import AppKit

final class SliceView: NSView {
    var frameDelay: TimeInterval = 0
    var displayID: CGDirectDisplayID = 0
    var onFrameDisplayed: ((CGDirectDisplayID) -> Void)?

    // Frame queue for delayed (native) screens
    private var frameQueue: [(time: CFAbsoluteTime, image: CGImage)] = []

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

    /// Fast path: share a single full-frame CGImage across all windows,
    /// each showing only its portion via `contentsRect`.
    func setSharedContents(_ image: CGImage, contentsRect: CGRect) {
        self.layer?.contents = image
        self.layer?.contentsRect = contentsRect
        if displayID != 0 { onFrameDisplayed?(displayID) }
    }

    /// Delayed path: deep-copy the slice portion and queue for later display.
    func enqueueDelayedSlice(from buffer: UnsafeMutablePointer<UInt8>,
                             stride: Int,
                             sliceX: Int, sliceY: Int,
                             sliceW: Int, sliceH: Int)
    {
        let required = sliceW * sliceH * 4
        let pixelCopy = UnsafeMutablePointer<UInt8>.allocate(capacity: required)
        let src = buffer + sliceY * stride + sliceX * 4
        for row in 0..<sliceH {
            let srcRow = src + row * stride
            let dstRow = pixelCopy + row * (sliceW * 4)
            dstRow.update(from: srcRow, count: sliceW * 4)
        }
        let data = NSData(bytesNoCopy: pixelCopy, length: required, freeWhenDone: true)
        guard let provider = CGDataProvider(data: data) else { return }
        guard let cgImg = makeCGImage(provider: provider, w: sliceW, h: sliceH, stride: sliceW * 4) else { return }
        frameQueue.append((CFAbsoluteTimeGetCurrent(), cgImg))
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
            if displayID != 0 { onFrameDisplayed?(displayID) }
            frameQueue.removeFirst()
        }
    }

    private func makeCGImage(provider: CGDataProvider, w: Int, h: Int, stride: Int) -> CGImage? {
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        return CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
