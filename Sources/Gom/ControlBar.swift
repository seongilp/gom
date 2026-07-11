import AppKit

/// Bottom HUD: seek slider, current/total time, volume readout.
final class ControlBar: NSVisualEffectView {
    var onSeekFraction: ((Double) -> Void)?

    private let currentLabel = ControlBar.makeTimeLabel(alignment: .right)
    private let durationLabel = ControlBar.makeTimeLabel(alignment: .left)
    private let volumeLabel = ControlBar.makeTimeLabel(alignment: .right)
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = true
        slider.refusesFirstResponder = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderMoved(_:))

        for label in [currentLabel, durationLabel, volumeLabel] {
            addSubview(label)
        }
        addSubview(slider)

        NSLayoutConstraint.activate([
            currentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            currentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            currentLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),

            slider.leadingAnchor.constraint(equalTo: currentLabel.trailingAnchor, constant: 10),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),

            durationLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),

            volumeLabel.leadingAnchor.constraint(equalTo: durationLabel.trailingAnchor, constant: 12),
            volumeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            volumeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            volumeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    func update(current: Double, duration: Double, volume: Float, muted: Bool) {
        currentLabel.stringValue = MediaInfo.timeString(current)
        durationLabel.stringValue = MediaInfo.timeString(duration)
        volumeLabel.stringValue = muted ? "MUTE" : "\(Int((volume * 100).rounded()))%"

        // Don't fight the user mid-drag.
        if NSEvent.pressedMouseButtons == 0 {
            slider.doubleValue = duration > 0 ? min(max(current / duration, 0), 1) : 0
        }
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        onSeekFraction?(sender.doubleValue)
    }

    private static func makeTimeLabel(alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: "0:00")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = alignment
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
