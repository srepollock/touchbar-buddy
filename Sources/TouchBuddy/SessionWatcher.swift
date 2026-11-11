import Foundation
import OSLog
import TouchBuddyCore

private let logger = Logger(subsystem: "ca.spollock.touchbuddy", category: "watcher")

@MainActor
final class SessionWatcher {
    var onChange: (_ sessions: [SessionRecord], _ triggers: [SessionRecord]) -> Void = { _, _ in }

    private let store: SessionStore
    private let directory: URL
    private var previous: [SessionRecord] = []
    private var lastSignature: [String]?
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init(store: SessionStore, directory: URL) {
        self.store = store
        self.directory = directory
    }

    func start() {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            logger.error("cannot create sessions dir: \(String(describing: error), privacy: .public)")
        }
        watchDirectory()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func watchDirectory() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("cannot watch \(self.directory.path, privacy: .public); relying on timer")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func tick() {
        let now = Date()
        let (alive, deadIDs) = partitionDead(store.loadAll(), now: now, isAlive: isProcessAlive)
        for id in deadIDs {
            logger.info("pruning dead session \(id, privacy: .public)")
            store.delete(sessionID: id)
        }
        let ordered = orderedForDisplay(alive, now: now)
        let isFirstTick = lastSignature == nil
        let triggers = isFirstTick ? [] : popupTriggers(old: previous, new: ordered, now: now)
        let signature = displaySignature(ordered, now: now)
        let changed = signature != lastSignature
        previous = ordered
        lastSignature = signature
        if changed || !triggers.isEmpty {
            onChange(ordered, triggers)
        }
    }
}
