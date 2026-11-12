import AppKit
import OSLog
import TouchBarPrivate
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let paths = TouchBuddyPaths.resolve()
    private var available: [CharacterDescriptor] = []
    private var strip: ControlStripController?
    private var statusMenu: StatusMenu?
    private var watcher: SessionWatcher?
    private var dashboard: DashboardController?
    private var latestSessions: [SessionRecord] = []
    private let frameCache = FrameCache()
    private let focuser = SessionFocuser()
    private lazy var replySender = ReplySender(store: SessionStore(directory: paths.sessions))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        logger.info("TBPPrivateAPIsAvailable: \(TBPPrivateAPIsAvailable(), privacy: .public)")

        let builtInDir = Bundle.main.resourceURL?.appendingPathComponent("Characters", isDirectory: true)
            ?? paths.characters
        available = discoverCharacters(builtInDir: builtInDir, userDir: paths.characters)
        let fallback = available.first { $0.id == "builtin/sparky" }

        let character = resolveSelectedCharacter(id: preferences.characterID, available: available)
        if character == nil {
            logger.error("no characters available at \(builtInDir.path, privacy: .public); showing plain status dot")
        }

        let dashboard = DashboardController(
            prefs: preferences, frames: frameCache, fallback: fallback,
            onChipTap: { [weak self] session in
                logger.info("chip tapped session=\(session.sessionID, privacy: .public)")
                self?.focuser.focus(session)
                self?.dashboard?.dismiss()
            },
            onReply: { [weak self] reply, session in
                self?.replySender.send(reply, shownFor: session) ?? false
            }
        )
        self.dashboard = dashboard

        let strip = ControlStripController(character: character, fallback: fallback, frameCache: frameCache) { [weak self] in
            self?.openDashboardManually()
        }
        self.strip = strip

        statusMenu = StatusMenu(
            preferences: preferences,
            userCharactersDir: paths.characters,
            settingsURL: HookInstaller.defaultSettingsURL(),
            helperPath: "/Applications/TouchBuddy.app/Contents/MacOS/touchbuddy-hook",
            characters: { [weak self] in
                guard let self else { return [] }
                self.available = discoverCharacters(builtInDir: builtInDir, userDir: self.paths.characters)
                return self.available
            },
            selectedID: { [weak self] in
                guard let self else { return nil }
                return resolveSelectedCharacter(id: self.preferences.characterID, available: self.available)?.id
            },
            onCharacterSelected: { [weak strip] descriptor in
                strip?.setCharacter(descriptor)
            }
        )

        let watcher = SessionWatcher(store: SessionStore(directory: paths.sessions), directory: paths.sessions)
        watcher.onChange = { [weak self] sessions, triggers in
            let now = Date()
            let overall = overallState(sessions, now: now)
            logger.info("sessions=\(sessions.count, privacy: .public) overall=\(overall?.rawValue ?? "none", privacy: .public) triggers=\(triggers.count, privacy: .public)")
            self?.strip?.update(overall: overall, count: sessions.count)
            self?.statusMenu?.setOverall(overall)
            self?.latestSessions = sessions
            self?.handleDashboard(sessions: sessions, triggers: triggers)
        }
        self.watcher = watcher
        watcher.start()
    }

    private func currentCharacter() -> CharacterDescriptor? {
        resolveSelectedCharacter(id: preferences.characterID, available: available)
    }

    private func openDashboardManually() {
        guard let character = currentCharacter() else {
            logger.error("cannot open dashboard: no characters available")
            return
        }
        dashboard?.show(sessions: latestSessions, focus: latestSessions.first, character: character, autoDismiss: false)
    }

    private func handleDashboard(sessions: [SessionRecord], triggers: [SessionRecord]) {
        if let trigger = triggers.first {
            guard let character = currentCharacter() else {
                logger.error("cannot pop dashboard: no characters available")
                return
            }
            dashboard?.show(sessions: sessions, focus: trigger, character: character, autoDismiss: true)
        } else {
            dashboard?.refresh(sessions: sessions)
        }
    }
}
