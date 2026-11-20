import AppKit
import TouchBuddyCore

func statusColor(_ state: SessionState?) -> NSColor {
    let hex = statusHex(state)
    return NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}
