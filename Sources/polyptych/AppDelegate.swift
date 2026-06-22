import AppKit
import IOKit.pwr_mgt

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: InputMode?
    private var mpvController: MPVController?
    private var spannedWindows: [SpannedWindow] = []
    private var sliceViews: [SliceView] = []
    private var downloadedFile: String?
    private var cachedConfig = Config.load()
    private var cachedSlices: [(NSScreen, NSRect)] = []
    private var cachedUnion: NSRect = .zero
    private var cachedSx: Double = 0
    private var cachedSy: Double = 0

    init(mode: InputMode?) {
        self.mode = mode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let mode else { return } // launched via Finder with no args — wait for openFile
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

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        if debugMode {
            fputs("[polyptych] openFile: \(filename)\n", stderr)
        }
        // If already playing, close current playback and start new file
        if mpvController != nil {
            mpvController?.savePosition()
            mpvController = nil
            for w in spannedWindows { w.close() }
            spannedWindows = []
            sliceViews = []
            downloadedFile = nil
        }
        startPlayback(filePath: filename, isURL: false)
        return true
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

        updateCachedLayout()

        let (nativeScreens, dlScreens) = DisplayDetector.classifyDisplays()
        let nativeIDs = Set(nativeScreens.map { DisplayDetector.displayID(for: $0) })
        let hasDL = !dlScreens.isEmpty

        for (i, (s, _)) in slices.enumerated() {
            guard i < cachedSlices.count else { break }
            let view = SliceView(frame: .zero)
            view.displayID = DisplayDetector.displayID(for: s)
            let win = SpannedWindow(screenFrame: s.frame)
            win.contentView = view
            spannedWindows.append(win)
            sliceViews.append(view)
            win.makeKeyAndOrderFront(nil)

            if hasDL && nativeIDs.contains(view.displayID) {
                frameDelay = cachedConfig.frameDelay
                view.frameDelay = frameDelay
                // Middle (native, delayed) screen gets the subtitle overlay
                view.setupSubtitleLayer()
            }

            if debugMode {
                fputs("[polyptych] window \(i): frame=\(s.frame) displayID=\(view.displayID)\n", stderr)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        mpv.start(file: filePath, isURL: isURL,
                  audioLanguages: cachedConfig.audioLanguages,
                  subtitleLanguages: cachedConfig.subtitleLanguages)

        // Prevent display sleep and screensaver during playback
        IOPMAssertionCreateWithName(
            "NoDisplaySleepAssertion" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "polyptych video playback" as CFString,
            &sleepAssertion)

        let initAudio = isURL ? 0.0 : (hasDL ? cachedConfig.audioDelay : 0.0)
        audioDelay = initAudio
        if initAudio > 0 { mpv.cmd(["set", "audio-delay", String(format: "%.2f", initAudio)]) }

        mpv.onNeedsRender = { [weak self] in
            self?.renderFrame()
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKey(event) ?? false { return nil }
            return event
        }

        // Monitor display changes — just update the layout math, don't touch windows.
        // (The render loop uses cachedSlices, so updating those is enough.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        startupComplete = true
    }

    private var startupComplete = false

    @objc private func screensChanged() {
        guard startupComplete else { return }
        mpvController?.savePosition()
        DispatchQueue.main.async { [self] in
            updateCachedLayout()
        }
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
                            "--format", "bestvideo[height<=1080][vcodec^=avc1]+bestaudio/best[height<=1080]",
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

    private var fpsFrames: Int = 0
    private var fpsLastTime: CFAbsoluteTime = 0
    private var renderAttempts: Int = 0
    private var renderMisses: Int = 0

    private func renderFrame() {
        guard let mpv = mpvController else { return }
        renderAttempts += 1
        let fStart = CFAbsoluteTimeGetCurrent()

        guard let renderBuf = mpv.renderFrame() else {
            renderMisses += 1
            if debugMode { logFrame(fStart, CFAbsoluteTimeGetCurrent(), false, mpv: mpv) }
            return
        }

        // Per-slice CGImages for each screen (original approach, avoids DisplayLink CA commit issues with contentsRect).
        let srcStride = Int(mpv.renderStride)
        let srcBuf = renderBuf
        let bmi = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        let renderW = Int(mpv.renderWidth)

        for (i, sView) in sliceViews.enumerated() {
            if debugMode && fpsFrames == 0 {
                fputs("[polyptych] render \(i): delay=\(sView.frameDelay)\n", stderr)
            }
            guard i < cachedSlices.count else { break }

            let s = bezelCroppedSlice(i)
            let sliceW = Int(Double(s.width) * cachedSx)
            let sliceH = Int(Double(s.size.height) * cachedSy)
            let sliceX = Int(Double(s.origin.x) * cachedSx)
            let sliceY = Int(Double(s.origin.y) * cachedSy)
            let required = sliceW * sliceH * 4
            let pixelCopy = UnsafeMutablePointer<UInt8>.allocate(capacity: required)
            // Copy slice rows from the render buffer
            for row in 0..<sliceH {
                let srcRow = srcBuf + (sliceY + row) * srcStride + sliceX * 4
                let dstRow = pixelCopy + row * (sliceW * 4)
                dstRow.update(from: srcRow, count: sliceW * 4)
            }
            let data = NSData(bytesNoCopy: pixelCopy, length: required, freeWhenDone: true)
            guard let provider = CGDataProvider(data: data) else { continue }
            guard let cgImg = CGImage(
                width: sliceW, height: sliceH,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: sliceW * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bmi,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            ) else { continue }

            if sView.frameDelay > 0 {
                sView.enqueueDelayedImage(cgImg)
            } else {
                sView.layer?.contents = cgImg
                sView.layer?.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }

        // Subtitle logic on the middle (native, delayed) screen
        if let subView = sliceViews.first(where: { $0.frameDelay > 0 }) {
            let showSubs: Bool = {
                guard let audioLang = mpv.readPropertyString("current-tracks/audio/lang"),
                      !audioLang.isEmpty else { return false }
                return !cachedConfig.subtitleLanguages.contains(audioLang)
            }()
            if showSubs {
                let subText = mpv.readPropertyString("sub-text")
                subView.updateSubtitle(subText)
            } else {
                subView.updateSubtitle(nil)
            }
        }

        if debugMode { logFrame(fStart, CFAbsoluteTimeGetCurrent(), true, mpv: mpv) }
    }

    /// The i-th slice rect after applying the bezel crop.
    private func bezelCroppedSlice(_ index: Int) -> NSRect {
        guard index < cachedSlices.count else { return .zero }
        let bezelFrac = cachedConfig.bezelGaps.first ?? 0.075
        var s = cachedSlices[index].1
        let crop = Double(s.width) * bezelFrac
        s.origin.x += crop
        s.size.width -= crop * 2
        return s
    }

    private func logFrame(_ fStart: CFAbsoluteTime, _ fEnd: CFAbsoluteTime, _ success: Bool, mpv: MPVController) {
        if success { fpsFrames += 1 }
        let now = CFAbsoluteTimeGetCurrent()
        if fpsLastTime == 0 { fpsLastTime = now }
        if now - fpsLastTime >= 1.0 {
            let elapsed = now - fpsLastTime
            let fps = Double(fpsFrames) / elapsed
            let hitRate = renderAttempts > 0
                ? String(format: "%.0f%%", Double(fpsFrames) / Double(renderAttempts) * 100)
                : "0%"
            let vfps = mpv.readPropDouble("estimated-vf-fps") ?? 0
            let drops = mpv.readPropInt64("frame-drop-count") ?? 0
            let totalMs = (fEnd - fStart) * 1000
            let rw = Int(mpv.renderWidth)
            let rh = Int(mpv.renderHeight)
            fputs("[polyptych] \(Int(round(fps)))fps hit:\(hitRate) vfps:\(Int(round(vfps))) drops:\(drops) | frame:\(Int(totalMs))ms | \(rw)×\(rh)\n", stderr)
            fpsFrames = 0
            fpsLastTime = now
            renderAttempts = 0
            renderMisses = 0
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
