import AppKit

/// Centered keyboard-shortcut reference, toggled with `?`.
final class HelpOverlay: NSVisualEffectView {
    private static let shortcuts: [(String, String)] = [
        ("Space", "Play / Pause"),
        ("← →", "Seek ±5s   (⇧: ±30s)"),
        ("↑ ↓", "Volume"),
        ("Scroll", "Volume · horizontal: seek"),
        (", .", "Frame step (while paused)"),
        ("[ ] \\", "Speed −/+ 0.25 · reset"),
        ("Home End", "Jump to start / end"),
        ("1 2 3", "Window 50% / 100% / 200%"),
        ("⌘← ⌘→", "Previous / next file"),
        ("L", "Loop"),
        ("M", "Mute"),
        ("S", "Snapshot (PNG next to video)"),
        ("C", "Subtitles on/off"),
        ("T", "Always on top"),
        ("V", "Media info + live stats"),
        ("F / 2×click", "Full screen"),
        ("⌘O", "Open file"),
        ("?", "This help"),
    ]

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        let text = Self.shortcuts
            .map { key, desc in key.padding(toLength: 13, withPad: " ", startingAt: 0) + desc }
            .joined(separator: "\n")

        let title = NSTextField(labelWithString: "Keyboard Shortcuts")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(labelWithString: text)
        body.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        body.textColor = .white
        body.maximumNumberOfLines = 0
        body.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(body)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isHidden = true
    }
}
