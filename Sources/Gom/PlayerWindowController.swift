import AppKit
import AVFoundation
import UniformTypeIdentifiers

final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    private let playerView = PlayerView()
    private var videoSize: CGSize?
    private var endObserver: NSObjectProtocol?

    private static let defaultContentSize = NSSize(width: 640, height: 360)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gom"
        window.center()
        window.tabbingMode = .disallowed
        self.init(window: window)

        window.delegate = self
        window.contentView = playerView
        window.makeFirstResponder(playerView)

        playerView.onOpenFile = { [weak self] url in
            self?.open(url: url)
        }
        playerView.onScaleRequest = { [weak self] scale in
            self?.resizeWindow(scale: scale)
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - Opening files

    func presentOpenPanel() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url: url)
        }
    }

    func open(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        replaceEndObserver(for: item)

        playerView.player.replaceCurrentItem(with: item)
        playerView.player.play()

        window?.title = url.lastPathComponent
        videoSize = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform)
            else { return }

            let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let size = CGSize(width: abs(rect.width), height: abs(rect.height))
            guard size.width > 0, size.height > 0 else { return }

            self.videoSize = size
            self.resizeWindow(scale: 1.0)
        }
    }

    private func replaceEndObserver(for item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.playerView.player.seek(to: .zero)
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
}
