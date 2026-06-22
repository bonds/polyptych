import AppKit

final class SliceView: NSView {
    var frameDelay: TimeInterval = 0
    var displayID: CGDirectDisplayID = 0

    // Frame queue for delayed (native) screens
    private var frameQueue: [(time: CFAbsoluteTime, image: CGImage)] = []

    // Subtitle overlay
    private var subtitleLayer: CATextLayer?
    private let subtitleHeight: CGFloat = 200

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.layer?.contentsGravity = .resize
    }

    deinit {
        subtitleLayer?.removeFromSuperlayer()
    }

    // MARK: - Subtitles

    /// Create the subtitle text overlay layer (call once after the view has a frame).
    func setupSubtitleLayer(position: String = "bottom") {
        guard let parent = self.layer else { return }
        let layer = CATextLayer()
        layer.string = ""
        layer.font = NSFont.boldSystemFont(ofSize: 56)
        layer.fontSize = 56
        layer.foregroundColor = NSColor.white.cgColor
        layer.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.6).cgColor
        layer.cornerRadius = 8
        layer.alignmentMode = .center
        layer.isWrapped = true
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.zPosition = 100 // above video content

        let yPos: CGFloat
        if position == "top" {
            yPos = parent.bounds.maxY - subtitleHeight / 2 - 20
        } else {
            yPos = parent.bounds.minY + subtitleHeight / 2 + 60
        }
        layer.position = CGPoint(x: parent.bounds.midX, y: yPos)

        layer.bounds = CGRect(x: 0, y: 0,
                              width: parent.bounds.width * 0.95,
                              height: subtitleHeight)
        layer.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        parent.addSublayer(layer)
        subtitleLayer = layer
    }

    /// Update the subtitle text (nil or empty hides the overlay).
    func updateSubtitle(_ text: String?) {
        guard let layer = subtitleLayer else { return }
        let s = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            layer.string = ""
            layer.isHidden = true
        } else {
            let para = NSMutableParagraphStyle()
            para.paragraphSpacingBefore = 16
            para.paragraphSpacing = 16
            para.alignment = .center
            layer.string = NSAttributedString(string: s, attributes: [
                .paragraphStyle: para,
            ])
            layer.isHidden = false
        }
    }

    // MARK: - Frame queue

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
