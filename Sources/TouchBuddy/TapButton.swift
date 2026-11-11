import AppKit

@MainActor
final class TapButton: NSButton {
    private let handler: () -> Void

    init(onTap: @escaping () -> Void) {
        handler = onTap
        super.init(frame: .zero)
        title = ""
        isBordered = false
        isTransparent = true
        setButtonType(.momentaryChange)
        target = self
        action = #selector(fire)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    @objc private func fire() { handler() }
}
