#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <time.h>
#include <errno.h>

/* A private duplicate of stdout keeps libmtp diagnostics out of the JSON stream. */
static FILE *events;
static LIBMTP_mtpdevice_t *device;
static volatile sig_atomic_t cancelled;
static uint64_t last_tick;

static void quoted(const char *s) {
    fputc('"', events);
    for (const unsigned char *p = (const unsigned char *)(s ? s : ""); *p; ++p) {
        switch (*p) {
            case '"': fputs("\\\"", events); break;
            case '\\': fputs("\\\\", events); break;
            case '\n': fputs("\\n", events); break;
            case '\r': fputs("\\r", events); break;
            case '\t': fputs("\\t", events); break;
            default:
                if (*p < 0x20) fprintf(events, "\\u%04x", *p);
                else fputc(*p, events);
        }
    }
    fputc('"', events);
}

static void message(const char *type, const char *text) {
    fputs("{\"event\":", events); quoted(type);
    fputs(",\"message\":", events); quoted(text); fputs("}\n", events);
    fflush(events);
}

static void release_device(void) {
    if (device) LIBMTP_Release_Device(device);
    device = NULL;
}

static void errors(void) {
    for (LIBMTP_error_t *e = LIBMTP_Get_Errorstack(device); e; e = e->next)
        message("log", e->error_text);
    LIBMTP_Clear_Errorstack(device);
}

static int is_sd_install(const char *name) {
    if (!name) return 0;
    return strcasestr(name, "sd") &&
        (strcasestr(name, "install") || strstr(name, "Установ") ||
         strstr(name, "установ") || strstr(name, "安装"));
}

static void connect_switch(void) {
    release_device();
    LIBMTP_raw_device_t *raw = NULL;
    int count = 0, index = -1, matches = 0;
    LIBMTP_error_number_t rc = LIBMTP_Detect_Raw_Devices(&raw, &count);
    if (rc != LIBMTP_ERROR_NONE && rc != LIBMTP_ERROR_NO_DEVICE_ATTACHED) {
        free(raw);
        message("error", "MTP 枚举失败。请重接 USB 数据线，并关闭其他 MTP 软件。");
        return;
    }
    for (int i = 0; i < count; ++i) {
        /* Never open phones or other vendors' MTP sessions. */
        if (raw[i].device_entry.vendor_id == 0x057e) { index = i; ++matches; }
    }
    if (matches != 1) {
        free(raw);
        message("error", matches ? "检测到多台 Nintendo 设备，请只连接一台 Switch。" :
            "未检测到 Switch MTP。请打开 DBI → Run MTP responder，使用 USB 数据线直连 Mac，再点连接。");
        return;
    }
    device = LIBMTP_Open_Raw_Device_Uncached(&raw[index]);
    free(raw);
    if (!device) {
        message("error", "发现 Nintendo 设备，但无法打开 MTP。请退出 OpenMTP、Android File Transfer 等软件，重启 DBI 的 MTP 模式并重新连接；若系统询问是否允许配件连接，请允许。");
        return;
    }
    if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) {
        errors(); release_device();
        message("error", "读取 DBI 安装入口失败，请重新进入 MTP 模式。"); return;
    }
    int targets = 0;
    fputs("{\"event\":\"connected\",\"storages\":[", events);
    for (LIBMTP_devicestorage_t *s = device->storage; s; s = s->next) {
        if (!is_sd_install(s->StorageDescription)) continue;
        if (targets++) fputc(',', events);
        fprintf(events, "{\"id\":%" PRIu32 ",\"name\":", s->id);
        quoted(s->StorageDescription);
        fprintf(events, ",\"free\":%" PRIu64 "}", s->FreeSpaceInBytes);
    }
    fputs("]}\n", events); fflush(events);
    if (!targets) {
        for (LIBMTP_devicestorage_t *s = device->storage; s; s = s->next)
            message("log", s->StorageDescription);
        release_device();
        message("error", "设备没有暴露 SD 安装入口。请在 DBI 配置的 MTP Storages 中启用 SD Card install，再重新进入 MTP 模式。");
    }
}

static void on_cancel(int sig) { (void)sig; cancelled = 1; }

static int progress(uint64_t sent, uint64_t total, const void *unused) {
    (void)unused;
    if (cancelled) return 1;
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    uint64_t tick = (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
    if (!last_tick || tick - last_tick >= 100 || sent == total) {
        fprintf(events, "{\"event\":\"progress\",\"sent\":%" PRIu64 ",\"total\":%" PRIu64 "}\n", sent, total);
        fflush(events); last_tick = tick;
    }
    return 0;
}

static int valid_extension(const char *name) {
    const char *ext = strrchr(name, '.');
    return ext && (!strcasecmp(ext, ".nsp") || !strcasecmp(ext, ".nsz") ||
                   !strcasecmp(ext, ".xci") || !strcasecmp(ext, ".xcz"));
}

static void send_file(const char *id_text, const char *path) {
    if (!device) { message("error", "连接已断开，请重新连接 Switch。"); return; }
    char *end = NULL; errno = 0;
    unsigned long id = strtoul(id_text, &end, 10);
    if (errno || !*id_text || *end || id > UINT32_MAX) {
        message("error", "安装入口 ID 无效。"); return;
    }
    LIBMTP_devicestorage_t *target = device->storage;
    while (target && target->id != id) target = target->next;
    if (!target || !is_sd_install(target->StorageDescription)) {
        message("error", "拒绝写入：目标不是 DBI 的 SD 安装入口。"); return;
    }
    const char *name = strrchr(path, '/'); name = name ? name + 1 : path;
    if (*path != '/' || !valid_extension(name)) {
        message("error", "请选择 NSP、NSZ、XCI 或 XCZ 文件。"); return;
    }
    int fd = open(path, O_RDONLY | O_NONBLOCK);
    struct stat st;
    if (fd < 0 || fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0) {
        if (fd >= 0) close(fd);
        message("error", "文件无法读取、不是普通文件或大小为 0。"); return;
    }
    LIBMTP_file_t *file = LIBMTP_new_file_t();
    if (!file) { close(fd); message("error", "内存分配失败。"); return; }
    file->filename = strdup(name);
    if (!file->filename) {
        LIBMTP_destroy_file_t(file); close(fd); message("error", "内存分配失败。"); return;
    }
    file->filesize = (uint64_t)st.st_size;
    file->filetype = LIBMTP_FILETYPE_UNKNOWN;
    file->storage_id = (uint32_t)id;
    file->parent_id = UINT32_MAX; /* SendObjectInfo uses 0xffffffff for an explicit storage root. */
    last_tick = 0;
    message("sending", name);
    int rc = cancelled ? -1 : LIBMTP_Send_File_From_File_Descriptor(device, fd, file, progress, NULL);
    LIBMTP_destroy_file_t(file); close(fd);
    if (rc != 0) {
        errors(); release_device();
        message(cancelled ? "cancelled" : "error", cancelled ?
            "传输已取消；请在 DBI 查看安装状态。再次传输前需要重新连接。" :
            "MTP 传输失败，队列已停止。请查看 Switch 的 DBI 提示与下方日志，再重新连接。");
        return;
    }
    message("sent", "MTP 传输完成；安装是否成功请以 Switch 的 DBI 提示为准。");
}

int main(void) {
    events = fdopen(dup(STDOUT_FILENO), "w");
    if (!events || dup2(STDERR_FILENO, STDOUT_FILENO) < 0) return 1;
    struct sigaction sa = {0}; sa.sa_handler = on_cancel; sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART; sigaction(SIGUSR1, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);
    LIBMTP_Init();
    message("ready", "MTP helper ready");
    char *line = NULL; size_t capacity = 0; ssize_t len;
    while ((len = getline(&line, &capacity, stdin)) >= 0) {
        if (len && line[len-1] == '\n') line[--len] = 0;
        if (!strcmp(line, "connect")) { cancelled = 0; connect_switch(); }
        else if (!strcmp(line, "disconnect")) { release_device(); message("disconnected", "已断开连接。"); }
        else if (!strcmp(line, "quit")) break;
        else if (!strncmp(line, "send\t", 5)) {
            char *path = strchr(line + 5, '\t');
            if (!path) message("error", "传输参数不完整。");
            else { *path++ = 0; send_file(line + 5, path); cancelled = 0; }
        } else message("error", "未知命令。");
    }
    free(line); release_device(); fclose(events); return 0;
}
