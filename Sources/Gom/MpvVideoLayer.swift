import AppKit
import Clibmpv
import OpenGL.GL
import OpenGL.GL3

/// CAOpenGLLayer that renders mpv's video via the libmpv render API.
final class MpvVideoLayer: CAOpenGLLayer {
    private let lock = NSLock()
    private var renderContext: OpaquePointer?

    /// Shared GL context: mpv_render_context_create must run with a current GL
    /// context, and drawing must use the same (or a shared) one.
    /// nil when CGL setup fails — callers must skip mpv rendering then
    /// (making a nil context current and calling GL crashes in libGL).
    private(set) var glPixelFormat: CGLPixelFormatObj?
    private(set) var glContext: CGLContextObj?

    override init() {
        super.init()
        isOpaque = true
        isAsynchronous = false
        backgroundColor = NSColor.black.cgColor

        glPixelFormat = Self.makePixelFormat()
        if let glPixelFormat {
            var context: CGLContextObj?
            CGLCreateContext(glPixelFormat, nil, &context)
            glContext = context
        }
        if glContext == nil {
            NSLog("MpvVideoLayer: CGL context creation failed — mpv video rendering disabled")
        }
    }

    private static func makePixelFormat() -> CGLPixelFormatObj? {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            kCGLPFAAccelerated,
            CGLPixelFormatAttribute(0),
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        CGLChoosePixelFormat(attributes, &pixelFormat, &count)
        if pixelFormat == nil {
            let fallback: [CGLPixelFormatAttribute] = [
                kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
                kCGLPFADoubleBuffer,
                CGLPixelFormatAttribute(0),
            ]
            CGLChoosePixelFormat(fallback, &pixelFormat, &count)
        }
        return pixelFormat
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func attach(renderContext: OpaquePointer) {
        lock.lock()
        self.renderContext = renderContext
        lock.unlock()
    }

    func detachRenderContext() {
        lock.lock()
        renderContext = nil
        lock.unlock()
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        guard let glPixelFormat else { return super.copyCGLPixelFormat(forDisplayMask: mask) }
        CGLRetainPixelFormat(glPixelFormat)
        return glPixelFormat
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        guard let glContext else { return super.copyCGLContext(forPixelFormat: pf) }
        CGLRetainContext(glContext)
        return glContext
    }

    override func draw(
        inCGLContext ctx: CGLContextObj,
        pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval,
        displayTime ts: UnsafePointer<CVTimeStamp>?
    ) {
        CGLSetCurrentContext(ctx)

        lock.lock()
        defer { lock.unlock() }

        guard let renderContext else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            glFlush()
            return
        }

        var boundFBO: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &boundFBO)

        var fbo = mpv_opengl_fbo(
            fbo: boundFBO,
            w: Int32(bounds.width * contentsScale),
            h: Int32(bounds.height * contentsScale),
            internal_format: 0
        )
        var flipY: Int32 = 1

        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
        glFlush()
    }
}

/// View whose backing layer is the mpv OpenGL layer.
final class MpvVideoView: NSView {
    var videoLayer: MpvVideoLayer { layer as! MpvVideoLayer }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func makeBackingLayer() -> CALayer {
        MpvVideoLayer()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor {
            layer?.contentsScale = scale
        }
    }
}
