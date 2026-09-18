import SwiftUI
import AppKit
import DouyinCore

@MainActor
final class PlayerModel: ObservableObject {
    @Published var input = UserDefaults.standard.string(forKey: "lastInput") ?? ""
    @Published var mpvPath = UserDefaults.standard.string(forKey: "mpvPath") ?? ""
    @Published var autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true
    @Published var streams: [LiveStream] = []
    @Published var selection = ""
    @Published var busy = false
    @Published var status = "就绪"
    @Published var isError = false
    @Published var roomID = ""
    private var task: Task<Void, Never>?
    var selected: LiveStream? { streams.first { $0.id == selection } }
    var effectiveMPV: String? {
        let custom = mpvPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = custom.isEmpty ? ["/Applications/mpv.app/Contents/MacOS/mpv", NSHomeDirectory() + "/Applications/mpv.app/Contents/MacOS/mpv", "/opt/homebrew/bin/mpv", "/usr/local/bin/mpv"] : [(custom as NSString).expandingTildeInPath]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func resolve(play: Bool) {
        guard !busy else { return }
        let id: String
        do { id = try LiveResolver.roomID(from: input) }
        catch { fail(error); return }
        if play && effectiveMPV == nil { failMessage("找不到 mpv，请在设置中选择本机 mpv 程序。"); return }
        busy = true; isError = false; status = "正在获取直播地址…"; roomID = id
        let preferred = selection
        streams = []; selection = ""
        UserDefaults.standard.set(input, forKey: "lastInput")
        task = Task {
            defer { busy = false }
            do {
                let result = try await LiveResolver.resolve(roomID: id)
                try Task.checkCancellation()
                streams = result
                selection = result.first(where: { $0.id == preferred })?.id ?? result[0].id
                status = "已获取 \(result.count) 个播放选项 · 房间 \(id)"
                if play { launch() }
            } catch is CancellationError { status = "已取消" }
            catch { if Task.isCancelled { status = "已取消" } else { fail(error) } }
        }
    }
    func cancel() { task?.cancel() }
    func fail(_ error: Error) { failMessage(error.localizedDescription) }
    func failMessage(_ message: String) { isError = true; status = message }
    func launch() {
        guard let stream = selected, let executable = effectiveMPV else { failMessage("找不到可执行的 mpv 程序。"); return }
        do {
            UserDefaults.standard.set(mpvPath, forKey: "mpvPath")
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("douyin2mpv")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let log = dir.appendingPathComponent("mpv.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            var arguments = ["--force-window=yes", "--title=抖音直播 \(roomID)"]
            if autoReconnect {
                let script = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/live-reconnect.lua").path
                guard FileManager.default.fileExists(atPath: script) else {
                    throw NSError(domain: "Douyin2MPV", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少自动恢复脚本，请重新构建应用。"])
                }
                let reconnect = "reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_on_http_error=5xx,reconnect_delay_max=3"
                arguments += ["--idle=yes", "--keep-open=no", "--network-timeout=15",
                    "--cache=yes", "--cache-secs=20", "--demuxer-max-bytes=64MiB",
                    "--stream-lavf-o=\(reconnect)", "--demuxer-lavf-o=\(reconnect)",
                    "--script=\(script)",
                    "--script-opts-append=douyin2mpv-room=\(roomID)",
                    "--script-opts-append=douyin2mpv-quality=\(stream.quality)",
                    "--script-opts-append=douyin2mpv-format=\(stream.format)"]
            }
            process.arguments = arguments + ["--", stream.url.absoluteString]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle; process.standardError = handle
            process.terminationHandler = { process in
                let code = process.terminationStatus
                if code != 0 {
                    Task { @MainActor [weak self] in
                        self?.failMessage("mpv 已退出（代码 \(code)）。可尝试其他清晰度或 FLV；诊断日志位于 ~/Library/Application Support/douyin2mpv/mpv.log。")
                    }
                }
            }
            try process.run()
            isError = false; status = "已启动 mpv · \(stream.label)"
        } catch { fail(error) }
    }
    func copyURL() {
        guard let stream = selected else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(stream.url.absoluteString, forType: .string)
        status = "已复制直播地址（有有效期）"; isError = false
    }
    func export() {
        guard let stream = selected else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "douyin-\(roomID).m3u"
        if panel.runModal() == .OK, let url = panel.url {
            do { try "#EXTM3U\n#EXTINF:-1,Douyin \(roomID)\n\(stream.url.absoluteString)\n".write(to: url, atomically: true, encoding: .utf8); status = "播放列表已保存（直播地址有有效期）"; isError = false }
            catch { fail(error) }
        }
    }
    func chooseMPV() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "选择 mpv.app 或 mpv 可执行文件"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            mpvPath = url.pathExtension == "app" ? url.appendingPathComponent("Contents/MacOS/mpv").path : url.path
            UserDefaults.standard.set(mpvPath, forKey: "mpvPath")
        }
    }
    func openRoom() {
        if let id = try? LiveResolver.roomID(from: input), let url = URL(string: "https://live.douyin.com/\(id)") { NSWorkspace.shared.open(url) }
    }
}

// Keep native window dragging while using an opaque, system-colored surface.
struct SystemWindow: NSViewRepresentable {
    final class Surface: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
    }
    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ nsView: Surface, context: Context) {}
}

struct ContentView: View {
    @StateObject private var model = PlayerModel()
    @State private var settingsOpen = false
    @State private var hoveringPlay = false
    @FocusState private var inputFocused: Bool
    private var tint: Color { model.isError ? .orange : .green }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DOUYIN / MPV")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2.8)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 82)
                Spacer()
                Button { settingsOpen.toggle() } label: {
                    Image(systemName: "gearshape").font(.system(size: 16, weight: .light))
                        .foregroundStyle(.secondary).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).accessibilityLabel("设置").help("画质与播放器设置")
                .popover(isPresented: $settingsOpen, arrowEdge: .bottom) { settings }
            }.frame(height: 34)

            HStack(spacing: 22) {
                Image(nsImage: NSImage(contentsOfFile: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.png").path) ?? NSImage(named: NSImage.applicationIconName)!)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 56, height: 56).accessibilityHidden(true)
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 52)
                TextField("", text: $model.input, prompt: Text("粘贴抖音直播链接").foregroundColor(.secondary))
                    .font(.system(size: model.input.isEmpty ? 28 : 19, weight: .light))
                    .textFieldStyle(.plain).foregroundStyle(.primary)
                    .focused($inputFocused).disabled(model.busy)
                    .accessibilityLabel("抖音直播链接或房间号")
                    .onSubmit { model.resolve(play: true) }
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 52)
                Button {
                    if model.busy { model.cancel() } else { model.resolve(play: true) }
                } label: {
                    ZStack {
                        Circle().fill(Color.primary.opacity(hoveringPlay ? 0.09 : 0.025))
                        Circle().strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.5)
                        Image(systemName: model.busy ? "stop.fill" : "play.fill")
                            .font(.system(size: model.busy ? 19 : 26, weight: .regular))
                            .offset(x: model.busy ? 0 : 2).foregroundStyle(.primary)
                    }.frame(width: 64, height: 64).contentShape(Circle())
                }
                .buttonStyle(.plain).onHover { hoveringPlay = $0 }
                .accessibilityLabel(model.busy ? "取消解析" : "用 mpv 播放")
                .help(model.busy ? "取消解析" : "播放 · Return")
                .keyboardShortcut(.return, modifiers: [])
                .animation(.easeOut(duration: 0.15), value: hoveringPlay)
            }.padding(.horizontal, 17).frame(height: 92)

            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
            HStack(spacing: 9) {
                if model.busy {
                    ProgressView().controlSize(.mini).frame(width: 10, height: 10)
                } else {
                    Circle().fill(tint).frame(width: 8, height: 8)
                }
                Text(model.status).font(.system(size: 11, weight: .regular))
                    .foregroundStyle(model.isError ? Color.orange : Color.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).help(model.status)
                    .accessibilityLabel("状态：\(model.status)")
                Spacer(minLength: 0)
            }.padding(.horizontal, 14).frame(height: 24)
        }
        .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 2)
        .frame(width: 880, height: 156)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .background(SystemWindow())
        .onChange(of: model.mpvPath) { value in UserDefaults.standard.set(value, forKey: "mpvPath") }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("播放设置").font(.headline)
            Toggle("断流自动恢复", isOn: $model.autoReconnect)
                .onChange(of: model.autoReconnect) { UserDefaults.standard.set($0, forKey: "autoReconnect") }
            Text("下次播放生效；连续失败最多重试 5 次，关闭播放器即停止。")
                .font(.caption).foregroundStyle(.secondary)
            if !model.streams.isEmpty {
                Picker("画质 / 格式", selection: $model.selection) {
                    ForEach(model.streams) { Text($0.label).tag($0.id) }
                }
                Text("选择后点击主界面的播放键生效。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("解析画质") { model.resolve(play: false) }.disabled(model.busy || model.input.isEmpty)
                Button("浏览器打开") { model.openRoom() }.disabled(model.input.isEmpty)
            }
            if model.selected != nil {
                HStack {
                    Button("复制直播地址") { model.copyURL() }
                    Button("导出 M3U") { model.export() }
                }
            }
            Divider()
            Text("mpv 播放器").font(.subheadline)
            HStack {
                TextField("自动检测", text: $model.mpvPath).textFieldStyle(.roundedBorder)
                Button("选择…") { model.chooseMPV() }
            }
            Text(model.effectiveMPV ?? "未找到 mpv，请选择可执行文件。")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("支持直播间链接、房间号及含 live_web_rid 的链接。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 400).background(Color(nsColor: .windowBackgroundColor))
    }
}

@main
struct Douyin2MPVApp: App {
    var body: some Scene {
        Window("Douyin2MPV", id: "main") {
            ZStack(alignment: .top) {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                ContentView().ignoresSafeArea()
            }
            .frame(width: 880, height: 128)
        }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .defaultSize(width: 880, height: 156)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
