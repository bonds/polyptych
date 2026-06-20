import AppKit

final class SliceView: NSView {
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var writeIndex = 0
    private var sliceW: Int = 0
    private var sliceH: Int = 0

    var frameDelay: TimeInterval = 0
    var displayID: CGDirectDisplayID = 0
    var onFrameDisplayed: ((CGDirectDisplayID) -> Void)?
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

    func updateSlice(from controller: MPVController, sliceX: Int, sliceY: Int, sliceW: Int, sliceH: Int) {
        let required = sliceW * sliceH * 4
        if buffers.isEmpty {
            buffers = [
                UnsafeMutablePointer<UInt8>.allocate(capacity: required),
                UnsafeMutablePointer<UInt8>.allocate(capacity: required),
            ]
        }
        self.sliceW = sliceW
        self.sliceH = sliceH

        writeIndex = (writeIndex + 1) % 2
        let buf = buffers[writeIndex]

        controller.readSlice(x: sliceX, y: sliceY, width: sliceW, height: sliceH,
                             into: buf, destStride: sliceW * 4)

        if frameDelay > 0 {
            // For delayed screens, copy pixel data so each queued frame owns its buffer
            let pixelCopy = UnsafeMutablePointer<UInt8>.allocate(capacity: required)
            pixelCopy.update(from: buf, count: required)
            let data = NSData(bytesNoCopy: pixelCopy, length: required, freeWhenDone: true)
            guard let provider = CGDataProvider(data: data) else { return }
            guard let cgImg = makeCGImage(provider: provider, w: sliceW, h: sliceH, stride: sliceW * 4) else { return }
            frameQueue.append((CFAbsoluteTimeGetCurrent(), cgImg))
            showNextDelayedFrame()
        } else {
            let data = NSData(bytesNoCopy: buf, length: required, freeWhenDone: false)
            guard let provider = CGDataProvider(data: data) else { return }
            guard let cgImg = makeCGImage(provider: provider, w: sliceW, h: sliceH, stride: sliceW * 4) else { return }
            self.layer?.contents = cgImg
            if displayID != 0 { onFrameDisplayed?(displayID) }
        }
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
