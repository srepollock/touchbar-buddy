import AppKit
import OSLog
import TouchBarPrivate

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let stripIdentifier = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.strip")
    private static let labelIdentifier = NSTouchBarItem.Identifier("ca.spollock.touchbuddy.label")

    private var stripItem: NSCustomTouchBarItem?
    private var modalBar: NSTouchBar?
    private var minimizeTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        logger.info("TBPPrivateAPIsAvailable: \(TBPPrivateAPIsAvailable(), privacy: .public)")

        let button = NSButton(title: "TB", target: self, action: #selector(stripTapped))
        button.bezelColor = .systemOrange
        let item = NSCustomTouchBarItem(identifier: Self.stripIdentifier)
        item.view = button
        stripItem = item

        TBPAddSystemTrayItem(item)
        TBPSetControlStripPresence(Self.stripIdentifier.rawValue, true)
    }

    @objc private func stripTapped() {
        let bar = NSTouchBar()
        bar.defaultItemIdentifiers = [Self.labelIdentifier]
        let labelItem = NSCustomTouchBarItem(identifier: Self.labelIdentifier)
        labelItem.view = NSTextField(labelWithString: "TouchBuddy spike ✅")
        bar.templateItems = [labelItem]
        modalBar = bar

        TBPShowCloseBoxWhenFrontMost(true)
        TBPPresentSystemModal(bar, Self.stripIdentifier.rawValue)

        minimizeTask?.cancel()
        minimizeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let bar = self?.modalBar else { return }
            TBPMinimizeSystemModal(bar)
        }
    }
}
