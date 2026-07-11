import AppKit
import AVFoundation

/// Layer-hosting view backed directly by AVPlayerLayer (hardware-accelerated video path).
final class PlayerView: NSView {
    let player = AVPlayer()

    var onOpenFile: ((URL) -> Void)?
    var onScaleRequest: ((CGFloat) -> Void)?

    private static let seekStep: Double = 5.0
    private static let volumeStep: Float = 0.1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
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

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49:  // space
            togglePlayPause()
        case 123: // left arrow
            seek(by: -Self.seekStep)
        case 124: // right arrow
            seek(by: Self.seekStep)
        case 126: // up arrow
            adjustVolume(by: Self.volumeStep)
        case 125: // down arrow
            adjustVolume(by: -Self.volumeStep)
        case 18:  // 1
            onScaleRequest?(0.5)
        case 19:  // 2
            onScaleRequest?(1.0)
        case 20:  // 3
            onScaleRequest?(2.0)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Playback controls

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if player.timeControlStatus == .paused {
            player.play()
        } else {
            player.pause()
        }
    }

    private func seek(by seconds: Double) {
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

    private func adjustVolume(by delta: Float) {
        player.volume = min(max(player.volume + delta, 0), 1)
    }

    // MARK: - Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURL(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = fileURL(from: sender) else { return false }
        onOpenFile?(url)
        return true
    }

    private func fileURL(from info: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first
    }
}
