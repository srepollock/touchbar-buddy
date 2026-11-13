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
            focusITermSession(uniqueID: uniqueID)
        case .claudeDesktop:
            activate(Self.claudeDesktopBundleID)
        case .itermApp:
            focusRunningITerm()
        }
    }

    /// Select the session. When the script reports it missing, reveal a hotkey window, else fall back to the safe
    /// running-iTerm activation (never a launch). A nil result (error, timeout, Automation denied) skips every fallback.
    private func focusITermSession(uniqueID: String) {
        guard let result = runAppleScript(itermSelectScript(uniqueID: uniqueID)) else {
            logger.info("iTerm session \(uniqueID, privacy: .public) select failed; no fallback")
            return
        }
        guard result != "found" else { return }
        logger.info("iTerm session \(uniqueID, privacy: .public) not found result=\(result, privacy: .public)")
        if !revealHotkeyWindow() { activateRunningITerm() }
    }

    /// No session to target: reveal a hotkey window, else bring an already-running iTerm forward. Never launches iTerm
    /// or reopens it (a reopen event spawns a window when only a hidden hotkey window exists).
    private func focusRunningITerm() {
        if !revealHotkeyWindow() { activateRunningITerm() }
    }

    private func activateRunningITerm() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.itermBundleID).first else {
            logger.info("iTerm is not running; nothing to focus")
            return
        }
        let activated = app.activate()
        logger.info("iTerm app activate accepted=\(activated, privacy: .public)")
    }

    /// Never `activate`s iTerm here: with only a hidden hotkey window that makes iTerm open a new window or tab.
    private func revealHotkeyWindow() -> Bool {
        let result = runAppleScript(itermRevealHotkeyScript)
        logger.info("hotkey window reveal result=\(result ?? "error", privacy: .public)")
        return result == "revealed"
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

/// Runs on the calling thread; each script carries a 5 second timeout, so a hung iTerm can block the main thread for up to 5 s per call (timeouts -1712 and user cancel -128 are rethrown by every `try` block, never swallowed). A select that reports missing plus the hotkey fallback can total up to 10 s.
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
