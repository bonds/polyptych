import AppKit
import IOSurface
import Clibmpv

final class MPVController: @unchecked Sendable {
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?

    let renderWidth: Int32
    let renderHeight: Int32
    let renderStride: Int32
    let surface: IOSurface

    init(unionWidth: Int32, unionHeight: Int32) {
        self.renderWidth = unionWidth
        self.renderHeight = unionHeight
        self.renderStride = unionWidth * 4
        let w = Int(unionWidth)
        let h = Int(unionHeight)
        let props: [IOSurfacePropertyKey: Any] = [
            .width: w,
            .height: h,
            .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4,
            .bytesPerRow: w * 4,
            .allocSize: h * w * 4,
        ]
        guard let s = IOSurface(properties: props) else {
            fatalError("IOSurface creation failed")
        }
        self.surface = s
    }

    deinit {
        if let rc = renderContext { mpv_render_context_free(rc) }
        if let m = mpv { mpv_terminate_destroy(m) }
    }

    func start(file filePath: String, isURL: Bool = false) {
        guard let mpv = mpv_create() else { fatalError("mpv_create failed") }
        self.mpv = mpv

        mpv_set_option_string(mpv, "keepaspect", "yes")
        mpv_set_option_string(mpv, "vo", "libmpv")
        mpv_set_option_string(mpv, "hwdec", "no")
        mpv_set_option_string(mpv, "audio-buffer", "0.05")
        mpv_set_option_string(mpv, "video-sync", "audio")
        mpv_set_option_string(mpv, "osd-level", "1")
        mpv_set_option_string(mpv, "osd-align-x", "center")
        mpv_set_option_string(mpv, "osd-align-y", "center")
        mpv_set_option_string(mpv, "ytdl-format", "bestvideo[height<=1080][vcodec^=avc1]+bestaudio/best[height<=1080]")

        if isURL {
            mpv_set_option_string(mpv, "cache", "yes")
            mpv_set_option_string(mpv, "cache-secs", "60")
            mpv_set_option_string(mpv, "demuxer-max-bytes", "500M")
            mpv_set_option_string(mpv, "demuxer-readahead-secs", "60")
        } else {
            mpv_set_option_string(mpv, "cache", "yes")
            mpv_set_option_string(mpv, "cache-secs", "60")
            mpv_set_option_string(mpv, "demuxer-readahead-secs", "60")
            mpv_set_option_string(mpv, "demuxer-max-bytes", "500M")
            mpv_set_option_string(mpv, "cache-pause", "yes")
        }

        mpv_set_option_string(mpv, "save-position-on-quit", "yes")
        mpv_set_option_string(mpv, "watch-later-dir", "\(NSHomeDirectory())/.config/polyptych/watch_later")

        if mpv_initialize(mpv) < 0 { fatalError("mpv_initialize failed") }

        setupSWRenderContext()
        cmd(["loadfile", filePath])

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { (p: UnsafeMutableRawPointer?) in
            guard let p else { return }
            Unmanaged<MPVController>.fromOpaque(p).takeUnretainedValue().processEvents()
        }, ctx)
    }

    func cmd(_ args: [String]) {
        guard let mpv else { return }
        var argv: [UnsafePointer<CChar>?] = args.map {
            $0.withCString { UnsafePointer(strdup($0)) }
        }
        argv.append(nil)
        mpv_command(mpv, &argv)
        for p in argv { if let p { free(UnsafeMutablePointer(mutating: p)) } }
    }

    // MARK: - Render

    /// Render a new frame into the IOSurface. Returns true if a new frame was rendered.
    func renderFrame() -> Bool {
        guard let rc = renderContext else { return false }
        surface.lock(options: IOSurfaceLockOptions(rawValue: 0), seed: nil)
        defer { surface.unlock(options: IOSurfaceLockOptions(rawValue: 0), seed: nil) }

        let ptr = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        var swSize: [Int32] = [renderWidth, renderHeight]
        var swStride = renderStride

        let result = "bgra".withCString { fmt in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: &swSize),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: fmt)),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: &swStride),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: ptr),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_render(rc, &params)
        }
        return result >= 0
    }

    /// Deep-copy a rectangular slice from the IOSurface.
    func copySlice(x: Int, y: Int, width: Int, height: Int, into dest: UnsafeMutablePointer<UInt8>, destStride: Int) {
        surface.lock(options: IOSurfaceLockOptions(rawValue: 1), seed: nil) // kIOSurfaceLockReadOnly
        defer { surface.unlock(options: IOSurfaceLockOptions(rawValue: 0), seed: nil) }
        let src = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        let srcStride = Int(renderStride)
        for row in 0..<height {
            let srcRow = src + (y + row) * srcStride + x * 4
            let dstRow = dest + row * destStride
            dstRow.update(from: srcRow, count: width * 4)
        }
    }

    // MARK: - Properties

    func readAVSync() -> Double? {
        guard let mpv else { return nil }
        var val = Double(0)
        return mpv_get_property(mpv, "avsync", MPV_FORMAT_DOUBLE, &val) >= 0 ? val : nil
    }

    func savePosition() {
        cmd(["write-watch-later-config"])
    }

    func readPropDouble(_ name: String) -> Double? {
        guard let mpv else { return nil }
        var val = Double(0)
        return mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &val) >= 0 ? val : nil
    }

    func readPropInt64(_ name: String) -> Int64? {
        guard let mpv else { return nil }
        var val = Int64(0)
        return mpv_get_property(mpv, name, MPV_FORMAT_INT64, &val) >= 0 ? val : nil
    }

    // MARK: - Private

    var onNeedsRender: (() -> Void)?

    private func setupSWRenderContext() {
        "sw".withCString { apiType in
            var initParams: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            if mpv_render_context_create(&renderContext, mpv, &initParams) < 0 {
                fatalError("mpv_render_context_create failed")
            }
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(renderContext, { ptr in
            guard let ptr else { return }
            let this = Unmanaged<MPVController>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { this.onNeedsRender?() }
        }, ctx)
    }

    private func processEvents() {
        guard let mpv else { return }
        while true {
            guard let event = mpv_wait_event(mpv, 0)?.pointee else { break }
            if event.event_id == MPV_EVENT_NONE { break }
            if event.event_id == MPV_EVENT_SHUTDOWN {
                DispatchQueue.main.async { NSApp.terminate(nil as Any?) }
                break
            }
            if event.event_id == MPV_EVENT_END_FILE,
               let data = event.data {
                let end = data.load(as: mpv_event_end_file.self)
                if end.reason == MPV_END_FILE_REASON_EOF {
                    DispatchQueue.main.async { NSApp.terminate(nil as Any?) }
                    break
                }
            }
        }
    }
}
