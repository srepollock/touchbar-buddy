import AppKit

@MainActor
final class TapButton: NSButton {
    private let handler: () -> Void

    init(accessibilityLabel: String, onTap: @escaping () -> Void) {
        handler = onTap
        super.init(frame: .zero)
        title = ""
        isBordered = false
        isTransparent = true
        setButtonType(.momentaryChange)
        target = self
        action = #selector(fire)
        autoresizingMask = [.width, .height]
        setAccessibilityLabel(accessibilityLabel)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func fire() { handler() }
}
