import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let filePath: String?
    private let isURL: Bool
    private var mpvController: MPVController?
    private var spannedWindows: [SpannedWindow] = []
    private var sliceViews: [SliceView] = []

    init(filePath: String?, isURL: Bool) {
        self.filePath = filePath
        self.isURL = isURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = filePath else {
            fputs("Usage: polyptych <video-file-or-url>\n", stderr)
            NSApp.terminate(nil as Any?)
            return
        }

        if !isURL && !FileManager.default.fileExists(atPath: path) {
            fputs("polyptych: file not found: \(path)\n", stderr)
            NSApp.terminate(nil as Any?)
            return
        }

        if isURL {
            DispatchQueue.global().async { [self] in
                let resolved = Self.resolveURL(path)
                DispatchQueue.main.async { [self] in
                    startPlayback(filePath: resolved, isURL: true)
                }
            }
        } else {
            DispatchQueue.main.async { [self] in
                startPlayback(filePath: path, isURL: false)
            }
        }
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Setup

    private func startPlayback(filePath: String, isURL: Bool) {
        let screens = DisplayLayout.selectedScreens()
        let union = DisplayLayout.unionRect(of: screens)
        let slices = DisplayLayout.slices(for: screens, relativeTo: union)

        let renderScale: Double = 1.0
        let renderW = CInt(Double(union.width) * renderScale)
        let renderH = CInt(Double(union.height) * renderScale)

        let mpv = MPVController(unionWidth: renderW, unionHeight: renderH)
        self.mpvController = mpv

        let (nativeScreens, dlScreens) = DisplayDetector.classifyDisplays()
        let nativeIDs = Set(nativeScreens.map { DisplayDetector.displayID(for: $0) })
        let hasDL = !dlScreens.isEmpty

        for (s, _) in slices {
            let view = SliceView()
            view.displayID = DisplayDetector.displayID(for: s)
            let win = SpannedWindow(screenFrame: s.frame)
            win.contentView = view
            spannedWindows.append(win)
            sliceViews.append(view)
            win.makeKeyAndOrderFront(nil)

            let dlDelay = hasDL ? 0.20 : 0.0
            let networkDelay = isURL ? 0.0 : dlDelay
            if hasDL && nativeIDs.contains(view.displayID) {
                view.frameDelay = dlDelay
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        mpv.start(file: filePath, isURL: isURL)
        let initialDelay = isURL ? 0.0 : (hasDL ? 0.20 : 0.0)
        if initialDelay > 0 { setSyncDelay(initialDelay, mpv: mpv) }

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    // MARK: - URL resolution

    private static func resolveURL(_ url: String) -> String {
        let search = url.hasPrefix("ytdl://") ? String(url.dropFirst(7)) : url
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yt-dlp", "--get-url", "--default-search", "ytsearch",
                            "--format", "best[height<=?1080]", search]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return url }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return url }
        return output.components(separatedBy: "\n").first ?? output
    }

    // MARK: - Render

    private func renderFrame() {

        guard let mpv = mpvController else { return }
        let screens = DisplayLayout.selectedScreens()
        let union = DisplayLayout.unionRect(of: screens)
        let slices = DisplayLayout.slices(for: screens, relativeTo: union)

        guard mpv.renderFrame() else { return }

        let sx = Double(mpv.renderWidth) / Double(union.width)
        let sy = Double(mpv.renderHeight) / Double(union.height)

        for (i, sView) in sliceViews.enumerated() {
            guard i < slices.count else { break }
            let s = slices[i].1
            sView.updateSlice(
                from: mpv,
                sliceX: Int(Double(s.origin.x) * sx),
                sliceY: Int(Double(s.origin.y) * sy),
                sliceW: Int(Double(s.width) * sx),
                sliceH: Int(Double(s.height) * sy)
            )
        }
    }

    // MARK: - Keyboard

    private var syncDelay: Double = 0

    private func setSyncDelay(_ seconds: Double, mpv: MPVController) {
        syncDelay = seconds
        mpv.cmd(["set", "audio-delay", String(format: "%.2f", seconds)])
        for view in sliceViews {
            if view.frameDelay > 0 { view.frameDelay = seconds }
        }
        mpv.cmd(["show-text", String(format: "Delay: %dms", Int(seconds * 1000)), "1000"])
    }

    private func handleKey(_ event: NSEvent) {
        guard let mpv = mpvController else { return }
        switch event.keyCode {
        case 123: mpv.cmd(["seek", "-5"])
        case 124: mpv.cmd(["seek", "5"])
        case 125: mpv.cmd(["seek", "-60"])
        case 126: mpv.cmd(["seek", "60"])
        default:
            if let chars = event.characters {
                switch chars {
                case " ": mpv.cmd(["cycle", "pause"])
                case "q", "\u{1b}": NSApp.terminate(nil as Any?)
                case "[":
                    setSyncDelay(max(0, syncDelay - 0.05), mpv: mpv)
                case "]":
                    setSyncDelay(min(1.0, syncDelay + 0.05), mpv: mpv)
                default: break
                }
            }
        }
    }
}
