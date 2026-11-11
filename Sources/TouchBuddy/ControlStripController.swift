import AppKit
import TouchBarPrivate
import TouchBuddyCore

@MainActor
private final class StripItemView: NSView {
    static let size = NSSize(width: 40, height: 30)

    let ring = CALayer()
    let sprite = SpriteView(frame: .zero)
    let fallbackDot = NSView(frame: .zero)
    let badge = NSTextField(labelWithString: "")
    private let tapButton: TapButton

    override var intrinsicContentSize: NSSize { Self.size }

    init(onTap: @escaping () -> Void) {
        tapButton = TapButton(onTap: onTap)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        ring.cornerRadius = Self.size.height / 2
        ring.borderWidth = 2
        ring.frame = CGRect(origin: .zero, size: Self.size)
        layer?.addSublayer(ring)

        sprite.frame = bounds.insetBy(dx: 7, dy: 5)
        addSubview(sprite)

        fallbackDot.wantsLayer = true
        fallbackDot.frame = bounds.insetBy(dx: 8, dy: 8)
        fallbackDot.layer?.cornerRadius = fallbackDot.frame.height / 2
        fallbackDot.isHidden = true
        addSubview(fallbackDot)

        badge.font = .systemFont(ofSize: 9, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.drawsBackground = false
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.black.cgColor
        badge.layer?.cornerRadius = 6
        badge.frame = NSRect(x: Self.size.width - 13, y: Self.size.height - 13, width: 13, height: 13)
        badge.isHidden = true
        addSubview(badge)

        tapButton.frame = bounds
        addSubview(tapButton)
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
final class ControlStripController {
    static let identifier = "ca.spollock.touchbuddy.strip"

    private let item: NSCustomTouchBarItem
    private let view: StripItemView
    private var character: CharacterDescriptor?
    private let fallback: CharacterDescriptor?
    private let frameCache: FrameCache
    private var overall: SessionState?
    private var count = 0

    init(
        character: CharacterDescriptor?, fallback: CharacterDescriptor?, frameCache: FrameCache,
        onTap: @escaping () -> Void
    ) {
        self.character = character
        self.frameCache = frameCache
        view = StripItemView(onTap: onTap)
        self.fallback = fallback
        item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(Self.identifier))
        item.view = view
        TBPAddSystemTrayItem(item)
        TBPSetControlStripPresence(Self.identifier, true)
        render()
    }

    func update(overall: SessionState?, count: Int) {
        guard overall != self.overall || count != self.count else { return }
        self.overall = overall
        self.count = count
        render()
    }

    func setCharacter(_ c: CharacterDescriptor) {
        guard c.id != character?.id else { return }
        character = c
        render()
    }

    private func render() {
        let state = overall ?? .idle
        let color = statusColor(overall)
        view.ring.borderColor = color.cgColor
        view.ring.removeAnimation(forKey: "pulse")
        if overall == .needsInput {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.4
            pulse.toValue = 1.0
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            view.ring.add(pulse, forKey: "pulse")
        }

        let resolved = frameCache.resolve(character: character, fallback: fallback, state: state)
        if let resolved {
            view.sprite.isHidden = false
            view.fallbackDot.isHidden = true
            view.sprite.play(resolved.frames, key: resolved.key)
        } else {
            view.sprite.stop()
            view.sprite.isHidden = true
            view.fallbackDot.isHidden = false
            view.fallbackDot.layer?.backgroundColor = color.cgColor
        }

        view.badge.isHidden = count <= 0
        view.badge.stringValue = count > 9 ? "9+" : "\(count)"
    }
}
