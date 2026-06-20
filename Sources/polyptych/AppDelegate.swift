import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let filePath: String?
    private var mpvController: MPVController?
    private var spannedWindows: [SpannedWindow] = []
    private var sliceViews: [SliceView] = []

    init(filePath: String?) {
        self.filePath = filePath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = filePath else {
            fputs("Usage: polyptych <video-file-or-url>\n", stderr)
            NSApp.terminate(nil as Any?)
            return
        }

        let isURL = path.hasPrefix("ytdl://") || path.hasPrefix("http://") || path.hasPrefix("https://")
        if !isURL && !FileManager.default.fileExists(atPath: path) {
            fputs("polyptych: file not found: \(path)\n", stderr)
            NSApp.terminate(nil as Any?)
            return
        }

        DispatchQueue.main.async { [self] in
            startPlayback(filePath: path, isURL: isURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Setup

    private func startPlayback(filePath: String, isURL: Bool = false) {
        let screens = DisplayLayout.selectedScreens()
        let union = DisplayLayout.unionRect(of: screens)
        let slices = DisplayLayout.slices(for: screens, relativeTo: union)

        let renderScale: Double = 0.5
        let renderW = CInt(Double(union.width) * renderScale)
        let renderH = CInt(Double(union.height) * renderScale)

        let mpv = MPVController(unionWidth: renderW, unionHeight: renderH)
        self.mpvController = mpv

        // Detect native vs DisplayLink screens by refresh rate (120Hz+ = native)
        let (nativeScreens, _) = DisplayDetector.classifyDisplays()
        let nativeIDs = Set(nativeScreens.map { DisplayDetector.displayID(for: $0) })

        for (s, _) in slices {
            let view = SliceView()
            view.displayID = DisplayDetector.displayID(for: s)
            let win = SpannedWindow(screenFrame: s.frame)
            win.contentView = view
            spannedWindows.append(win)
            sliceViews.append(view)
            win.makeKeyAndOrderFront(nil)

            // Delay native screens to match DisplayLink latency
            if nativeIDs.contains(view.displayID) {
                view.frameDelay = 0.20
            }
        }

        mpv.start(file: filePath, isURL: isURL)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        // Baseline audio delay for DisplayLink screens
        mpv.cmd(["set", "audio-delay", "0.20"])

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    // MARK: - Auto A/V Sync (fine-tunes baseline delay)

    private var avSyncCount = 0
    private var avSyncAccum: Double = 0
    private var audioDelay: Double = 0.20

    private func checkAVSync() {
        guard let mpv = mpvController, let av = mpv.readAVSync(), abs(av) > 0.001 else { return }
        avSyncCount += 1
        avSyncAccum += av

        if avSyncCount >= 90 {
            let avg = avSyncAccum / Double(avSyncCount)
            if abs(avg) > 0.03 {
                let correction = avg * 0.3
                audioDelay = max(0, min(1.0, audioDelay + correction))
                mpv.cmd(["set", "audio-delay", String(format: "%.3f", audioDelay)])
            }
            avSyncCount = 0
            avSyncAccum = 0
        }
    }

    // MARK: - Render

    private func renderFrame() {
        guard let mpv = mpvController else { return }
        let screens = DisplayLayout.selectedScreens()
        let union = DisplayLayout.unionRect(of: screens)
        let slices = DisplayLayout.slices(for: screens, relativeTo: union)

        guard mpv.renderFrame() else { return }
        checkAVSync()

        let sx = Double(mpv.renderWidth) / Double(union.width)
        let sy = Double(mpv.renderHeight) / Double(union.height)

        for (i, sView) in sliceViews.enumerated() {
            guard i < slices.count else { break }
            let s = slices[i].slice
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
                default: break
                }
            }
        }
    }
}
