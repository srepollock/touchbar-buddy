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
            if !selectITermSession(uniqueID: uniqueID) { activate(Self.itermBundleID) }
        case .claudeDesktop:
            activate(Self.claudeDesktopBundleID)
        case .itermApp:
            activate(Self.itermBundleID)
        }
    }

    private func selectITermSession(uniqueID: String) -> Bool {
        guard let script = NSAppleScript(source: itermSelectScript(uniqueID: uniqueID)) else {
            logger.error("could not compile iTerm script")
            return false
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            logger.error("iTerm script failed: \(String(describing: error), privacy: .public)")
            return false
        }
        let found = result.stringValue == "found"
        if !found { logger.info("iTerm session \(uniqueID, privacy: .public) not found") }
        return found
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
