import AppKit
import Clibmpv

final class MPVController: @unchecked Sendable {
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?

    let renderWidth: Int32
    let renderHeight: Int32
    private(set) var renderStride: Int32
    private let buffer: UnsafeMutablePointer<UInt8>

    init(unionWidth: Int32, unionHeight: Int32) {
        self.renderWidth = unionWidth
        self.renderHeight = unionHeight
        self.renderStride = unionWidth * 4
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: Int(unionHeight) * Int(unionWidth * 4)
        )
    }

    deinit {
        if let rc = renderContext { mpv_render_context_free(rc) }
        if let m = mpv { mpv_terminate_destroy(m) }
        buffer.deallocate()
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
        mpv_set_option_string(mpv, "ytdl-format", "bestvideo[height<=?1080]+bestaudio/best")

        if isURL {
            mpv_set_option_string(mpv, "cache", "yes")
            mpv_set_option_string(mpv, "cache-secs", "30")
            mpv_set_option_string(mpv, "demuxer-max-bytes", "200M")
            mpv_set_option_string(mpv, "demuxer-readahead-secs", "60")
        } else {
            mpv_set_option_string(mpv, "demuxer-readahead-secs", "0")
            mpv_set_option_string(mpv, "cache", "no")
        }

        mpv_set_option_string(mpv, "audio-delay", "0.20")

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

    func renderFrame() -> Bool {
        guard let rc = renderContext else { return false }
        var swSize: [Int32] = [renderWidth, renderHeight]
        var swStride = renderStride

        let result = "bgra".withCString { fmt in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: &swSize),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: fmt)),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: &swStride),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: buffer),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_render(rc, &params)
        }
        return result >= 0
    }

    func readSlice(x: Int, y: Int, width: Int, height: Int, into dest: UnsafeMutablePointer<UInt8>, destStride: Int) {
        let srcStride = Int(renderStride)
        for row in 0..<height {
            let srcRow = buffer + (y + row) * srcStride + x * 4
            let dstRow = dest + row * destStride
            dstRow.update(from: srcRow, count: width * 4)
        }
    }

    /// Read mpv's A/V sync value. Positive = audio ahead of video.
    func readAVSync() -> Double? {
        guard let mpv else { return nil }
        var val = Double(0)
        let result = mpv_get_property(mpv, "avsync", MPV_FORMAT_DOUBLE, &val)
        return result >= 0 ? val : nil
    }

    // MARK: - Private

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

        mpv_render_context_set_update_callback(renderContext, { _ in }, nil)
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
