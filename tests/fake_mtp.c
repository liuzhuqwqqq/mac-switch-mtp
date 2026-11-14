/* Protocol-boundary fixture. No USB library is linked into this test binary. */
#include <libmtp.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <sys/stat.h>

static int mode(const char *s) { const char *v = getenv("FAKE_MTP"); return v && !strcmp(v, s); }
static LIBMTP_devicestorage_t sd, install, nand;
static LIBMTP_mtpdevice_t device;
static LIBMTP_error_t error = { .errornumber = LIBMTP_ERROR_GENERAL, .error_text = "模拟 USB 传输错误：\"错误\"\n详情" };

void LIBMTP_Init(void) { printf("fixture: unsolicited library stdout\n"); }
LIBMTP_error_number_t LIBMTP_Detect_Raw_Devices(LIBMTP_raw_device_t **raw, int *count) {
    if (mode("none")) { *raw = NULL; *count = 0; return LIBMTP_ERROR_NO_DEVICE_ATTACHED; }
    *count = mode("multiple") ? 2 : 1;
    *raw = calloc(*count, sizeof(**raw));
    for (int i = 0; i < *count; ++i) (*raw)[i].device_entry.vendor_id = mode("foreign") ? 0x1234 : 0x057e;
    return LIBMTP_ERROR_NONE;
}
LIBMTP_mtpdevice_t *LIBMTP_Open_Raw_Device_Uncached(LIBMTP_raw_device_t *raw) {
    if (raw->device_entry.vendor_id != 0x057e) abort();
    if (mode("openfail")) return NULL;
    sd = (LIBMTP_devicestorage_t){ .id = 65537, .StorageDescription = "1: SD Card", .next = &install };
    install = (LIBMTP_devicestorage_t){ .id = 327681, .StorageDescription = mode("nostorage") ? "7: Saves" : "5: SD Card install", .FreeSpaceInBytes = 100000000000ULL, .next = &nand };
    nand = (LIBMTP_devicestorage_t){ .id = 393217, .StorageDescription = "6: NAND install" };
    device.storage = &sd;
    return &device;
}
int LIBMTP_Get_Storage(LIBMTP_mtpdevice_t *d, int sort) { (void)d; (void)sort; return mode("storagefail") ? -1 : 0; }
void LIBMTP_Release_Device(LIBMTP_mtpdevice_t *d) { (void)d; }
LIBMTP_error_t *LIBMTP_Get_Errorstack(LIBMTP_mtpdevice_t *d) { (void)d; return &error; }
void LIBMTP_Clear_Errorstack(LIBMTP_mtpdevice_t *d) { (void)d; }
LIBMTP_file_t *LIBMTP_new_file_t(void) { return calloc(1, sizeof(LIBMTP_file_t)); }
void LIBMTP_destroy_file_t(LIBMTP_file_t *f) { free(f->filename); free(f); }
int LIBMTP_Send_File_From_File_Descriptor(LIBMTP_mtpdevice_t *d, int fd, LIBMTP_file_t *f, LIBMTP_progressfunc_t cb, const void *data) {
    (void)d;
    struct stat st; if (fstat(fd, &st) || (uint64_t)st.st_size != f->filesize ||
        f->parent_id != UINT32_MAX || f->storage_id != 327681 || !f->filename || f->filetype != LIBMTP_FILETYPE_UNKNOWN) abort();
    if (mode("sendfail")) return -1;
    if (mode("cancel")) raise(SIGUSR1);
    if (cb(0, f->filesize, data)) return -1;
    if (cb(f->filesize, f->filesize, data)) return -1;
    return 0;
}
