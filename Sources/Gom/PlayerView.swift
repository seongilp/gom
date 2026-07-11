import AppKit

/// Input container view: keyboard shortcuts, drag & drop, hover tracking.
/// Hosts the active backend's video view as a full-size subview.
final class PlayerView: NSView {
    var onOpenFile: ((URL) -> Void)?
    var onScaleRequest: ((CGFloat) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onVolumeChange: ((Float) -> Void)?

    private var trackingArea: NSTrackingArea?

    private static let seekStep: Double = 5.0
    private static let volumeStep: Float = 0.1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setBackendView(_ backendView: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        backendView.frame = bounds
        backendView.autoresizingMask = [.width, .height]
        addSubview(backendView)
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49:  // space
            onTogglePlayPause?()
        case 123: // left arrow
            onSeek?(-Self.seekStep)
        case 124: // right arrow
            onSeek?(Self.seekStep)
        case 126: // up arrow
            onVolumeChange?(Self.volumeStep)
        case 125: // down arrow
            onVolumeChange?(-Self.volumeStep)
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

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
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
