import AppKit

/// Abstraction over the two playback engines: AVFoundation (native, hardware path)
/// and libmpv (fallback for WebM/MKV and other formats AVFoundation cannot play).
protocol PlaybackBackend: AnyObject {
    var view: NSView { get }
    var onVideoSizeChange: ((CGSize) -> Void)? { get set }
    var onPlaybackFailed: ((URL) -> Void)? { get set }
    var onPauseStateChange: ((Bool) -> Void)? { get set }

    var isPaused: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    /// Normalized 0...1
    var volume: Float { get }
    var isMuted: Bool { get }

    func open(url: URL)
    func togglePlayPause()
    func seek(by seconds: Double)
    func seek(to seconds: Double)
    func adjustVolume(by delta: Float)
    func toggleMute()
    func fetchMediaInfo(completion: @escaping (MediaInfo?) -> Void)
    /// Fast, synchronous, safe to poll several times per second.
    func liveStats() -> [(String, String)]
    func shutdown()
}

enum BackendKind {
    case native
    case mpv

    /// Formats AVFoundation cannot demux/decode go straight to mpv.
    static func forFile(at url: URL) -> BackendKind {
        let mpvExtensions: Set<String> = [
            "webm", "mkv", "ogv", "ogg", "flv", "wmv", "avi", "ts", "m2ts", "rm", "rmvb",
        ]
        return mpvExtensions.contains(url.pathExtension.lowercased()) ? .mpv : .native
    }
}
