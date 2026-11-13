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
            activate(Self.itermBundleID)
        }
    }

    private func selectITermSession(uniqueID: String) -> Bool {
        let found = runAppleScript(itermSelectScript(uniqueID: uniqueID)) == "found"
        if !found { logger.info("iTerm session \(uniqueID, privacy: .public) not found") }
        return found
    }

    /// Never `activate`s iTerm here: with only a hidden hotkey window that makes iTerm open a new window or tab.
    private func revealHotkeyWindowIfAny() {
        let result = runAppleScript(itermRevealHotkeyScript)
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

/// Runs on the calling thread; the generated scripts carry their own 5 second timeout.
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
