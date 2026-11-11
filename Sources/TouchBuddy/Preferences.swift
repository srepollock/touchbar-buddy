import Foundation

@MainActor
final class Preferences {
    private enum Key {
        static let characterID = "characterID"
        static let ttsEnabled = "ttsEnabled"
        static let popupSeconds = "popupSeconds"
    }

    static let popupDurationChoices: [Double] = [4, 8, 15]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var characterID: String? {
        get { defaults.string(forKey: Key.characterID) }
        set { defaults.set(newValue, forKey: Key.characterID) }
    }

    var ttsEnabled: Bool {
        get { defaults.bool(forKey: Key.ttsEnabled) }
        set { defaults.set(newValue, forKey: Key.ttsEnabled) }
    }

    var popupSeconds: Double {
        get {
            let stored = defaults.double(forKey: Key.popupSeconds)
            return stored > 0 ? stored : 8
        }
        set { defaults.set(newValue, forKey: Key.popupSeconds) }
    }
}
