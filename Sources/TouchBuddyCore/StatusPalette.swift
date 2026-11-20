import Foundation

public func statusHex(_ state: SessionState?) -> UInt32 {
    switch state {
    case .needsInput: 0xF5A623
    case .working: 0x4A90E2
    case .finished: 0x7ED321
    case .idle, .none: 0x666666
    }
}
