import Foundation

/// Previous/next video within the same directory (Finder-style ordering).
enum FolderNavigator {
    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv", "avi", "flv", "wmv",
        "ts", "m2ts", "ogv", "ogg", "rm", "rmvb", "3gp", "mpg", "mpeg",
    ]

    static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub"]

    static func siblings(of url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [url] }

        return contents
            .filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func next(after url: URL) -> URL? {
        adjacent(to: url, offset: 1)
    }

    static func previous(before url: URL) -> URL? {
        adjacent(to: url, offset: -1)
    }

    private static func adjacent(to url: URL, offset: Int) -> URL? {
        let files = siblings(of: url)
        guard let index = files.firstIndex(where: { $0.path == url.path }) else { return nil }
        let target = index + offset
        guard files.indices.contains(target) else { return nil }
        return files[target]
    }

    /// Subtitle file sitting next to the video with the same basename, if any.
    static func adjacentSubtitle(for url: URL) -> URL? {
        let base = url.deletingPathExtension()
        for ext in ["srt", "ass", "ssa", "vtt"] {
            let candidate = base.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
