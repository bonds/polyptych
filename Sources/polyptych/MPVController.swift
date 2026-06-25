import AppKit
import Clibmpv

final class MPVController: @unchecked Sendable {
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?

    let renderWidth: Int32
    let renderHeight: Int32
    let renderStride: Int32

    private let numBuffers = 3
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var renderIndex = 0

    init(unionWidth: Int32, unionHeight: Int32) {
        self.renderWidth = unionWidth
        self.renderHeight = unionHeight
        self.renderStride = unionWidth * 4
        let capacity = Int(unionHeight) * Int(unionWidth * 4)
        self.buffers = (0..<numBuffers).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        }
    }

    deinit {
        if let rc = renderContext { mpv_render_context_free(rc) }
        if let m = mpv { mpv_terminate_destroy(m) }
        for buf in buffers { buf.deallocate() }
    }

    func start(file filePath: String, isURL: Bool = false,
               audioLanguages: [String] = [], subtitleLanguages: [String] = []) {
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
        mpv_set_option_string(mpv, "ytdl-format", "bestvideo[height<=1080][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=1080]")
        mpv_set_option_string(mpv, "sub-auto", "fuzzy")
        mpv_set_option_string(mpv, "sub-visibility", "no")

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

        if !audioLanguages.isEmpty {
            let s = audioLanguages.joined(separator: ",")
            fputs("[polyptych] mpv.start: setting alang='\(s)'\n", stderr)
            mpv_set_option_string(mpv, "alang", s)
        } else {
            fputs("[polyptych] mpv.start: audioLanguages empty, NOT setting alang\n", stderr)
        }
        if !subtitleLanguages.isEmpty {
            let s = subtitleLanguages.joined(separator: ",")
            fputs("[polyptych] mpv.start: setting slang='\(s)'\n", stderr)
            mpv_set_option_string(mpv, "slang", s)
        }

        if mpv_initialize(mpv) < 0 { fatalError("mpv_initialize failed") }

        setupSWRenderContext()
        cmd(["loadfile", filePath])

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { (p: UnsafeMutableRawPointer?) in
            guard let p else { return }
            Unmanaged<MPVController>.fromOpaque(p).takeUnretainedValue().processEvents()
        }, ctx)
    }

    @discardableResult
    func cmd(_ args: [String]) -> Int32 {
        guard let mpv else { return -1 }
        var argv: [UnsafePointer<CChar>?] = args.map {
            $0.withCString { UnsafePointer(strdup($0)) }
        }
        argv.append(nil)
        let result = mpv_command(mpv, &argv)
        for p in argv { if let p { free(UnsafeMutablePointer(mutating: p)) } }
        if result != 0 {
            fputs("[polyptych] cmd error: \(args[0]) code=\(result)\n", stderr)
        }
        return result
    }

    /// Replace the audio filter chain (for YouTube downloaded files with loudness normalization).
    func setAF(_ filter: String) {
        cmd(["af", "set", filter])
    }

    /// Clear all audio filters (for local files — playback at raw volume).
    func clearAF() {
        cmd(["af", "clr", ""])
    }

    // MARK: - Render

    /// Renders into the triple buffer, returns the buffer pointer (nil if no new frame).
    func renderFrame() -> UnsafeMutablePointer<UInt8>? {
        guard let rc = renderContext else { return nil }
        let currentBuf = buffers[renderIndex]

        let result = "bgra".withCString { fmt in
            var swSize: [Int32] = [renderWidth, renderHeight]
            var swStride = renderStride
            return swSize.withUnsafeMutableBufferPointer { sizeBuf in
                withUnsafeMutablePointer(to: &swStride) { stridePtr in
                    var params: [mpv_render_param] = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: sizeBuf.baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: fmt)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: stridePtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: currentBuf),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                    ]
                    return mpv_render_context_render(rc, &params)
                }
            }
        }
        guard result >= 0 else { return nil }
        renderIndex = (renderIndex + 1) % numBuffers
        return buffers[(renderIndex - 1 + numBuffers) % numBuffers]
    }

    /// Deep-copy a rectangular slice from the latest render buffer.
    func copySlice(x: Int, y: Int, width: Int, height: Int, into dest: UnsafeMutablePointer<UInt8>, destStride: Int) {
        let buf = buffers[(renderIndex - 1 + numBuffers) % numBuffers]
        let srcStride = Int(renderStride)
        for row in 0..<height {
            let srcRow = buf + (y + row) * srcStride + x * 4
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

    func readPropertyString(_ name: String) -> String? {
        guard let mpv else { return nil }
        let ptr = mpv_get_property_string(mpv, name)
        guard let p = ptr else { return nil }
        defer { mpv_free(p) }
        return String(cString: p)
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

    /// Log available tracks and re-select audio/sub matching language preferences.
    func reselectTracks() {
        // Log all tracks in debug mode
        if debugMode {
            let count = readPropInt64("track-list/count") ?? 0
            for i in 0..<count {
                let type = readPropertyString("track-list/\(i)/type") ?? "?"
                let lang = readPropertyString("track-list/\(i)/lang") ?? "?"
                let sel = readPropertyString("track-list/\(i)/selected") ?? "?"
                let id = readPropInt64("track-list/\(i)/id") ?? 0
                fputs("[polyptych] track \(id): \(type) lang=\(lang) sel=\(sel)\n", stderr)
            }
        }

        // Manually select audio track matching audioLanguages
        let aLangs = readPropertyString("options/alang") ?? "<nil>"
        fputs("[polyptych] reselect: alang option='\(aLangs)'\n", stderr)
        if !aLangs.isEmpty && aLangs != "<nil>" {
            let prefs = aLangs.split(separator: ",").map(String.init)
            if let matchingId = findTrack(type: "audio", languages: prefs) {
                fputs("[polyptych] reselect: found audio track \(matchingId), setting aid\n", stderr)
                cmd(["set", "aid", String(matchingId)])
                // Verify after set
                let after = readPropertyString("aid") ?? "?"
                let afterLang = readPropertyString("current-tracks/audio/lang") ?? "?"
                fputs("[polyptych] reselect: aid=\(after) lang=\(afterLang)\n", stderr)
            } else {
                fputs("[polyptych] reselect: no matching audio track, setting aid=auto\n", stderr)
                cmd(["set", "aid", "auto"])
            }
        } else {
            fputs("[polyptych] reselect: no alang set, setting aid=auto\n", stderr)
            cmd(["set", "aid", "auto"])
        }

        // Manually select sub track matching subtitleLanguages
        let sLangs = readPropertyString("options/slang") ?? ""
        if !sLangs.isEmpty {
            let prefs = sLangs.split(separator: ",").map(String.init)
            if let matchingId = findTrack(type: "sub", languages: prefs) {
                cmd(["set", "sid", String(matchingId)])
            } else {
                cmd(["set", "sid", "auto"])
            }
        }
    }

    /// Map ISO 639-1 codes to common ISO 639-2/B three-letter codes.
    private static let langMap: [String: [String]] = [
        "zh": ["chi", "zho", "cmn"],
        "en": ["eng"],
        "ja": ["jpn"],
        "ko": ["kor"],
        "fr": ["fra", "fre"],
        "de": ["deu", "ger"],
        "es": ["spa"],
        "it": ["ita"],
        "pt": ["por"],
        "ru": ["rus"],
        "ar": ["ara"],
        "hi": ["hin"],
    ]

    /// Find the first track of `type` matching a language in `languages` (preference order).
    private func findTrack(type: String, languages: [String]) -> Int64? {
        let count = readPropInt64("track-list/count") ?? 0
        // For each language preference (in order), find a matching track
        for langPref in languages {
            // Build possible codes for this preference (one-letter + three-letter variants)
            var codes = [langPref]
            if let three = Self.langMap[langPref] {
                codes.append(contentsOf: three)
            }
            for i in 0..<count {
                guard readPropertyString("track-list/\(i)/type") == type else { continue }
                guard let trackLang = readPropertyString("track-list/\(i)/lang"), !trackLang.isEmpty else { continue }
                if codes.contains(trackLang) {
                    return readPropInt64("track-list/\(i)/id")
                }
            }
        }
        // Fallback: unlabeled track of the right type
        for i in 0..<count {
            guard readPropertyString("track-list/\(i)/type") == type else { continue }
            if (readPropertyString("track-list/\(i)/lang") ?? "").isEmpty {
                return readPropInt64("track-list/\(i)/id")
            }
        }
        return nil
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
            if event.event_id == MPV_EVENT_FILE_LOADED {
                DispatchQueue.main.async { [weak self] in
                    guard let s = self else { return }
                    s.reselectTracks()
                }
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
