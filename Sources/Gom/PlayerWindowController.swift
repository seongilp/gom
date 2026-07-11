import AppKit
import UniformTypeIdentifiers

final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    private let playerView = PlayerView(frame: .zero)
    private var backend: PlaybackBackend?
    private var backendKind: BackendKind?
    private var videoSize: CGSize?

    private static let defaultContentSize = NSSize(width: 640, height: 360)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Gom"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.tabbingMode = .disallowed
        self.init(window: window)

        window.delegate = self
        window.contentView = playerView
        window.makeFirstResponder(playerView)

        playerView.onOpenFile = { [weak self] url in self?.open(url: url) }
        playerView.onScaleRequest = { [weak self] scale in self?.resizeWindow(scale: scale) }
        playerView.onTogglePlayPause = { [weak self] in self?.backend?.togglePlayPause() }
        playerView.onSeek = { [weak self] seconds in self?.backend?.seek(by: seconds) }
        playerView.onVolumeChange = { [weak self] delta in self?.backend?.adjustVolume(by: delta) }
        playerView.onHoverChange = { [weak self] inside in self?.setWindowButtonsVisible(inside) }

        setWindowButtonsVisible(false)
    }

    // MARK: - Opening files

    func presentOpenPanel() {
        guard let window else { return }
        let panel = NSOpenPanel()
        var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
        for ext in ["webm", "mkv"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url: url)
        }
    }

    func open(url: URL) {
        open(url: url, using: BackendKind.forFile(at: url))
    }

    private func open(url: URL, using kind: BackendKind) {
        if backendKind != kind || backend == nil {
            backend?.shutdown()
            let newBackend: PlaybackBackend = (kind == .mpv) ? MpvBackend() : AVPlayerBackend()
            newBackend.onVideoSizeChange = { [weak self] size in
                self?.videoSize = size
                self?.resizeWindow(scale: 1.0)
            }
            newBackend.onPlaybackFailed = { [weak self] failedURL in
                // AVFoundation could not play this file (e.g. AV1 without hardware
                // decoder) — retry once with the mpv backend.
                guard self?.backendKind == .native else { return }
                self?.open(url: failedURL, using: .mpv)
            }
            playerView.setBackendView(newBackend.view)
            backend = newBackend
            backendKind = kind
        }

        videoSize = nil
        window?.title = url.lastPathComponent
        backend?.open(url: url)
    }

    // MARK: - Window chrome (hover-only traffic lights)

    private func setWindowButtonsVisible(_ visible: Bool) {
        guard let window else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            for type in buttons {
                window.standardWindowButton(type)?.animator().alphaValue = visible ? 1 : 0
            }
        }
    }

    // MARK: - Window sizing (keys 1/2/3 → 50% / 100% / 200%)

    func resizeWindow(scale: CGFloat) {
        guard let window, let videoSize else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }

        var target = NSSize(width: videoSize.width * scale, height: videoSize.height * scale)

        if let screenFrame = window.screen?.visibleFrame {
            let maxSize = NSSize(width: screenFrame.width * 0.95, height: screenFrame.height * 0.95)
            if target.width > maxSize.width || target.height > maxSize.height {
                let ratio = min(maxSize.width / target.width, maxSize.height / target.height)
                target = NSSize(width: target.width * ratio, height: target.height * ratio)
            }
        }

        let contentRect = NSRect(origin: .zero, size: target)
        let frameRect = window.frameRect(forContentRect: contentRect)

        var origin = window.frame.origin
        // Keep the window's top-left corner anchored while resizing.
        origin.y += window.frame.height - frameRect.height

        window.setFrame(NSRect(origin: origin, size: frameRect.size), display: true, animate: false)
        window.contentAspectRatio = videoSize

        if let screenFrame = window.screen?.visibleFrame {
            var frame = window.frame
            frame.origin.x = min(max(frame.origin.x, screenFrame.minX), max(screenFrame.maxX - frame.width, screenFrame.minX))
            frame.origin.y = min(max(frame.origin.y, screenFrame.minY), max(screenFrame.maxY - frame.height, screenFrame.minY))
            window.setFrameOrigin(frame.origin)
        }
    }

    func windowWillClose(_ notification: Notification) {
        backend?.shutdown()
    }
}
