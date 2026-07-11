import AppKit

enum PlayerAction {
    case togglePlayPause
    case seekBy(Double)
    case seekToStart
    case seekToEnd
    case volumeBy(Float)
    case scaleWindow(CGFloat)
    case speedUp
    case speedDown
    case speedReset
    case frameStep(forward: Bool)
    case toggleLoop
    case toggleMute
    case toggleInfo
    case toggleSubtitles
    case toggleAlwaysOnTop
    case toggleHelp
    case snapshot
    case closeOverlays
}

/// Input container view: keyboard shortcuts, scroll wheel, drag & drop, hover tracking.
/// Hosts the active backend's video view as a full-size subview.
final class PlayerView: NSView {
    var onOpenFiles: (([URL]) -> Void)?
    var onAction: ((PlayerAction) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onMouseMoved: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var backendView: NSView?
    private var scrollSeekAccumulator: CGFloat = 0
    private var scrollVolumeAccumulator: CGFloat = 0

    private static let seekStep: Double = 5.0
    private static let bigSeekStep: Double = 30.0
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

    func setBackendView(_ newBackendView: NSView) {
        backendView?.removeFromSuperview()
        newBackendView.frame = bounds
        newBackendView.autoresizingMask = [.width, .height]
        // Keep overlay views (control bar, info panel, help) above the video.
        addSubview(newBackendView, positioned: .below, relativeTo: subviews.first)
        backendView = newBackendView
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let seekStep = shift ? Self.bigSeekStep : Self.seekStep

        switch event.keyCode {
        case 49:  // space
            onAction?(.togglePlayPause)
        case 123: // left arrow
            onAction?(.seekBy(-seekStep))
        case 124: // right arrow
            onAction?(.seekBy(seekStep))
        case 126: // up arrow
            onAction?(.volumeBy(Self.volumeStep))
        case 125: // down arrow
            onAction?(.volumeBy(-Self.volumeStep))
        case 115: // home
            onAction?(.seekToStart)
        case 119: // end
            onAction?(.seekToEnd)
        case 18:  // 1
            onAction?(.scaleWindow(0.5))
        case 19:  // 2
            onAction?(.scaleWindow(1.0))
        case 20:  // 3
            onAction?(.scaleWindow(2.0))
        case 33:  // [
            onAction?(.speedDown)
        case 30:  // ]
            onAction?(.speedUp)
        case 42:  // backslash
            onAction?(.speedReset)
        case 43:  // ,
            onAction?(.frameStep(forward: false))
        case 47:  // .
            onAction?(.frameStep(forward: true))
        case 37:  // l
            onAction?(.toggleLoop)
        case 46:  // m
            onAction?(.toggleMute)
        case 9:   // v
            onAction?(.toggleInfo)
        case 8:   // c
            onAction?(.toggleSubtitles)
        case 17:  // t
            onAction?(.toggleAlwaysOnTop)
        case 1:   // s
            onAction?(.snapshot)
        case 44:  // / or ?
            onAction?(.toggleHelp)
        case 53:  // esc
            onAction?(.closeOverlays)
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

    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 12 : 1

        if abs(dx) > abs(dy) {
            scrollSeekAccumulator += dx
            while abs(scrollSeekAccumulator) >= threshold {
                onAction?(.seekBy(scrollSeekAccumulator > 0 ? -3 : 3))
                scrollSeekAccumulator -= threshold * (scrollSeekAccumulator > 0 ? 1 : -1)
            }
        } else {
            scrollVolumeAccumulator += dy
            while abs(scrollVolumeAccumulator) >= threshold {
                onAction?(.volumeBy(scrollVolumeAccumulator > 0 ? 0.05 : -0.05))
                scrollVolumeAccumulator -= threshold * (scrollVolumeAccumulator > 0 ? 1 : -1)
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
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

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }

    // MARK: - Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender)?.isEmpty == false ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = fileURLs(from: sender), !urls.isEmpty else { return false }
        onOpenFiles?(urls)
        return true
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
    }
}
