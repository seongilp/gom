import Foundation
import MediaPlayer

/// Media-key / Now Playing integration plus display-sleep prevention while playing.
final class NowPlayingBridge {
    var onPlayPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?

    private var sleepActivity: NSObjectProtocol?
    private var lastElapsedPush: TimeInterval = 0

    func activate() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [5]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.onSkip?(5)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [5]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.onSkip?(-5)
            return .success
        }
    }

    func updateMetadata(title: String, duration: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyPlaybackDuration] = duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Cheap to call from a fast timer; throttles actual pushes to ~1/s.
    func updateProgress(position: Double, rate: Double, force: Bool = false) {
        let now = Date().timeIntervalSinceReferenceDate
        guard force || now - lastElapsedPush >= 1 else { return }
        lastElapsedPush = now
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func setPlaying(_ playing: Bool) {
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
        if playing {
            if sleepActivity == nil {
                sleepActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .userInitiated],
                    reason: "Video playback"
                )
            }
        } else if let sleepActivity {
            ProcessInfo.processInfo.endActivity(sleepActivity)
            self.sleepActivity = nil
        }
    }
}
