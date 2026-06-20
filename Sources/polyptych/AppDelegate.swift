import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: InputMode
    private var mpvController: MPVController?
    private var spannedWindows: [SpannedWindow] = []
    private var sliceViews: [SliceView] = []
    private var downloadedFile: String?
    private var cachedConfig = Config.load()
    private var cachedSlices: [(NSScreen, NSRect)] = []
    private var cachedUnion: NSRect = .zero
    private var cachedSx: Double = 0
    private var cachedSy: Double = 0

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
        // Don't clean up — keep for cache
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

        // Render at video-like resolution (1920x1080) instead of full union.
        // SW renderer processes 2MP instead of 6MP per frame — much faster.
        // GPU (CALayer) handles the final stretch to fill all displays.
        let renderW = CInt(1920)
        let renderH = CInt(1080)

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

            if hasDL && nativeIDs.contains(view.displayID) {
                frameDelay = 0.05
                view.frameDelay = frameDelay
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        mpv.start(file: filePath, isURL: isURL)
        let initAudio = isURL ? 0.0 : (hasDL ? 0.15 : 0.0)
        audioDelay = initAudio
        if initAudio > 0 { mpv.cmd(["set", "audio-delay", String(format: "%.2f", initAudio)]) }

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }

        // Cache display layout for the render loop
        let s = DisplayLayout.selectedScreens()
        cachedUnion = DisplayLayout.unionRect(of: s)
        cachedSlices = DisplayLayout.slices(for: s, relativeTo: cachedUnion)
        cachedSx = Double(mpv.renderWidth) / Double(cachedUnion.width)
        cachedSy = Double(mpv.renderHeight) / Double(cachedUnion.height)
    }

    // MARK: - YouTube download

    private static let tmpDir = "/tmp/polyptych-downloads"
    private static let maxCacheAge: TimeInterval = 7 * 86400  // 7 days

    private static func downloadYouTube(_ query: String) -> String? {
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        cleanupOldCache()

        // Step 1: resolve video ID quickly to check cache
        guard let videoID = resolveVideoID(query) else {
            fputs("polyptych: could not resolve video ID\n", stderr)
            return nil
        }

        // Step 2: check for cached file
        if let cached = findCacheFile(videoID) { return cached }

        // Step 3: download
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
            fputs("polyptych: yt-dlp download failed: \(error.localizedDescription)\n", stderr)
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

    private static func resolveVideoID(_ query: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["yt-dlp", "--default-search", "ytsearch",
                       "--print", "id", "--no-warnings", query]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch { return nil }
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }

    private static func findCacheFile(_ videoID: String) -> String? {
        let dir = URL(fileURLWithPath: tmpDir)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir) else { return nil }
        for f in files where f.hasPrefix(videoID) {
            let path = dir.appendingPathComponent(f).path
            return path
        }
        return nil
    }

    private static func cleanupOldCache() {
        let dir = URL(fileURLWithPath: tmpDir)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir) else { return }
        let now = Date()
        for f in files {
            let path = dir.appendingPathComponent(f).path
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let mtime = attrs[.modificationDate] as? Date,
                  now.timeIntervalSince(mtime) > maxCacheAge else { continue }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Render

    private func renderFrame() {
        guard let mpv = mpvController else { return }
        guard mpv.renderFrame() else { return }

        let bezelFrac = cachedConfig.bezel.gaps.first ?? 0.075

        for (i, sView) in sliceViews.enumerated() {
            guard i < cachedSlices.count else { break }
            var s = cachedSlices[i].1
            let crop = Double(s.width) * bezelFrac
            s.origin.x += crop
            s.size.width -= crop * 2
            sView.updateSlice(
                from: mpv,
                sliceX: Int(Double(s.origin.x) * cachedSx),
                sliceY: Int(Double(s.origin.y) * cachedSy),
                sliceW: Int(Double(s.width) * cachedSx),
                sliceH: Int(Double(s.height) * cachedSy)
            )
        }
    }

    // MARK: - Sync

    private var audioDelay: Double = 0
    private var frameDelay: Double = 0

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
                // Audio delay: [ ]
                case "[":
                    audioDelay = max(0, audioDelay - 0.05)
                    mpv.cmd(["set", "audio-delay", String(format: "%.2f", audioDelay)])
                    mpv.cmd(["show-text", String(format: "Audio: %dms", Int(audioDelay * 1000)), "1000"])
                case "]":
                    audioDelay = min(1.0, audioDelay + 0.05)
                    mpv.cmd(["set", "audio-delay", String(format: "%.2f", audioDelay)])
                    mpv.cmd(["show-text", String(format: "Audio: %dms", Int(audioDelay * 1000)), "1000"])
                // Frame delay (video sync between monitors): { }
                case "{":
                    frameDelay = max(0, frameDelay - 0.05)
                    for view in sliceViews { if view.frameDelay > 0 { view.frameDelay = frameDelay } }
                    mpv.cmd(["show-text", String(format: "Frame: %dms", Int(frameDelay * 1000)), "1000"])
                case "}":
                    frameDelay = min(1.0, frameDelay + 0.05)
                    for view in sliceViews { if view.frameDelay > 0 { view.frameDelay = frameDelay } }
                    mpv.cmd(["show-text", String(format: "Frame: %dms", Int(frameDelay * 1000)), "1000"])
                default: break
                }
            }
        }
    }
}
