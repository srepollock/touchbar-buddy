import AppKit
import TouchBuddyCore

func statusColor(_ state: SessionState?) -> NSColor {
    switch state {
    case .needsInput: .systemOrange
    case .working: .systemBlue
    case .finished: .systemGreen
    case .idle, .none: .systemGray
    }
}
