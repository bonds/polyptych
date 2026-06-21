import AppKit

final class SliceView: NSView {
    var frameDelay: TimeInterval = 0
    var displayID: CGDirectDisplayID = 0

    // Frame queue for delayed (native) screens
    private var frameQueue: [(time: CFAbsoluteTime, image: CGImage)] = []

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLayer()
    }

    override init() {
        super.init(frame: .zero)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        self.wantsLayer = true
        self.layer?.contentsGravity = .resize
    }

    /// Queue a pre-built CGImage for delayed display.
    func enqueueDelayedImage(_ image: CGImage) {
        frameQueue.append((CFAbsoluteTimeGetCurrent(), image))
        showNextDelayedFrame()
    }

    private func showNextDelayedFrame() {
        let now = CFAbsoluteTimeGetCurrent()
        while frameQueue.count > 1 {
            if now - frameQueue[1].time >= frameDelay {
                frameQueue.removeFirst()
            } else {
                break
            }
        }
        if let first = frameQueue.first, now - first.time >= frameDelay {
            self.layer?.contents = first.image
            self.layer?.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            frameQueue.removeFirst()
        }
    }
}
