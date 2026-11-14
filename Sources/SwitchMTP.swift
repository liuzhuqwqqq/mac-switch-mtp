import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Darwin

struct InstallTarget: Identifiable {
    let id: UInt32
    let name: String
    let free: UInt64
}

struct QueueItem: Identifiable {
    let id = UUID()
    let url: URL
    let size: UInt64
    var state = "等待"
}

// Each pipe can deliver partial UTF-8 sequences or several JSON records at once.
final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    func feed(_ data: Data, consume: (String) -> Void) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<end], as: UTF8.self)
            buffer.removeSubrange(...end)
            consume(line)
        }
    }
}

final class Installer: ObservableObject {
    @Published var items: [QueueItem] = []
    @Published var targets: [InstallTarget] = []
    @Published var selectedTarget: UInt32 = 0
    @Published var connected = false
    @Published var connecting = false
    @Published var running = false
    @Published var cancelling = false
    @Published var status = "等待连接 Switch"
    @Published var notice = ""
    @Published var logs = ""
    @Published var sent: UInt64 = 0
    @Published var total: UInt64 = 0
    @Published var speed: Double = 0
    @Published var currentID: UUID?
    private var process: Process?
    private var input: FileHandle?
    private var startedAt = Date()
    private var activity: NSObjectProtocol?
    var quitAfterCancel = false
    var busy: Bool { running || connecting }
    var queuedSize: UInt64 { items.reduce(0) { $0 + $1.size } }
    var fraction: Double { total > 0 ? min(1, Double(sent) / Double(total)) : 0 }
    var currentName: String { items.first { $0.id == currentID }?.url.lastPathComponent ?? "" }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    func log(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs += "[\(time)] \(text)\n"
        if logs.count > 100_000 { logs = String(logs.suffix(80_000)) }
    }

    func launch() {
        guard process == nil else { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mtp-helper")
        let child = Process()
        child.executableURL = helper
        let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        child.standardInput = stdinPipe; child.standardOutput = stdoutPipe; child.standardError = stderrPipe
        let outputReader = LineReader(), errorReader = LineReader()
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            outputReader.feed(data) { line in
                DispatchQueue.main.async { self?.handle(line) }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            errorReader.feed(data) { line in
                DispatchQueue.main.async { if !line.isEmpty { self?.log(line) } }
            }
        }
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.process = nil; self.input = nil; self.connected = false; self.connecting = false
                if self.running { self.setCurrentState("失败"); self.finishQueue() }
                self.status = "连接进程已退出"
                self.log("MTP helper 已退出；点击连接可重新启动。")
            }
        }
        do {
            try child.run(); process = child; input = stdinPipe.fileHandleForWriting
            log("本机 MTP 组件已启动。")
        } catch { notice = "无法启动 MTP 组件：\(error.localizedDescription)"; connecting = false }
    }

    private func command(_ value: String) {
        do { try input?.write(contentsOf: Data((value + "\n").utf8)) }
        catch { notice = "连接进程通信失败：\(error.localizedDescription)"; log(notice); connected = false; connecting = false; finishQueue() }
    }

    func connect() {
        guard !busy else { return }
        notice = ""; connected = false; targets = []; selectedTarget = 0
        if process == nil { launch() }
        guard process != nil else { return }
        connecting = true; status = "正在连接 DBI…"; log(status); command("connect")
    }

    func disconnect() {
        guard !busy else { return }
        command("disconnect"); connected = false; targets = []; selectedTarget = 0
        status = "已断开连接"
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择安装文件"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["nsp", "nsz", "xci", "xcz"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    func addFiles(_ urls: [URL]) {
        guard !busy else { return }
        var rejected: [String] = []
        for url in urls {
            let path = url.path
            guard ["nsp", "nsz", "xci", "xcz"].contains(url.pathExtension.lowercased()),
                  !path.contains("\n"), !path.contains("\r"), !path.contains("\t"),
                  let attr = try? FileManager.default.attributesOfItem(atPath: path),
                  attr[.type] as? FileAttributeType == .typeRegular,
                  let size = (attr[.size] as? NSNumber)?.uint64Value, size > 0,
                  FileManager.default.isReadableFile(atPath: path)
            else { rejected.append(url.lastPathComponent); continue }
            if !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                items.append(QueueItem(url: url, size: size))
            }
        }
        if !rejected.isEmpty { notice = "无法加入文件：\(rejected.joined(separator: "、"))。支持非空的 NSP / NSZ / XCI / XCZ 文件；路径不能包含制表符或换行。" }
    }

    func start() {
        guard connected, !busy, targets.contains(where: { $0.id == selectedTarget }), !items.isEmpty else { return }
        for i in items.indices where items[i].state == "失败" || items[i].state == "已取消" { items[i].state = "等待" }
        guard items.contains(where: { $0.state == "等待" }) else { return }
        notice = ""; running = true; cancelling = false
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "向 Switch 传输安装文件")
        nextFile()
    }

    private func nextFile() {
        guard running, !cancelling else { finishQueue(); return }
        guard let item = items.first(where: { $0.state == "等待" }) else {
            status = "队列传输完成"; notice = "文件已传给 DBI。请在 Switch 上确认安装结果。"; finishQueue(); return
        }
        currentID = item.id; setCurrentState("传输中")
        sent = 0; total = item.size; speed = 0; startedAt = Date()
        status = "正在传输到 SD 卡安装入口"
        command("send\t\(selectedTarget)\t\(item.url.path)")
    }

    private func setCurrentState(_ state: String) {
        if let i = items.firstIndex(where: { $0.id == currentID }) { items[i].state = state }
    }

    func cancel() {
        guard running, !cancelling, let process else { return }
        cancelling = true; status = "正在请求取消…"; log("已请求取消；等待当前 USB 操作返回。")
        kill(process.processIdentifier, SIGUSR1)
    }

    private func finishQueue() {
        running = false; cancelling = false; currentID = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        if quitAfterCancel { shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["event"] as? String else { log(line); return }
        let message = event["message"] as? String ?? ""
        switch type {
        case "ready": break
        case "connected":
            targets = (event["storages"] as? [[String: Any]] ?? []).compactMap { entry in
                guard let id = entry["id"] as? NSNumber, let name = entry["name"] as? String else { return nil }
                return InstallTarget(id: id.uint32Value, name: name, free: (entry["free"] as? NSNumber)?.uint64Value ?? 0)
            }
            selectedTarget = targets.first?.id ?? 0; connected = !targets.isEmpty; connecting = false
            status = connected ? "Switch 已连接 · DBI MTP" : "没有 SD 卡安装入口"
            log(status)
        case "progress":
            sent = (event["sent"] as? NSNumber)?.uint64Value ?? 0
            if let size = event["total"] as? NSNumber, size.uint64Value > 0 { total = size.uint64Value }
            speed = Double(sent) / max(0.1, Date().timeIntervalSince(startedAt))
        case "sending": log("开始传输：\(message)")
        case "sent":
            sent = total; setCurrentState("已传输"); log(message)
            if cancelling { status = "已停止后续队列"; finishQueue() }
            else { nextFile() }
        case "cancelled", "error":
            if running { setCurrentState(type == "cancelled" ? "已取消" : "失败") }
            status = type == "cancelled" ? "传输已取消" : "连接或传输遇到问题"
            notice = message; log(message); connected = false; connecting = false
            targets = []; selectedTarget = 0; finishQueue()
        case "disconnected": connected = false; log(message)
        default: if !message.isEmpty { log(message) }
        }
    }

    func shutdown() { if !running { command("quit"); try? input?.close() } }
    func copyLogs() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(logs, forType: .string) }
}

struct ContentView: View {
    @ObservedObject var model: Installer
    @State private var hovering = false
    @State private var showLogs = false
    private let green = Color(red: 0.11, green: 0.46, blue: 0.38)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 29)).foregroundStyle(green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Switch MTP").font(.title2.bold())
                        Text("Mac → DBI → SD 卡").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 13) {
                    Label(model.connected ? "设备已连接" : "等待设备", systemImage: model.connected ? "checkmark.circle.fill" : "cable.connector")
                        .font(.headline).foregroundStyle(model.connected ? green : .secondary)
                    Text(model.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(action: model.connect) {
                        HStack { if model.connecting { ProgressView().controlSize(.small) }; Text(model.connected ? "重新连接" : "连接 Switch").frame(maxWidth: .infinity) }
                    }.buttonStyle(.borderedProminent).tint(green).disabled(model.busy)
                    if model.connected { Button("断开连接", action: model.disconnect).disabled(model.busy) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("连接方法").font(.headline)
                    step("1", "Switch 打开 DBI")
                    step("2", "进入 Run MTP responder")
                    step("3", "用 USB 数据线直连 Mac")
                    step("4", "连接后添加文件并开始传输")
                }
                Spacer()
                Text("支持 NSP · NSZ · XCI · XCZ\n64 位文件大小 · 流式传输\n仅用于你有权使用的安装文件")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(5)
                Text("试用版 0.1 · Apple Silicon").font(.caption2).foregroundStyle(.tertiary)
            }.padding(26).frame(width: 270).background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("传到 Switch，交给 DBI 安装").font(.system(size: 25, weight: .semibold))
                        Text("直接传入 SD 卡安装入口，无需先复制完整文件到 SD 卡。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if !model.notice.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                        Text(model.notice).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Button { model.notice = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.font(.callout).padding(12).background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 29)).foregroundStyle(green)
                    Text("将安装文件拖到这里").font(.headline)
                    Button("选择文件…", action: model.chooseFiles).disabled(model.busy)
                    Text("可一次添加多个文件，按队列依次传输").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 19)
                    .background(hovering ? green.opacity(0.12) : green.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(green.opacity(hovering ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                    .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
                        guard !model.busy else { return false }
                        for provider in providers {
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                if let url { DispatchQueue.main.async { model.addFiles([url]) } }
                            }
                        }
                        return true
                    }
                HStack {
                    Text("传输队列").font(.headline)
                    Text("\(model.items.count) 个文件 · \(Installer.bytes(model.queuedSize))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("清空") { model.items = [] }.disabled(model.busy || model.items.isEmpty)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if model.items.isEmpty {
                            Text("添加文件后，它们会显示在这里。")
                                .foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 33)
                        }
                        ForEach(model.items) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.state == "已传输" ? "checkmark.circle.fill" : "doc.zipper")
                                    .foregroundStyle(item.state == "已传输" ? green : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle).help(item.url.path)
                                    Text(Installer.bytes(item.size)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.state).font(.caption).foregroundStyle(.secondary)
                                Button { model.items.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.plain).disabled(model.busy)
                            }.padding(11)
                            Divider()
                        }
                    }
                }.frame(minHeight: 100, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                if model.running {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.currentName).font(.callout).lineLimit(1).truncationMode(.middle)
                        ProgressView(value: model.fraction).tint(green)
                        HStack {
                            Text("\(Installer.bytes(model.sent)) / \(Installer.bytes(model.total))")
                            Spacer()
                            Text(model.cancelling ? "等待取消…" : "\(Int(model.fraction * 100))% · \(Installer.bytes(UInt64(max(0, model.speed))))/s")
                        }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                HStack {
                    if model.targets.count > 1 {
                        Picker("安装入口", selection: $model.selectedTarget) {
                            ForEach(model.targets) { Text($0.name).tag($0.id) }
                        }.disabled(model.busy)
                    } else {
                        Label(model.targets.first?.name ?? "安装位置：SD 卡", systemImage: "sdcard")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.running {
                        Button("取消传输", action: model.cancel).disabled(model.cancelling)
                    } else {
                        Button("开始传输安装", action: model.start)
                            .buttonStyle(.borderedProminent).tint(green).controlSize(.large)
                            .disabled(!model.connected || model.busy || !model.items.contains { $0.state != "已传输" })
                    }
                }
                DisclosureGroup(isExpanded: $showLogs) {
                    VStack(alignment: .trailing, spacing: 5) {
                        ScrollView {
                            Text(model.logs.isEmpty ? "暂无日志" : model.logs).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 100)
                        Button("复制日志", action: model.copyLogs).controlSize(.small)
                    }.padding(.top, 7)
                } label: { Text("连接与传输日志").font(.caption).foregroundStyle(.secondary) }
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 970, minHeight: 720)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number).font(.caption.bold()).foregroundStyle(green).frame(width: 19, height: 19)
                .background(green.opacity(0.10), in: Circle())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Installer()
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let mainMenu = NSMenu()
        let item = NSMenuItem(); mainMenu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Switch MTP", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Switch MTP", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; NSApp.mainMenu = mainMenu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Switch MTP · DBI 安装助手"
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        model.launch()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.running {
            let alert = NSAlert()
            alert.messageText = "正在向 Switch 传输文件"
            alert.informativeText = "取消传输后退出。请在 Switch 的 DBI 中确认当前安装状态。"
            alert.addButton(withTitle: "继续传输"); alert.addButton(withTitle: "取消传输并退出")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            model.quitAfterCancel = true; model.cancel(); return .terminateLater
        }
        model.shutdown(); return .terminateNow
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
