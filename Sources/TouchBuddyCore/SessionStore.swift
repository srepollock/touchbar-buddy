import Foundation
import os

public struct TouchBuddyPaths: Sendable {
    public let root: URL
    public var sessions: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    public var characters: URL { root.appendingPathComponent("Characters", isDirectory: true) }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TouchBuddyPaths {
        if let home = environment["TOUCHBUDDY_HOME"], !home.isEmpty {
            return TouchBuddyPaths(root: URL(fileURLWithPath: home, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return TouchBuddyPaths(root: base.appendingPathComponent("TouchBuddy", isDirectory: true))
    }
}

public enum SessionStoreError: Error, Equatable {
    case invalidSessionID
}

public func sanitizedSessionID(_ raw: String) -> String? {
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    let cleaned = String(raw.filter { allowed.contains($0) })
    return cleaned.isEmpty ? nil : cleaned
}

public struct SessionStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func load(sessionID: String) -> SessionRecord? {
        guard let url = fileURL(for: sessionID) else { return nil }
        return read(url)
    }

    public func loadAll() -> [SessionRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap(read)
            .sorted { $0.sessionID < $1.sessionID }
    }

    public func write(_ record: SessionRecord) throws {
        guard let url = fileURL(for: record.sessionID) else { throw SessionStoreError.invalidSessionID }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try Self.encoder().encode(record)
        let temp = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            guard FileManager.default.createFile(
                atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]
            ) else { throw CocoaError(.fileWriteUnknown) }
            if rename(temp.path, url.path) != 0 {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    public func delete(sessionID: String) {
        guard let url = fileURL(for: sessionID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Serialises read-modify-write per session across hook processes. Waits at most ~200 ms, then proceeds
    /// unlocked so a stuck peer can never hang Claude Code.
    public func withSessionLock<T>(sessionID: String, _ body: () -> T) -> T {
        guard let clean = sanitizedSessionID(sessionID) else { return body() }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let path = directory.appendingPathComponent(".\(clean).lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            hookLogger.debug("lock file open failed; proceeding unlocked")
            return body()
        }
        defer { close(fd) }
        var locked = false
        for _ in 0..<40 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                locked = true
                break
            }
            usleep(5_000)
        }
        if !locked { hookLogger.debug("session lock wait timed out; proceeding unlocked") }
        defer { if locked { flock(fd, LOCK_UN) } }
        return body()
    }

    private func fileURL(for sessionID: String) -> URL? {
        sanitizedSessionID(sessionID).map { directory.appendingPathComponent("\($0).json") }
    }

    private func read(_ url: URL) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder().decode(SessionRecord.self, from: data)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private let hookLogger = Logger(subsystem: "ca.spollock.touchbuddy", category: "hook")

public func runHook(
    stdin: Data,
    environment: [String: String],
    store: SessionStore,
    claudePID: Int32?,
    now: Date
) -> Int32 {
    guard !stdin.isEmpty else {
        hookLogger.debug("empty stdin")
        return 0
    }
    let payload: HookPayload
    do {
        payload = try JSONDecoder().decode(HookPayload.self, from: stdin)
    } catch {
        hookLogger.debug("undecodable payload: \(String(describing: error), privacy: .public)")
        return 0
    }
    guard sanitizedSessionID(payload.sessionID) != nil else {
        hookLogger.debug("session_id empty after sanitising")
        return 0
    }
    let context = HookContext(
        claudePID: claudePID,
        itermSessionID: environment["ITERM_SESSION_ID"],
        entrypoint: environment["CLAUDE_CODE_ENTRYPOINT"],
        now: now
    )
    store.withSessionLock(sessionID: payload.sessionID) {
        switch reduce(existing: store.load(sessionID: payload.sessionID), payload: payload, context: context) {
        case .upsert(let record):
            do {
                try store.write(record)
            } catch {
                hookLogger.debug("write failed: \(String(describing: error), privacy: .public)")
            }
        case .delete(let sessionID):
            store.delete(sessionID: sessionID)
        case .unchanged:
            break
        }
    }
    return 0
}
