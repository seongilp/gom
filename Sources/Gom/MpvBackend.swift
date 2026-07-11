import AppKit
import Clibmpv

/// libmpv-based fallback backend for formats AVFoundation cannot play (WebM, MKV, …).
/// Renders via the libmpv render API into a CAOpenGLLayer (see MpvVideoLayer).
final class MpvBackend: NSObject, PlaybackBackend {
    let view: NSView
    var onVideoSizeChange: ((CGSize) -> Void)?
    var onPlaybackFailed: ((URL) -> Void)?

    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private let eventQueue = DispatchQueue(label: "com.zihado.gom.mpv-events")

    private var videoView: MpvVideoView { view as! MpvVideoView }

    override init() {
        self.view = MpvVideoView(frame: .zero)
        super.init()
    }

    func open(url: URL) {
        if handle == nil {
            setUp()
        }
        command("loadfile", url.path)
        setPaused(false)
    }

    func togglePlayPause() {
        command("cycle", "pause")
    }

    func seek(by seconds: Double) {
        command("seek", String(seconds), "relative+exact")
    }

    func adjustVolume(by delta: Float) {
        command("add", "volume", String(Int(delta * 100)))
    }

    func shutdown() {
        videoView.videoLayer.detachRenderContext()
        if let renderContext {
            mpv_render_context_set_update_callback(renderContext, nil, nil)
            mpv_render_context_free(renderContext)
            self.renderContext = nil
        }
        if let handle {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
    }

    deinit {
        shutdown()
    }

    // MARK: - Setup

    private func setUp() {
        guard let mpv = mpv_create() else {
            assertionFailure("mpv_create failed")
            return
        }

        mpv_set_option_string(mpv, "vo", "libmpv")
        mpv_set_option_string(mpv, "hwdec", "auto-safe")
        mpv_set_option_string(mpv, "keep-open", "yes")
        mpv_set_option_string(mpv, "input-default-bindings", "no")
        mpv_set_option_string(mpv, "input-cursor", "no")
        mpv_set_option_string(mpv, "osc", "no")
        mpv_set_option_string(mpv, "osd-level", "0")
        mpv_set_option_string(mpv, "volume-max", "100")
        mpv_set_option_string(mpv, "config", "no")
        mpv_set_option_string(mpv, "terminal", "no")
        // No Lua scripts: LuaJIT needs the JIT entitlement, and we use none of them.
        // Each builtin script has its own option; load-scripts only covers user scripts.
        mpv_set_option_string(mpv, "load-scripts", "no")
        mpv_set_option_string(mpv, "load-stats-overlay", "no")
        mpv_set_option_string(mpv, "load-osd-console", "no")
        mpv_set_option_string(mpv, "load-commands", "no")
        mpv_set_option_string(mpv, "load-select", "no")
        mpv_set_option_string(mpv, "load-auto-profiles", "no")
        mpv_set_option_string(mpv, "load-positioning", "no")
        mpv_set_option_string(mpv, "ytdl", "no")

        guard mpv_initialize(mpv) >= 0 else {
            mpv_terminate_destroy(mpv)
            assertionFailure("mpv_initialize failed")
            return
        }
        handle = mpv

        createRenderContext(for: mpv)

        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            let backend = Unmanaged<MpvBackend>.fromOpaque(context).takeUnretainedValue()
            backend.scheduleEventDrain()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func createRenderContext(for mpv: OpaquePointer) {
        let apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)
        defer { free(apiType) }

        var glInitParams = mpv_opengl_init_params(
            get_proc_address: { _, name in
                guard let name else { return nil }
                return MpvBackend.glProcAddress(name)
            },
            get_proc_address_ctx: nil
        )

        // mpv probes GL functions during creation — a current GL context is required.
        let previousContext = CGLGetCurrentContext()
        CGLSetCurrentContext(videoView.videoLayer.glContext)
        defer { CGLSetCurrentContext(previousContext) }

        var context: OpaquePointer?
        withUnsafeMutablePointer(to: &glInitParams) { glPointer in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(glPointer)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            let status = mpv_render_context_create(&context, mpv, &params)
            if status < 0 {
                assertionFailure("mpv_render_context_create failed: \(status)")
            }
        }

        guard let context else { return }
        renderContext = context
        videoView.videoLayer.attach(renderContext: context)

        mpv_render_context_set_update_callback(context, { rawContext in
            guard let rawContext else { return }
            let backend = Unmanaged<MpvBackend>.fromOpaque(rawContext).takeUnretainedValue()
            DispatchQueue.main.async {
                backend.videoView.videoLayer.setNeedsDisplay()
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private static let openGLHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/OpenGL.framework/OpenGL",
        RTLD_LAZY | RTLD_GLOBAL
    )

    private static func glProcAddress(_ name: UnsafePointer<CChar>) -> UnsafeMutableRawPointer? {
        guard let handle = openGLHandle else { return nil }
        return dlsym(handle, name)
    }

    // MARK: - Events

    private func scheduleEventDrain() {
        eventQueue.async { [weak self] in
            self?.drainEvents()
        }
    }

    private func drainEvents() {
        while let handle {
            guard let event = mpv_wait_event(handle, 0) else { break }
            let eventID = event.pointee.event_id
            if eventID == MPV_EVENT_NONE {
                break
            }
            if eventID == MPV_EVENT_VIDEO_RECONFIG {
                reportVideoSize()
            }
        }
    }

    private func reportVideoSize() {
        guard let handle else { return }
        var width: Int64 = 0
        var height: Int64 = 0
        mpv_get_property(handle, "dwidth", MPV_FORMAT_INT64, &width)
        mpv_get_property(handle, "dheight", MPV_FORMAT_INT64, &height)
        guard width > 0, height > 0 else { return }

        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        DispatchQueue.main.async { [weak self] in
            self?.onVideoSizeChange?(size)
        }
    }

    // MARK: - Commands

    private func command(_ parts: String...) {
        guard let handle else { return }
        let owned: [UnsafeMutablePointer<CChar>?] = parts.map { strdup($0) }
        defer {
            for cString in owned {
                free(cString)
            }
        }
        var argv: [UnsafePointer<CChar>?] = owned.map { UnsafePointer($0) }
        argv.append(nil)
        mpv_command(handle, &argv)
    }

    private func setPaused(_ paused: Bool) {
        guard let handle else { return }
        var flag: Int32 = paused ? 1 : 0
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
    }
}
