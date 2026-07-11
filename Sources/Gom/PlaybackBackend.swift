import AppKit

/// Abstraction over the two playback engines: AVFoundation (native, hardware path)
/// and libmpv (fallback for WebM/MKV and other formats AVFoundation cannot play).
protocol PlaybackBackend: AnyObject {
    var view: NSView { get }
    var onVideoSizeChange: ((CGSize) -> Void)? { get set }
    var onPlaybackFailed: ((URL) -> Void)? { get set }
    var onPauseStateChange: ((Bool) -> Void)? { get set }
    /// Fires at end of file when looping is off (loop is handled inside the backend).
    var onPlaybackEnded: (() -> Void)? { get set }

    var isPaused: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    /// Normalized 0...1
    var volume: Float { get }
    var isMuted: Bool { get }
    /// 0.25 ... 3.0, 1.0 = normal
    var playbackRate: Double { get set }
    var isLoopEnabled: Bool { get set }

    func open(url: URL)
    func togglePlayPause()
    func seek(by seconds: Double)
    func seek(to seconds: Double)
    func stepFrame(forward: Bool)
    func adjustVolume(by delta: Float)
    func toggleMute()
    func captureSnapshot(to url: URL, completion: @escaping (Bool) -> Void)
    /// mpv only; no-op on AVFoundation (subtitled files are routed to mpv).
    func loadSubtitle(url: URL)
    func toggleSubtitles()
    func fetchMediaInfo(completion: @escaping (MediaInfo?) -> Void)
    /// Fast, synchronous, safe to poll several times per second.
    func liveStats() -> [(String, String)]
    func shutdown()
}

enum BackendKind {
    case native
    case mpv

    /// Formats AVFoundation cannot demux/decode go straight to mpv.
    /// Files with an adjacent subtitle also go to mpv — it renders subtitles natively.
    static func forFile(at url: URL) -> BackendKind {
        let mpvExtensions: Set<String> = [
            "webm", "mkv", "ogv", "ogg", "flv", "wmv", "avi", "ts", "m2ts", "rm", "rmvb",
        ]
        if mpvExtensions.contains(url.pathExtension.lowercased()) {
            return .mpv
        }
        if FolderNavigator.adjacentSubtitle(for: url) != nil {
            return .mpv
        }
        return .native
    }
}
