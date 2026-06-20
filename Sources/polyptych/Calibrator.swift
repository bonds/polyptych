import AppKit
import CoreVideo
import CoreFoundation

/// Measures per-screen display latency via CVDisplayLink vsync timing.
/// After collecting samples for a few seconds, computes audio & frame delays
/// to sync all screens to the slowest one.
final class Calibrator: @unchecked Sendable {
    private var displayLinks: [CGDirectDisplayID: CVDisplayLink] = [:]
    private var pendingSubmits: [CGDirectDisplayID: [CFAbsoluteTime]] = [:]
    private var vsyncTimes: [CGDirectDisplayID: [CFAbsoluteTime]] = [:]
    private let lock = NSLock()

    private var startTime: CFAbsoluteTime = 0
    private let duration: CFAbsoluteTime = 5.0

    private(set) var isRunning = false
    private(set) var isDone = false

    /// Results
    private(set) var audioDelay: Double = 0
    private(set) var screenDelays: [CGDirectDisplayID: Double] = [:]
    private(set) var screenLatencies: [CGDirectDisplayID: Double] = [:]

    var onComplete: (() -> Void)?

    deinit {
        for (_, dl) in displayLinks { CVDisplayLinkStop(dl) }
    }

    func start() {
        startTime = CFAbsoluteTimeGetCurrent()
        isRunning = true

        for screen in NSScreen.screens {
            let id = DisplayDetector.displayID(for: screen)
            guard id != 0 else { continue }
            pendingSubmits[id] = []
            vsyncTimes[id] = []

            var dl: CVDisplayLink?
            CVDisplayLinkCreateWithCGDisplay(id, &dl)
            guard let dl else {
                fputs(String(format: "[cal] no display link for %d\n", id), stderr)
                continue
            }

            let ptr = Unmanaged.passUnretained(self).toOpaque()
            CVDisplayLinkSetOutputHandler(dl) { (_, _, out, _, _) -> CVReturn in
                let now = CFAbsoluteTimeGetCurrent()
                let vsyncHost = out.pointee.hostTime
                let vsyncTime = CFAbsoluteTime(Double(vsyncHost) / 1_000_000_000)
                let cal = Unmanaged<Calibrator>.fromOpaque(ptr).takeUnretainedValue()

                cal.lock.lock()
                cal.vsyncTimes[id]?.append(now)
                // Match this vsync to the most recent submit
                if var pending = cal.pendingSubmits[id], !pending.isEmpty {
                    let submit = pending.removeLast()
                    cal.pendingSubmits[id] = pending
                    let latency = now - submit
                    if latency > 0.005 && latency < 0.5 { // 5ms-500ms range
                        cal.screenLatencies[id] = latency
                    }
                }
                cal.lock.unlock()

                // Check if done
                if now - cal.startTime >= cal.duration {
                    DispatchQueue.main.async { cal.finish() }
                }
                return kCVReturnSuccess
            }
            CVDisplayLinkStart(dl)
            displayLinks[id] = dl
        }
    }

    /// Call from the render thread when a frame is displayed on a given screen.
    func recordFrame(_ displayID: CGDirectDisplayID) {
        guard isRunning else { return }
        lock.lock()
        pendingSubmits[displayID]?.append(CFAbsoluteTimeGetCurrent())
        // Keep only the most recent pending submit
        if var p = pendingSubmits[displayID], p.count > 3 {
            p.removeFirst(p.count - 3)
            pendingSubmits[displayID] = p
        }
        lock.unlock()
    }

    private func finish() {
        isRunning = false
        isDone = true

        guard !screenLatencies.isEmpty else {
            fputs("[cal] no latency samples collected\n", stderr)
            DispatchQueue.main.async { self.onComplete?() }
            return
        }

        let maxLat = screenLatencies.values.max() ?? 0
        fputs(String(format: "[cal] max latency: %.1fms\n", maxLat * 1000), stderr)

        for (id, lat) in screenLatencies {
            let delay = maxLat - lat
            screenDelays[id] = delay > 0.01 ? delay : 0
            fputs(String(format: "[cal] screen %d: latency=%.1fms delay=%.1fms\n", id, lat * 1000, delay * 1000), stderr)
        }

        audioDelay = maxLat
        fputs(String(format: "[cal] audio delay: %.1fms\n", audioDelay * 1000), stderr)

        DispatchQueue.main.async { self.onComplete?() }
    }
}
