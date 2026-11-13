import AppKit
import OSLog
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "focus")

@MainActor
final class SessionFocuser {
    private static let itermBundleID = "com.googlecode.iterm2"
    private static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    func focus(_ r: SessionRecord) {
        switch focusTarget(for: r) {
        case .itermSession(let uniqueID):
            if !selectITermSession(uniqueID: uniqueID) { revealHotkeyWindowIfAny() }
        case .claudeDesktop:
            activate(Self.claudeDesktopBundleID)
        case .itermApp:
            focusRunningITerm()
        }
    }

    private func selectITermSession(uniqueID: String) -> Bool {
        let result = runAppleScript(itermSelectScript(uniqueID: uniqueID))
        let found = result == "found"
        if !found {
            logger.info("iTerm session \(uniqueID, privacy: .public) not found result=\(result ?? "error", privacy: .public)")
        }
        return found
    }

    /// No session to target: reveal a hotkey window, else bring an already-running iTerm forward. Never launches iTerm
    /// or reopens it (a reopen event spawns a window when only a hidden hotkey window exists).
    private func focusRunningITerm() {
        revealHotkeyWindowIfAny(then: { revealed in
            guard !revealed else { return }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.itermBundleID).first else {
                logger.info("iTerm is not running; nothing to focus")
                return
            }
            app.activate()
        })
    }

    /// Never `activate`s iTerm here: with only a hidden hotkey window that makes iTerm open a new window or tab.
    private func revealHotkeyWindowIfAny(then: ((Bool) -> Void)? = nil) {
        let result = runAppleScript(itermRevealHotkeyScript)
        then?(result == "revealed")
        logger.info("session not found; hotkey window fallback result=\(result ?? "error", privacy: .public)")
    }

    private func activate(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.error("no app for bundle id \(bundleID, privacy: .public)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { logger.error("activate failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

/// Runs on the calling thread; each script carries a 5 second timeout, so a hung iTerm can block the main thread for up to 5 s (not per window: timeouts are rethrown, not swallowed).
@MainActor
func runAppleScript(_ source: String) -> String? {
    guard let script = NSAppleScript(source: source) else {
        logger.error("could not compile AppleScript")
        return nil
    }
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    if let error {
        logger.error("AppleScript failed: \(String(describing: error), privacy: .public)")
        return nil
    }
    return result.stringValue
}
