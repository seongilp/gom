import AppKit
import UniformTypeIdentifiers

final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    private let playerView = PlayerView(frame: .zero)
    private let controlBar = ControlBar()
    private let infoPanel = InfoPanel()
    private var backend: PlaybackBackend?
    private var backendKind: BackendKind?
    private var videoSize: CGSize?

    private var isPaused = true
    private var infoVisible = false
    private var cachedInfoText: String?
    private var hudUpdateTimer: Timer?
    private var hudHideTimer: Timer?

    private static let defaultContentSize = NSSize(width: 640, height: 360)
    private static let hudAutoHideDelay: TimeInterval = 2.5

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
        playerView.onSeek = { [weak self] seconds in
            self?.backend?.seek(by: seconds)
            self?.showHUDTransiently()
        }
        playerView.onVolumeChange = { [weak self] delta in
            self?.backend?.adjustVolume(by: delta)
            self?.showHUDTransiently()
        }
        playerView.onHoverChange = { [weak self] inside in self?.setWindowButtonsVisible(inside) }
        playerView.onMouseMoved = { [weak self] in self?.showHUDTransiently() }
        playerView.onToggleInfo = { [weak self] in self?.toggleInfoPanel() }
        playerView.onToggleMute = { [weak self] in
            self?.backend?.toggleMute()
            self?.showHUDTransiently()
        }

        setUpOverlays()
        setWindowButtonsVisible(false)
    }

    private func setUpOverlays() {
        playerView.addSubview(controlBar)
        playerView.addSubview(infoPanel)
        controlBar.alphaValue = 0
        controlBar.isHidden = true
        infoPanel.isHidden = true

        controlBar.onSeekFraction = { [weak self] fraction in
            guard let backend = self?.backend, backend.duration > 0 else { return }
            backend.seek(to: fraction * backend.duration)
        }

        NSLayoutConstraint.activate([
            controlBar.leadingAnchor.constraint(equalTo: playerView.leadingAnchor, constant: 16),
            controlBar.trailingAnchor.constraint(equalTo: playerView.trailingAnchor, constant: -16),
            controlBar.bottomAnchor.constraint(equalTo: playerView.bottomAnchor, constant: -16),
            controlBar.heightAnchor.constraint(equalToConstant: 44),

            infoPanel.trailingAnchor.constraint(equalTo: playerView.trailingAnchor, constant: -16),
            infoPanel.topAnchor.constraint(equalTo: playerView.topAnchor, constant: 16),
            infoPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
        ])

        hudUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshHUD()
        }
    }

    // MARK: - HUD

    private func refreshHUD() {
        guard let backend else { return }
        if !controlBar.isHidden {
            controlBar.update(
                current: backend.currentTime,
                duration: backend.duration,
                volume: backend.volume,
                muted: backend.isMuted
            )
        }
        if infoVisible {
            infoPanel.render(staticText: cachedInfoText, liveLines: backend.liveStats())
        }
    }

    private func setControlBarVisible(_ visible: Bool) {
        if visible {
            controlBar.isHidden = false
            refreshHUD()
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            controlBar.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self, !visible, self.controlBar.alphaValue == 0 else { return }
            self.controlBar.isHidden = true
        })
    }

    private func showHUDTransiently() {
        guard backend != nil else { return }
        setControlBarVisible(true)
        hudHideTimer?.invalidate()
        guard !isPaused else { return }
        hudHideTimer = Timer.scheduledTimer(
            withTimeInterval: Self.hudAutoHideDelay,
            repeats: false
        ) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.setControlBarVisible(false)
        }
    }

    private func handlePauseStateChange(_ paused: Bool) {
        isPaused = paused
        if paused {
            hudHideTimer?.invalidate()
            setControlBarVisible(true)
        } else {
            showHUDTransiently()
        }
    }

    private func toggleInfoPanel() {
        infoVisible.toggle()
        if infoVisible {
            cachedInfoText = nil
            infoPanel.render(staticText: nil, liveLines: backend?.liveStats() ?? [])
            infoPanel.isHidden = false
            backend?.fetchMediaInfo { [weak self] info in
                guard let self, self.infoVisible else { return }
                self.cachedInfoText = info?.formatted() ?? "No media information available"
                self.refreshHUD()
            }
        } else {
            infoPanel.isHidden = true
        }
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
            newBackend.onPauseStateChange = { [weak self] paused in
                self?.handlePauseStateChange(paused)
            }
            playerView.setBackendView(newBackend.view)
            backend = newBackend
            backendKind = kind
        }

        videoSize = nil
        window?.title = url.lastPathComponent
        backend?.open(url: url)

        if infoVisible {
            infoVisible = false
            infoPanel.isHidden = true
        }
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
        hudUpdateTimer?.invalidate()
        hudHideTimer?.invalidate()
        backend?.shutdown()
    }
}
