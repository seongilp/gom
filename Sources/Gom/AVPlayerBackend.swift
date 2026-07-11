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
    var onPauseStateChange: ((Bool) -> Void)?

    private var player: AVPlayer { (view as! VideoLayerView).player }
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var currentURL: URL?

    var isPaused: Bool { player.timeControlStatus == .paused }
    var currentTime: Double {
        let time = player.currentTime()
        return time.isNumeric ? time.seconds : 0
    }
    var duration: Double {
        guard let duration = player.currentItem?.duration, duration.isNumeric else { return 0 }
        return duration.seconds
    }
    var volume: Float { player.volume }
    var isMuted: Bool { player.isMuted }

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

        if rateObservation == nil {
            rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let paused = player.timeControlStatus == .paused
                DispatchQueue.main.async {
                    self?.onPauseStateChange?(paused)
                }
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

    func seek(to seconds: Double) {
        guard player.currentItem != nil else { return }
        let target = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func adjustVolume(by delta: Float) {
        player.volume = min(max(player.volume + delta, 0), 1)
    }

    func toggleMute() {
        player.isMuted.toggle()
    }

    func fetchMediaInfo(completion: @escaping (MediaInfo?) -> Void) {
        guard let currentURL, let asset = player.currentItem?.asset as? AVURLAsset else {
            completion(nil)
            return
        }
        let itemDuration = duration
        Task { @MainActor in
            var info = MediaInfo(
                fileName: currentURL.lastPathComponent,
                filePath: currentURL.path,
                fileSizeBytes: MediaInfo.fileSize(of: currentURL),
                container: currentURL.pathExtension.lowercased(),
                durationSeconds: itemDuration,
                engine: "AVFoundation (hardware)"
            )
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                if let (descriptions, size, fps, bitrate) = try? await track.load(
                    .formatDescriptions, .naturalSize, .nominalFrameRate, .estimatedDataRate
                ) {
                    if let description = descriptions.first {
                        info.videoCodec = MediaInfo.codecDisplayName(
                            fourCC: CMFormatDescriptionGetMediaSubType(description)
                        )
                    }
                    info.width = Int(abs(size.width))
                    info.height = Int(abs(size.height))
                    info.fps = Double(fps)
                    info.videoBitrate = Double(bitrate)
                }
            }
            if let track = try? await asset.loadTracks(withMediaType: .audio).first,
               let descriptions = try? await track.load(.formatDescriptions),
               let description = descriptions.first {
                info.audioCodec = MediaInfo.codecDisplayName(
                    fourCC: CMFormatDescriptionGetMediaSubType(description)
                )
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                    info.sampleRate = Int(asbd.mSampleRate)
                    info.channels = Int(asbd.mChannelsPerFrame)
                }
            }
            completion(info)
        }
    }

    func shutdown() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        rateObservation = nil
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
