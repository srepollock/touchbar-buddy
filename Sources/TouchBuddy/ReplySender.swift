import Foundation
import OSLog
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "reply")

@MainActor
final class ReplySender {
    private let store: SessionStore

    init(store: SessionStore) {
        self.store = store
    }

    /// Returns true only when the keystroke was delivered to the session.
    func send(_ reply: QuickReply, shownFor: SessionRecord) -> Bool {
        let current = store.load(sessionID: shownFor.sessionID)
        guard isReplyStillValid(shownFor: shownFor, current: current) else {
            logger.info("reply dropped: session \(shownFor.sessionID, privacy: .public) changed since the buttons were shown")
            return false
        }
        guard quickReplies(for: shownFor).contains(reply),
              let itermID = shownFor.itermSessionID, let uniqueID = itermUniqueID(from: itermID)
        else {
            logger.error("reply dropped: not offered for this session")
            return false
        }
        let keys = keystrokes(for: reply)
        guard !keys.isEmpty else { return false }
        let sent = runAppleScript(itermWriteScript(uniqueID: uniqueID, keystrokes: keys)) == "sent"
        logger.info("reply \(String(describing: reply), privacy: .public) sent=\(sent, privacy: .public)")
        return sent
    }
}
