import AppKit
import OSLog
import ServiceManagement
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "menu")

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let preferences: Preferences
    private let userCharactersDir: URL
    private let settingsURL: URL
    private let helperPath: String
    private let characters: () -> [CharacterDescriptor]
    private let onCharacterSelected: (CharacterDescriptor) -> Void
    private var selectedID: () -> String?

    init(
        preferences: Preferences,
        userCharactersDir: URL,
        settingsURL: URL,
        helperPath: String,
        characters: @escaping () -> [CharacterDescriptor],
        selectedID: @escaping () -> String?,
        onCharacterSelected: @escaping (CharacterDescriptor) -> Void
    ) {
        self.preferences = preferences
        self.userCharactersDir = userCharactersDir
        self.settingsURL = settingsURL
        self.helperPath = helperPath
        self.characters = characters
        self.selectedID = selectedID
        self.onCharacterSelected = onCharacterSelected
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        setOverall(nil)
    }

    func setOverall(_ state: SessionState?) {
        let config = NSImage.SymbolConfiguration(paletteColors: [statusColor(state)])
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "TouchBuddy")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let characterItem = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        let characterMenu = NSMenu()
        let selected = selectedID()
        for descriptor in characters() {
            let item = NSMenuItem(title: descriptor.manifest.displayName, action: #selector(selectCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = descriptor.id
            item.state = descriptor.id == selected ? .on : .off
            characterMenu.addItem(item)
        }
        characterItem.submenu = characterMenu
        menu.addItem(characterItem)

        let tts = NSMenuItem(title: "Speak lines aloud", action: #selector(toggleTTS), keyEquivalent: "")
        tts.target = self
        tts.state = preferences.ttsEnabled ? .on : .off
        menu.addItem(tts)

        let durationItem = NSMenuItem(title: "Popup duration", action: nil, keyEquivalent: "")
        let durationMenu = NSMenu()
        for seconds in Preferences.popupDurationChoices {
            let item = NSMenuItem(title: "\(Int(seconds)) s", action: #selector(selectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = preferences.popupSeconds == seconds ? .on : .off
            durationMenu.addItem(item)
        }
        durationItem.submenu = durationMenu
        menu.addItem(durationItem)

        menu.addItem(.separator())

        let hooksInstalled = Self.hooksInstalled(at: settingsURL)
        let hookItem = NSMenuItem(
            title: hooksInstalled ? "Uninstall Claude Code hooks" : "Install Claude Code hooks",
            action: hooksInstalled ? #selector(uninstallHooks) : #selector(installHooks),
            keyEquivalent: ""
        )
        hookItem.target = self
        menu.addItem(hookItem)

        let folder = NSMenuItem(title: "Open Characters Folder", action: #selector(openCharactersFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TouchBuddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    static func hooksInstalled(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return false }
        return HookInstaller.isInstalled(in: settings)
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let descriptor = characters().first(where: { $0.id == id })
        else { return }
        preferences.characterID = id
        onCharacterSelected(descriptor)
    }

    @objc private func toggleTTS() {
        preferences.ttsEnabled.toggle()
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        preferences.popupSeconds = seconds
    }

    @objc func installHooks() {
        let command = HookInstaller.hookCommand(helperPath: helperPath)
        runHookChange {
            try HookInstaller.installFile(at: settingsURL, command: command, now: Date())
        }
    }

    @objc func uninstallHooks() {
        runHookChange {
            try HookInstaller.uninstallFile(at: settingsURL, now: Date())
        }
    }

    private func runHookChange(_ change: () throws -> Void) {
        do {
            try change()
            logger.info("hook settings updated at \(self.settingsURL.path, privacy: .public)")
        } catch HookInstallerError.invalidJSON {
            showAlert("Could not update Claude Code hooks", "\(settingsURL.path) is not valid JSON. Fix or remove it, then try again.")
        } catch HookInstallerError.notAnObject {
            showAlert("Could not update Claude Code hooks", "\(settingsURL.path) has an unexpected structure (expected a JSON object with array-valued hook events).")
        } catch {
            logger.error("hook change failed: \(String(describing: error), privacy: .public)")
            showAlert("Could not update Claude Code hooks", "\(settingsURL.path): \(error.localizedDescription)")
        }
    }

    private func showAlert(_ title: String, _ detail: String) {
        logger.error("\(title, privacy: .public): \(detail, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openCharactersFolder() {
        do {
            try FileManager.default.createDirectory(at: userCharactersDir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(userCharactersDir)
        } catch {
            showAlert("Could not open characters folder", error.localizedDescription)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Could not change Launch at Login", error.localizedDescription)
        }
    }
}
