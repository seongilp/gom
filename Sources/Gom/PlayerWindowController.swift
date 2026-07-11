import AppKit
import UniformTypeIdentifiers

final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    private let playerView = PlayerView(frame: .zero)
    private let controlBar = ControlBar()
    private let infoPanel = InfoPanel()
    private let helpOverlay = HelpOverlay()
    private let nowPlaying = NowPlayingBridge()

    private var backend: PlaybackBackend?
    private var backendKind: BackendKind?
    private var videoSize: CGSize?
    private var currentURL: URL?

    // Playback state mirrored for HUD / new backends
    private var isPaused = true
    private var playbackRate: Double = 1.0
    private var loopEnabled = false
    private var alwaysOnTop = false

    // Queue (multi-file drop)
    private var playQueue: [URL] = []
    private var queueIndex = 0

    // Deferred work applied once the file is actually loaded (first video-size event)
    private var pendingResumePosition: Double?
    private var pendingSubtitle: URL?

    private var infoVisible = false
    private var cachedInfoText: String?
    private var hudUpdateTimer: Timer?
    private var hudHideTimer: Timer?
    private var positionSaveCounter = 0

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

        playerView.onOpenFiles = { [weak self] urls in self?.handleDroppedFiles(urls) }
        playerView.onAction = { [weak self] action in self?.perform(action) }
        playerView.onHoverChange = { [weak self] inside in self?.setWindowButtonsVisible(inside) }
        playerView.onMouseMoved = { [weak self] in self?.showHUDTransiently() }

        nowPlaying.activate()
        nowPlaying.onPlayPause = { [weak self] in self?.perform(.togglePlayPause) }
        nowPlaying.onSkip = { [weak self] seconds in self?.perform(.seekBy(seconds)) }

        setUpOverlays()
        setWindowButtonsVisible(false)
        MainMenu.rebuildRecents()
    }

    // MARK: - Actions

    private func perform(_ action: PlayerAction) {
        switch action {
        case .togglePlayPause:
            backend?.togglePlayPause()
        case .seekBy(let seconds):
            backend?.seek(by: seconds)
            showHUDTransiently()
        case .seekToStart:
            backend?.seek(to: 0)
            showHUDTransiently()
        case .seekToEnd:
            if let backend, backend.duration > 0 {
                backend.seek(to: backend.duration - 0.5)
            }
            showHUDTransiently()
        case .volumeBy(let delta):
            backend?.adjustVolume(by: delta)
            showHUDTransiently()
        case .scaleWindow(let scale):
            resizeWindow(scale: scale)
        case .speedUp:
            setRate(playbackRate + 0.25)
        case .speedDown:
            setRate(playbackRate - 0.25)
        case .speedReset:
            setRate(1.0)
        case .frameStep(let forward):
            backend?.stepFrame(forward: forward)
            showHUDTransiently()
        case .toggleLoop:
            loopEnabled.toggle()
            backend?.isLoopEnabled = loopEnabled
            showHUDTransiently()
        case .toggleMute:
            backend?.toggleMute()
            showHUDTransiently()
        case .toggleInfo:
            toggleInfoPanel()
        case .toggleSubtitles:
            backend?.toggleSubtitles()
            showHUDTransiently()
        case .toggleAlwaysOnTop:
            alwaysOnTop.toggle()
            window?.level = alwaysOnTop ? .floating : .normal
            showHUDTransiently()
        case .toggleHelp:
            helpOverlay.isHidden.toggle()
        case .snapshot:
            takeSnapshot()
        case .closeOverlays:
            helpOverlay.isHidden = true
            if infoVisible {
                infoVisible = false
                infoPanel.isHidden = true
            }
        }
    }

    private func setRate(_ rate: Double) {
        playbackRate = min(max(rate, 0.25), 3.0)
        backend?.playbackRate = playbackRate
        showHUDTransiently()
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
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            self?.handleDroppedFiles(panel.urls)
        }
    }

    func open(urls: [URL]) {
        handleDroppedFiles(urls)
    }

    private func handleDroppedFiles(_ urls: [URL]) {
        let subtitles = urls.filter { FolderNavigator.subtitleExtensions.contains($0.pathExtension.lowercased()) }
        let videos = urls
            .filter { !FolderNavigator.subtitleExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        if let subtitle = subtitles.first, videos.isEmpty {
            loadDroppedSubtitle(subtitle)
            return
        }
        guard !videos.isEmpty else { return }

        if videos.count > 1 {
            playQueue = videos
            queueIndex = 0
        } else {
            playQueue = []
        }
        open(url: videos[0])
    }

    private func loadDroppedSubtitle(_ subtitle: URL) {
        guard let currentURL else { return }
        if backendKind == .mpv {
            backend?.loadSubtitle(url: subtitle)
        } else {
            // AVFoundation cannot render external subtitles — reopen with mpv.
            let position = backend?.currentTime ?? 0
            pendingSubtitle = subtitle
            open(url: currentURL, using: .mpv, resumeAt: position > 1 ? position : nil)
        }
        showHUDTransiently()
    }

    func open(url: URL) {
        savePlaybackPosition()
        let resume = PlaybackStore.shared.resumePosition(for: url)
        open(url: url, using: BackendKind.forFile(at: url), resumeAt: resume)
    }

    private func open(url: URL, using kind: BackendKind, resumeAt: Double? = nil) {
        if backendKind != kind || backend == nil {
            backend?.shutdown()
            let newBackend: PlaybackBackend = (kind == .mpv) ? MpvBackend() : AVPlayerBackend()
            newBackend.onVideoSizeChange = { [weak self] size in
                self?.handleVideoLoaded(size: size)
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
            newBackend.onPlaybackEnded = { [weak self] in
                self?.handlePlaybackEnded()
            }
            playerView.setBackendView(newBackend.view)
            backend = newBackend
            backendKind = kind
        }

        videoSize = nil
        currentURL = url
        pendingResumePosition = resumeAt
        window?.title = url.lastPathComponent
        backend?.open(url: url)
        backend?.playbackRate = playbackRate
        backend?.isLoopEnabled = loopEnabled

        PlaybackStore.shared.addRecent(url)
        MainMenu.rebuildRecents()
        nowPlaying.updateMetadata(title: url.lastPathComponent, duration: 0)

        if infoVisible {
            infoVisible = false
            infoPanel.isHidden = true
        }
    }

    private func handleVideoLoaded(size: CGSize) {
        let firstLoad = videoSize == nil
        videoSize = size
        if firstLoad {
            resizeWindow(scale: 1.0)
            if let position = pendingResumePosition {
                pendingResumePosition = nil
                backend?.seek(to: position)
            }
            if let subtitle = pendingSubtitle {
                pendingSubtitle = nil
                backend?.loadSubtitle(url: subtitle)
            }
            if let backend {
                nowPlaying.updateMetadata(
                    title: currentURL?.lastPathComponent ?? "Gom",
                    duration: backend.duration
                )
            }
        }
    }

    private func handlePlaybackEnded() {
        savePlaybackPosition()
        if !playQueue.isEmpty, queueIndex + 1 < playQueue.count {
            queueIndex += 1
            open(url: playQueue[queueIndex])
        }
    }

    // MARK: - Queue / folder navigation

    @objc func nextFile(_ sender: Any?) {
        advance(by: 1)
    }

    @objc func previousFile(_ sender: Any?) {
        advance(by: -1)
    }

    private func advance(by offset: Int) {
        if !playQueue.isEmpty {
            let target = queueIndex + offset
            guard playQueue.indices.contains(target) else { return }
            queueIndex = target
            open(url: playQueue[target])
            return
        }
        guard let currentURL else { return }
        let neighbor = offset > 0
            ? FolderNavigator.next(after: currentURL)
            : FolderNavigator.previous(before: currentURL)
        if let neighbor {
            open(url: neighbor)
        }
    }

    // MARK: - Menu actions (responder chain)

    @objc func openRecentItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        playQueue = []
        open(url: url)
    }

    @objc func clearRecentItems(_ sender: Any?) {
        PlaybackStore.shared.clearRecents()
        MainMenu.rebuildRecents()
    }

    @objc func togglePlayPauseAction(_ sender: Any?) { perform(.togglePlayPause) }
    @objc func increaseSpeedAction(_ sender: Any?) { perform(.speedUp) }
    @objc func decreaseSpeedAction(_ sender: Any?) { perform(.speedDown) }
    @objc func resetSpeedAction(_ sender: Any?) { perform(.speedReset) }
    @objc func frameForwardAction(_ sender: Any?) { perform(.frameStep(forward: true)) }
    @objc func frameBackwardAction(_ sender: Any?) { perform(.frameStep(forward: false)) }
    @objc func toggleLoopAction(_ sender: Any?) { perform(.toggleLoop) }
    @objc func snapshotAction(_ sender: Any?) { perform(.snapshot) }
    @objc func toggleSubtitlesAction(_ sender: Any?) { perform(.toggleSubtitles) }
    @objc func toggleAlwaysOnTopAction(_ sender: Any?) { perform(.toggleAlwaysOnTop) }
    @objc func toggleInfoAction(_ sender: Any?) { perform(.toggleInfo) }
    @objc func toggleHelpAction(_ sender: Any?) { perform(.toggleHelp) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleLoopAction(_:)):
            menuItem.state = loopEnabled ? .on : .off
        case #selector(toggleAlwaysOnTopAction(_:)):
            menuItem.state = alwaysOnTop ? .on : .off
        default:
            break
        }
        return true
    }

    // MARK: - Snapshot

    private func takeSnapshot() {
        guard let backend, let currentURL else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        let baseName = currentURL.deletingPathExtension().lastPathComponent
        let fileName = "\(baseName)_\(formatter.string(from: Date())).png"

        let videoDirectory = currentURL.deletingLastPathComponent()
        let directory = FileManager.default.isWritableFile(atPath: videoDirectory.path)
            ? videoDirectory
            : FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? videoDirectory
        let destination = directory.appendingPathComponent(fileName)

        backend.captureSnapshot(to: destination) { [weak self] success in
            if success {
                NSSound(named: "Tink")?.play()
            }
            self?.showHUDTransiently()
        }
    }

    // MARK: - Playback position persistence

    private func savePlaybackPosition() {
        guard let backend, let currentURL, backend.duration > 0 else { return }
        PlaybackStore.shared.savePosition(
            backend.currentTime,
            duration: backend.duration,
            for: currentURL
        )
    }

    // MARK: - Overlays / HUD

    private func setUpOverlays() {
        playerView.addSubview(controlBar)
        playerView.addSubview(infoPanel)
        playerView.addSubview(helpOverlay)
        controlBar.alphaValue = 0
        controlBar.isHidden = true
        infoPanel.isHidden = true
        helpOverlay.isHidden = true

        controlBar.onSeekFraction = { [weak self] fraction in
            guard let backend = self?.backend, backend.duration > 0 else { return }
            backend.seek(to: fraction * backend.duration)
        }
        controlBar.onPlayPause = { [weak self] in self?.perform(.togglePlayPause) }

        NSLayoutConstraint.activate([
            controlBar.leadingAnchor.constraint(equalTo: playerView.leadingAnchor, constant: 16),
            controlBar.trailingAnchor.constraint(equalTo: playerView.trailingAnchor, constant: -16),
            controlBar.bottomAnchor.constraint(equalTo: playerView.bottomAnchor, constant: -16),
            controlBar.heightAnchor.constraint(equalToConstant: 44),

            infoPanel.trailingAnchor.constraint(equalTo: playerView.trailingAnchor, constant: -16),
            infoPanel.topAnchor.constraint(equalTo: playerView.topAnchor, constant: 16),
            infoPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 560),

            helpOverlay.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            helpOverlay.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
        ])

        hudUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
    }

    private func timerTick() {
        refreshHUD()

        guard let backend else { return }
        nowPlaying.updateProgress(position: backend.currentTime, rate: isPaused ? 0 : playbackRate)

        // Persist resume position roughly every 2 seconds while playing.
        positionSaveCounter += 1
        if positionSaveCounter >= 8 {
            positionSaveCounter = 0
            if !isPaused {
                savePlaybackPosition()
            }
        }
    }

    private func refreshHUD() {
        guard let backend else { return }
        if !controlBar.isHidden {
            controlBar.update(
                current: backend.currentTime,
                duration: backend.duration,
                volume: backend.volume,
                muted: backend.isMuted,
                paused: isPaused,
                rate: playbackRate,
                looping: loopEnabled
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
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func handlePauseStateChange(_ paused: Bool) {
        isPaused = paused
        nowPlaying.setPlaying(!paused)
        nowPlaying.updateProgress(
            position: backend?.currentTime ?? 0,
            rate: paused ? 0 : playbackRate,
            force: true
        )
        if paused {
            hudHideTimer?.invalidate()
            setControlBarVisible(true)
            savePlaybackPosition()
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
        savePlaybackPosition()
        nowPlaying.setPlaying(false)
        hudUpdateTimer?.invalidate()
        hudHideTimer?.invalidate()
        backend?.shutdown()
    }
}
