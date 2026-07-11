import AppKit
import AVFoundation

/// Layer-hosting view backed directly by AVPlayerLayer (hardware-accelerated video path).
final class VideoLayerView: NSView {
    let player = AVPlayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func makeBackingLayer() -> CALayer {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        return playerLayer
    }
}

final class AVPlayerBackend: NSObject, PlaybackBackend {
    let view: NSView = VideoLayerView(frame: .zero)
    var onVideoSizeChange: ((CGSize) -> Void)?
    var onPlaybackFailed: ((URL) -> Void)?

    private var player: AVPlayer { (view as! VideoLayerView).player }
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var currentURL: URL?

    func open(url: URL) {
        currentURL = url
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        observeEnd(of: item)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed, let self, let failedURL = self.currentURL else { return }
            DispatchQueue.main.async {
                self.onPlaybackFailed?(failedURL)
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform)
            else { return }

            let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let size = CGSize(width: abs(rect.width), height: abs(rect.height))
            guard size.width > 0, size.height > 0 else { return }
            self.onVideoSizeChange?(size)
        }
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if player.timeControlStatus == .paused {
            player.play()
        } else {
            player.pause()
        }
    }

    func seek(by seconds: Double) {
        guard let item = player.currentItem else { return }
        let offset = CMTime(seconds: seconds, preferredTimescale: 600)
        var target = player.currentTime() + offset
        if target < .zero {
            target = .zero
        }
        let duration = item.duration
        if duration.isNumeric && target > duration {
            target = duration
        }
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func adjustVolume(by delta: Float) {
        player.volume = min(max(player.volume + delta, 0), 1)
    }

    func shutdown() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            (self?.view as? VideoLayerView)?.player.seek(to: .zero)
        }
    }

    deinit {
        shutdown()
    }
}
