import Foundation

/// Recent files and resume positions, persisted in UserDefaults.
final class PlaybackStore {
    static let shared = PlaybackStore()

    private let defaults = UserDefaults.standard
    private static let recentsKey = "recentFiles"
    private static let positionsKey = "resumePositions"
    private static let positionOrderKey = "resumePositionOrder"

    private static let maxRecents = 10
    private static let maxPositions = 200
    private static let minResumeSeconds: Double = 10
    private static let watchedFraction: Double = 0.95

    // MARK: - Recents

    var recents: [URL] {
        let paths = defaults.stringArray(forKey: Self.recentsKey) ?? []
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func addRecent(_ url: URL) {
        var paths = defaults.stringArray(forKey: Self.recentsKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(Self.maxRecents)), forKey: Self.recentsKey)
    }

    func clearRecents() {
        defaults.removeObject(forKey: Self.recentsKey)
    }

    // MARK: - Resume positions

    func savePosition(_ seconds: Double, duration: Double, for url: URL) {
        var positions = defaults.dictionary(forKey: Self.positionsKey) as? [String: Double] ?? [:]
        var order = defaults.stringArray(forKey: Self.positionOrderKey) ?? []

        let finished = duration > 0 && seconds / duration >= Self.watchedFraction
        if seconds < Self.minResumeSeconds || finished {
            positions.removeValue(forKey: url.path)
            order.removeAll { $0 == url.path }
        } else {
            positions[url.path] = seconds
            order.removeAll { $0 == url.path }
            order.insert(url.path, at: 0)
            while order.count > Self.maxPositions {
                let evicted = order.removeLast()
                positions.removeValue(forKey: evicted)
            }
        }
        defaults.set(positions, forKey: Self.positionsKey)
        defaults.set(order, forKey: Self.positionOrderKey)
    }

    func resumePosition(for url: URL) -> Double? {
        let positions = defaults.dictionary(forKey: Self.positionsKey) as? [String: Double] ?? [:]
        return positions[url.path]
    }
}
