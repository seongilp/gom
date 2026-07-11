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
    var onPlaybackEnded: (() -> Void)?

    var isLoopEnabled = false
    private var storedRate: Double = 1.0
    var playbackRate: Double {
        get { storedRate }
        set {
            storedRate = min(max(newValue, 0.25), 3.0)
            if !isPaused {
                player.rate = Float(storedRate)
            }
        }
    }

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
        item.audioTimePitchAlgorithm = .timeDomain

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
            // play() resets rate to 1; resume at the stored playback rate.
            player.rate = Float(storedRate)
        } else {
            player.pause()
        }
    }

    func stepFrame(forward: Bool) {
        guard let item = player.currentItem else { return }
        player.pause()
        item.step(byCount: forward ? 1 : -1)
    }

    func seek(by seconds: Double) {
        // Chain off the pending target so rapid presses accumulate (+5, +10, …).
        requestSeek(to: (pendingSeekTarget ?? currentTime) + seconds)
    }

    func seek(to seconds: Double) {
        requestSeek(to: seconds)
    }

    /// Coalesced, keyframe-tolerant seeking: while one seek is in flight, new
    /// requests only move the target; the newest target wins when it completes.
    /// Exact (frame-accurate) seeks decode from the previous keyframe and make
    /// arrow-key scrubbing feel like buffering.
    private var pendingSeekTarget: Double?
    private var seekInFlight = false

    private func requestSeek(to seconds: Double) {
        guard player.currentItem != nil else { return }
        var target = max(seconds, 0)
        let total = duration
        if total > 0 {
            target = min(target, total)
        }
        pendingSeekTarget = target
        if !seekInFlight {
            performNextSeek()
        }
    }

    private func performNextSeek() {
        guard let target = pendingSeekTarget else {
            seekInFlight = false
            return
        }
        pendingSeekTarget = nil
        seekInFlight = true
        let time = CMTime(seconds: target, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            DispatchQueue.main.async {
                self?.performNextSeek()
            }
        }
    }

    func adjustVolume(by delta: Float) {
        player.volume = min(max(player.volume + delta, 0), 1)
    }

    func toggleMute() {
        player.isMuted.toggle()
    }

    func captureSnapshot(to url: URL, completion: @escaping (Bool) -> Void) {
        guard let asset = player.currentItem?.asset else {
            completion(false)
            return
        }
        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        DispatchQueue.global(qos: .userInitiated).async {
            var success = false
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let png = rep.representation(using: .png, properties: [:]) {
                    success = (try? png.write(to: url)) != nil
                }
            }
            DispatchQueue.main.async { completion(success) }
        }
    }

    func loadSubtitle(url: URL) {
        // Subtitled playback is routed to the mpv backend by the controller.
    }

    func toggleSubtitles() {}

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

    func liveStats() -> [(String, String)] {
        var lines: [(String, String)] = []
        guard let item = player.currentItem else { return lines }
        if let track = item.tracks.first(where: { $0.assetTrack?.mediaType == .video }) {
            lines.append(("FPS", String(format: "%.2f", track.currentVideoFrameRate)))
        }
        if let event = item.accessLog()?.events.last {
            if event.numberOfDroppedVideoFrames >= 0 {
                lines.append(("Dropped", "\(event.numberOfDroppedVideoFrames)"))
            }
            if event.indicatedBitrate > 0 {
                lines.append(("Bitrate", String(format: "%.1f Mbps", event.indicatedBitrate / 1_000_000)))
            }
        }
        lines.append(("Rate", String(format: "%.2f×", player.rate)))
        return lines
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
            guard let self else { return }
            if self.isLoopEnabled {
                self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                self.player.rate = Float(self.storedRate)
            } else {
                self.onPlaybackEnded?()
            }
        }
    }

    deinit {
        shutdown()
    }
}
