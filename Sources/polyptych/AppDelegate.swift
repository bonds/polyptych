import AppKit
import IOKit.pwr_mgt

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

        case .youtubeSearch(let query, let noCache):
            DispatchQueue.global().async { [self] in
                if let path = Self.downloadYouTube(query, noCache: noCache) {
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
        mpvController?.savePosition()
        IOPMAssertionRelease(sleepAssertion)
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        NSCursor.hide()
        mpvController?.cmd(["set", "pause", "no"])
        for w in spannedWindows { w.level = .floating }
        IOPMAssertionCreateWithName(
            "NoDisplaySleepAssertion" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "polyptych video playback" as CFString,
            &sleepAssertion)
    }

    func applicationDidResignActive(_ notification: Notification) {
        NSCursor.unhide()
        mpvController?.cmd(["set", "pause", "yes"])
        for w in spannedWindows { w.level = .normal }
        IOPMAssertionRelease(sleepAssertion)
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
                frameDelay = cachedConfig.frameDelay
                view.frameDelay = frameDelay
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        mpv.start(file: filePath, isURL: isURL)

        // Prevent display sleep and screensaver during playback
        IOPMAssertionCreateWithName(
            "NoDisplaySleepAssertion" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "polyptych video playback" as CFString,
            &sleepAssertion)

        let initAudio = isURL ? 0.0 : (hasDL ? cachedConfig.audioDelay : 0.0)
        audioDelay = initAudio
        if initAudio > 0 { mpv.cmd(["set", "audio-delay", String(format: "%.2f", initAudio)]) }

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKey(event) ?? false { return nil }
            return event
        }

        // Cache display layout for the render loop
        updateCachedLayout()
    }

    private func updateCachedLayout() {
        let s = DisplayLayout.selectedScreens()
        cachedUnion = DisplayLayout.unionRect(of: s)
        cachedSlices = DisplayLayout.slices(for: s, relativeTo: cachedUnion)
        cachedSx = Double(mpvController?.renderWidth ?? 1) / Double(max(cachedUnion.width, 1))
        cachedSy = Double(mpvController?.renderHeight ?? 1) / Double(max(cachedUnion.height, 1))
    }

    // MARK: - YouTube download

    private static let tmpDir = "/tmp/polyptych-downloads"
    private static let cacheIndexPath = "\(tmpDir)/.search_index.json"
    private static let maxCacheAge: TimeInterval = 7 * 86400

    private static func queryHash(_ query: String) -> String {
        var h = UInt64(5381)
        for byte in query.utf8 {
            h = ((h << 5) &+ h) &+ UInt64(byte)
        }
        return String(format: "%016llx", h)
    }

    private static func loadCacheIndex() -> [String: String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cacheIndexPath)),
              let idx = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return idx
    }

    private static func saveCacheIndex(_ idx: [String: String]) {
        if let data = try? JSONEncoder().encode(idx) {
            try? data.write(to: URL(fileURLWithPath: cacheIndexPath))
        }
    }

    private static func downloadYouTube(_ query: String, noCache: Bool = false) -> String? {
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        cleanupOldCache()

        let hash = queryHash(query)

        // --no-cache: purge existing cached file for this query
        if noCache {
            let idx = loadCacheIndex()
            if let oldID = idx[hash], let oldPath = findCacheFile(oldID) {
                try? FileManager.default.removeItem(atPath: oldPath)
            }
            var updated = idx
            updated.removeValue(forKey: hash)
            saveCacheIndex(updated)
        }

        let idx = loadCacheIndex()

        // Step 1: search-term hash cache — instant if we've seen this query before
        if !noCache, let videoID = idx[hash] {
            if let cached = findCacheFile(videoID) {
                fputs("[polyptych] search cache hit: \(query)\n", stderr)
                return cached
            }
        }

        // Step 2: resolve video ID
        guard let videoID = resolveVideoID(query) else {
            fputs("polyptych: could not resolve video ID\n", stderr)
            return nil
        }

        // Step 3: check video ID cache
        if let cached = findCacheFile(videoID) {
            var updated = idx
            updated[hash] = videoID
            saveCacheIndex(updated)
            return cached
        }

        // Step 4: download
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

        // Index the search hash for instant future lookups
        var updated = idx
        updated[hash] = videoID
        saveCacheIndex(updated)

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
            return dir.appendingPathComponent(f).path
        }
        return nil
    }

    private static func cleanupOldCache() {
        let dir = URL(fileURLWithPath: tmpDir)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir) else { return }
        let now = Date()
        for f in files where !f.hasPrefix(".") {  // don't clean index files
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

        let bezelFrac = cachedConfig.bezelGaps.first ?? 0.075

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
    private var sleepAssertion: IOPMAssertionID = IOPMAssertionID()


    private func saveConfig() {
        var cfg = cachedConfig
        cfg.audioDelay = audioDelay
        cfg.frameDelay = frameDelay
        cfg.bezelGaps = cachedConfig.bezelGaps
        Config.save(cfg)
        cachedConfig = cfg
    }

    // MARK: - Keyboard

    /// Returns true if the key was handled (event swallowed).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let mpv = mpvController else { return false }
        switch event.keyCode {
        case 123: mpv.cmd(["seek", "-5"]); return true
        case 124: mpv.cmd(["seek", "5"]); return true
        case 125: mpv.cmd(["seek", "-60"]); return true
        case 126: mpv.cmd(["seek", "60"]); return true
        default:
            if let chars = event.characters {
                switch chars {
                case " ": mpv.cmd(["cycle", "pause"]); return true
                case "q", "\u{1b}":
                    mpv.savePosition()
                    NSApp.terminate(nil as Any?)
                    return true
                case "[":
                    audioDelay = max(0, audioDelay - 0.05)
                    mpv.cmd(["set", "audio-delay", String(format: "%.2f", audioDelay)])
                    mpv.cmd(["show-text", String(format: "Audio: %dms", Int(audioDelay * 1000)), "1000"])
                    saveConfig(); return true
                case "]":
                    audioDelay = min(1.0, audioDelay + 0.05)
                    mpv.cmd(["set", "audio-delay", String(format: "%.2f", audioDelay)])
                    mpv.cmd(["show-text", String(format: "Audio: %dms", Int(audioDelay * 1000)), "1000"])
                    saveConfig(); return true
                case "{":
                    frameDelay = max(0, frameDelay - 0.05)
                    for view in sliceViews { if view.frameDelay > 0 { view.frameDelay = frameDelay } }
                    mpv.cmd(["show-text", String(format: "Frame: %dms", Int(frameDelay * 1000)), "1000"])
                    saveConfig(); return true
                case "}":
                    frameDelay = min(1.0, frameDelay + 0.05)
                    for view in sliceViews { if view.frameDelay > 0 { view.frameDelay = frameDelay } }
                    mpv.cmd(["show-text", String(format: "Frame: %dms", Int(frameDelay * 1000)), "1000"])
                    saveConfig(); return true
                default: break
                }
            }
        }
        return false
    }
}
