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

        let strip = ControlStripController(character: character, fallback: fallback) {
            logger.info("strip tapped (dashboard not implemented yet)")
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
        }
        self.watcher = watcher
        watcher.start()
    }
}
