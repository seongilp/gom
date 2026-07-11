import AppKit

/// Bottom HUD: play/pause button, seek slider, times, speed/loop badges, volume readout.
final class ControlBar: NSVisualEffectView {
    var onSeekFraction: ((Double) -> Void)?
    var onPlayPause: (() -> Void)?

    private let playButton = NSButton()
    private let currentLabel = ControlBar.makeLabel()
    private let durationLabel = ControlBar.makeLabel()
    private let speedLabel = ControlBar.makeLabel(color: .systemYellow)
    private let loopLabel = ControlBar.makeLabel(color: .systemGreen)
    private let volumeLabel = ControlBar.makeLabel()
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)

    private static let playImage = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
    private static let pauseImage = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        playButton.bezelStyle = .regularSquare
        playButton.isBordered = false
        playButton.image = Self.playImage
        playButton.contentTintColor = .white
        playButton.refusesFirstResponder = true
        playButton.target = self
        playButton.action = #selector(playPausePressed)

        slider.isContinuous = true
        slider.refusesFirstResponder = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        loopLabel.stringValue = "LOOP"
        loopLabel.isHidden = true
        speedLabel.isHidden = true

        let stack = NSStackView(views: [
            playButton, currentLabel, slider, durationLabel, speedLabel, loopLabel, volumeLabel,
        ])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    func update(
        current: Double,
        duration: Double,
        volume: Float,
        muted: Bool,
        paused: Bool,
        rate: Double,
        looping: Bool
    ) {
        currentLabel.stringValue = MediaInfo.timeString(current)
        durationLabel.stringValue = MediaInfo.timeString(duration)
        volumeLabel.stringValue = muted ? "MUTE" : "\(Int((volume * 100).rounded()))%"
        playButton.image = paused ? Self.playImage : Self.pauseImage

        let showSpeed = abs(rate - 1.0) > 0.01
        speedLabel.isHidden = !showSpeed
        if showSpeed {
            speedLabel.stringValue = String(format: "%.2g×", rate)
        }
        loopLabel.isHidden = !looping

        // Don't fight the user mid-drag.
        if NSEvent.pressedMouseButtons == 0 {
            slider.doubleValue = duration > 0 ? min(max(current / duration, 0), 1) : 0
        }
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        onSeekFraction?(sender.doubleValue)
    }

    @objc private func playPausePressed() {
        onPlayPause?()
    }

    private static func makeLabel(color: NSColor = .white) -> NSTextField {
        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = color
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }
}

/// Top-left overlay showing media details (toggled with V).
final class InfoPanel: NSVisualEffectView {
    private let textLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textLabel.textColor = .white
        textLabel.maximumNumberOfLines = 0
        textLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    func render(staticText: String?, liveLines: [(String, String)]) {
        var text = staticText ?? "Loading…"
        if !liveLines.isEmpty {
            let live = liveLines
                .map { key, value in key.padding(toLength: 11, withPad: " ", startingAt: 0) + value }
                .joined(separator: "\n")
            text += "\n\n" + live
        }
        textLabel.stringValue = text
    }
}
