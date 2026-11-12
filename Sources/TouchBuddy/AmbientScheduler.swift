import AppKit
import OSLog
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "ambient")

/// One-shot timer, rescheduled after every fire, that asks for an ambient stroll candidate.
@MainActor
final class AmbientScheduler {
    private let prefs: Preferences
    private let onFire: () -> Void
    private var timer: Timer?

    /// `TOUCHBUDDY_CHATTY_SECONDS` overrides the interval (in seconds) for testing.
    private static func overrideSeconds() -> TimeInterval? {
        guard let raw = ProcessInfo.processInfo.environment["TOUCHBUDDY_CHATTY_SECONDS"],
              let seconds = Double(raw), seconds > 0
        else { return nil }
        return seconds
    }

    init(prefs: Preferences, onFire: @escaping () -> Void) {
        self.prefs = prefs
        self.onFire = onFire
    }

    /// Restarts according to current preferences; call after a pref change.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard prefs.chattyEnabled else {
            logger.info("chatty mode off")
            return
        }
        let random = Double.random(in: 0..<1)
        let delay = Self.overrideSeconds().map { $0 * (0.7 + 0.6 * random) }
            ?? nextAmbientDelay(interval: prefs.chattyInterval, random: random)
        logger.info("next ambient check in \(Int(delay), privacy: .public) s")
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onFire()
                self.reschedule()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
