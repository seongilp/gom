import Foundation
import CoreMedia

struct MediaInfo {
    var fileName: String
    var filePath: String
    var fileSizeBytes: Int64?
    var container: String?
    var durationSeconds: Double?
    var videoCodec: String?
    var width: Int?
    var height: Int?
    var fps: Double?
    var videoBitrate: Double?
    var audioCodec: String?
    var sampleRate: Int?
    var channels: Int?
    var engine: String

    func formatted() -> String {
        var lines: [String] = []
        lines.append("File       \(fileName)")
        if let fileSizeBytes {
            lines.append("Size       \(Self.sizeString(fileSizeBytes))")
        }
        if let container {
            lines.append("Container  \(container)")
        }
        if let durationSeconds, durationSeconds.isFinite {
            lines.append("Duration   \(Self.timeString(durationSeconds))")
        }
        var video: [String] = []
        if let videoCodec { video.append(videoCodec) }
        if let width, let height { video.append("\(width)×\(height)") }
        if let fps, fps > 0 { video.append(String(format: "%.3ffps", fps).replacingOccurrences(of: ".000fps", with: "fps")) }
        if let videoBitrate, videoBitrate > 0 {
            video.append(String(format: "%.1f Mbps", videoBitrate / 1_000_000))
        }
        if !video.isEmpty {
            lines.append("Video      \(video.joined(separator: ", "))")
        }
        var audio: [String] = []
        if let audioCodec { audio.append(audioCodec) }
        if let sampleRate { audio.append("\(sampleRate) Hz") }
        if let channels { audio.append("\(channels)ch") }
        if !audio.isEmpty {
            lines.append("Audio      \(audio.joined(separator: ", "))")
        }
        lines.append("Engine     \(engine)")
        return lines.joined(separator: "\n")
    }

    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func sizeString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func fileSize(of url: URL) -> Int64? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64
    }

    static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    static func codecDisplayName(fourCC code: FourCharCode) -> String {
        switch fourCCString(code) {
        case "avc1", "avc3", "x264": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "av01": return "AV1"
        case "vp09": return "VP9"
        case "mp4v": return "MPEG-4"
        case "apcn", "apch", "apcs", "apco", "ap4h", "ap4x": return "ProRes"
        case "jpeg", "mjpa": return "Motion JPEG"
        case "aac ", "mp4a": return "AAC"
        case "ac-3": return "AC-3"
        case "ec-3": return "E-AC-3"
        case "lpcm": return "PCM"
        case "alac": return "ALAC"
        case ".mp3", "mp3 ": return "MP3"
        case "opus": return "Opus"
        case "flac": return "FLAC"
        case let other: return other.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }
}
