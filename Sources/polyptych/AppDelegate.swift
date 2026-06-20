import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: InputMode
    private var mpvController: MPVController?
    private var spannedWindows: [SpannedWindow] = []
    private var sliceViews: [SliceView] = []
    private var downloadedFile: String?

    init(mode: InputMode) {
        self.mode = mode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch mode {
        case .file(let path):
            guard FileManager.default.fileExists(atPath: path) else {
                fputs("polyptych: file not found: \(path)\n", stderr)
                NSApp.terminate(nil as Any?)
                return
            }
            DispatchQueue.main.async { [self] in
                startPlayback(filePath: path, isURL: false)
            }

        case .url(let url):
            DispatchQueue.main.async { [self] in
                startPlayback(filePath: url, isURL: true)
            }

        case .youtubeSearch(let query):
            DispatchQueue.global().async { [self] in
                if let path = Self.downloadYouTube(query) {
                    downloadedFile = path
                    DispatchQueue.main.async { [self] in
                        startPlayback(filePath: path, isURL: false)
                    }
                } else {
                    DispatchQueue.main.async {
                        fputs("polyptych: YouTube download failed\n", stderr)
                        NSApp.terminate(nil as Any?)
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let path = downloadedFile { try? FileManager.default.removeItem(atPath: path) }
        try? FileManager.default.removeItem(atPath: Self.tmpDir)
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

    // MARK: - YouTube download

    private static let tmpDir = "/tmp/polyptych-downloads"

    private static func downloadYouTube(_ query: String) -> String? {
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yt-dlp", "--default-search", "ytsearch",
                            "--format", "bestvideo[height<=?1080]+bestaudio/best",
                            "--merge-output-format", "mp4",
                            "--output", "\(tmpDir)/%(id)s.%(ext)s",
                            "--print", "after_move:\(tmpDir)/%(id)s.%(ext)s",
                            query]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fputs("polyptych: yt-dlp failed: \(error.localizedDescription)\n", stderr)
            return nil
        }

        guard process.terminationStatus == 0 else {
            fputs("polyptych: yt-dlp exited with status \(process.terminationStatus)\n", stderr)
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            fputs("polyptych: downloaded file not found\n", stderr)
            return nil
        }

        return path
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
        let bezelFrac = 0.075  // 7.5% crop per side to compensate for monitor bezels

        for (i, sView) in sliceViews.enumerated() {
            guard i < slices.count else { break }
            var s = slices[i].1
            // Crop each slice horizontally to mask bezels
            let crop = Double(s.width) * bezelFrac
            s.origin.x += crop
            s.size.width -= crop * 2
            sView.updateSlice(
                from: mpv,
                sliceX: Int(Double(s.origin.x) * sx),
                sliceY: Int(Double(s.origin.y) * sy),
                sliceW: Int(Double(s.width) * sx),
                sliceH: Int(Double(s.height) * sy)
            )
        }
    }

    // MARK: - Sync

    private var syncDelay: Double = 0

    private func setSyncDelay(_ seconds: Double, mpv: MPVController) {
        syncDelay = seconds
        mpv.cmd(["set", "audio-delay", String(format: "%.2f", seconds)])
        for view in sliceViews {
            if view.frameDelay > 0 { view.frameDelay = seconds }
        }
        mpv.cmd(["show-text", String(format: "Delay: %dms", Int(seconds * 1000)), "1000"])
    }

    // MARK: - Keyboard

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
