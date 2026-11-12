import Foundation

public enum HookInstallerError: Error, Equatable {
    case invalidJSON
    case notAnObject
}

public enum HookInstaller {
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop",
        "SessionEnd",
    ]
    public static let marker = "touchbuddy-hook"

    public static func hookCommand(helperPath: String) -> String {
        let quoted = "'" + helperPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "[ -x \(quoted) ] && \(quoted); exit 0"
    }

    public static func defaultSettingsURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["TOUCHBUDDY_CLAUDE_SETTINGS_LOCAL"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.local.json")
    }

    // MARK: - Pure transforms

    public static func install(into settings: JSONValue, command: String) -> JSONValue {
        var root = objectValue(settings)
        var hooks = objectValue(root["hooks"])
        for event in events {
            var groups = arrayValue(hooks[event])
            if groups.contains(where: { commands(in: $0).contains(command) }) { continue }
            groups = groups.compactMap { removingOurs(from: $0) }
            groups.append(.object(["hooks": .array([.object([
                "type": .string("command"),
                "command": .string(command),
                "timeout": .number(5),
            ])])]))
            hooks[event] = .array(groups)
        }
        root["hooks"] = .object(hooks)
        return .object(root)
    }

    public static func uninstall(from settings: JSONValue) -> JSONValue {
        guard case .object(var root) = settings, case .object(var hooks)? = root["hooks"] else {
            return settings
        }
        for (event, value) in hooks {
            guard case .array(let groups) = value else { continue }
            let remaining = groups.compactMap { removingOurs(from: $0) }
            if remaining.isEmpty {
                hooks[event] = nil
            } else {
                hooks[event] = .array(remaining)
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : .object(hooks)
        return .object(root)
    }

    public static func isInstalled(in settings: JSONValue) -> Bool {
        guard case .object(let root) = settings, case .object(let hooks)? = root["hooks"] else { return false }
        return hooks.values.contains { value in
            guard case .array(let groups) = value else { return false }
            return groups.contains { commands(in: $0).contains { $0.contains(marker) } }
        }
    }

    /// Events for which no TouchBuddy hook is registered (an old install lacks newer events).
    public static func missingEvents(in settings: JSONValue) -> [String] {
        guard case .object(let root) = settings, case .object(let hooks)? = root["hooks"] else { return events }
        return events.filter { event in
            guard case .array(let groups)? = hooks[event] else { return true }
            return !groups.contains { commands(in: $0).contains { $0.contains(marker) } }
        }
    }

    // MARK: - File level

    public static func installFile(at url: URL, command: String, now: Date) throws {
        try transformFile(at: url, now: now, validate: validateForInstall) {
            install(into: $0, command: command)
        }
    }

    public static func uninstallFile(at url: URL, now: Date) throws {
        try transformFile(at: url, now: now, requireInstalled: true) { uninstall(from: $0) }
    }

    private static func validateForInstall(_ settings: JSONValue) throws {
        guard case .object(let root) = settings else { throw HookInstallerError.notAnObject }
        guard let hooksValue = root["hooks"] else { return }
        guard case .object(let hooks) = hooksValue else { throw HookInstallerError.notAnObject }
        for event in events {
            if let value = hooks[event], case .array = value { continue }
            if hooks[event] != nil { throw HookInstallerError.notAnObject }
        }
    }

    private static func resolveTarget(_ url: URL) -> URL {
        let fileManager = FileManager.default
        var current = url
        for _ in 0..<32 {
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: current.path) else {
                return current
            }
            current = URL(
                fileURLWithPath: destination,
                relativeTo: current.deletingLastPathComponent()
            ).standardizedFileURL
        }
        return current
    }

    private static func transformFile(
        at url: URL, now: Date, requireInstalled: Bool = false,
        validate: (JSONValue) throws -> Void = { _ in },
        transform: (JSONValue) -> JSONValue
    ) throws {
        let target = resolveTarget(url)
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: target.path)

        var current = JSONValue.object([:])
        if exists {
            let data = try Data(contentsOf: target)
            guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                throw HookInstallerError.invalidJSON
            }
            guard case .object = decoded else { throw HookInstallerError.notAnObject }
            current = decoded
        } else if requireInstalled {
            return
        }
        try validate(current)
        if requireInstalled, !isInstalled(in: current) { return }

        let directory = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var mode = 0o600
        if exists {
            if let existing = (try fileManager.attributesOfItem(atPath: target.path))[.posixPermissions] as? Int {
                mode = existing
            }
            try fileManager.copyItem(at: target, to: uniqueBackupURL(for: target, now: now))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var output = try encoder.encode(transform(current))
        output.append(0x0A)

        let temp = directory.appendingPathComponent(".\(target.lastPathComponent).touchbuddy-tmp-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            try output.write(to: temp)
            try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: temp.path)
            guard rename(temp.path, target.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }

    private static func uniqueBackupURL(for target: URL, now: Date) -> URL {
        let directory = target.deletingLastPathComponent()
        let base = "\(target.lastPathComponent).touchbuddy-backup-\(timestamp(now))"
        var candidate = directory.appendingPathComponent(base)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter)")
            counter += 1
        }
        return candidate
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    // MARK: - Helpers

    private static func objectValue(_ value: JSONValue?) -> [String: JSONValue] {
        if case .object(let object)? = value { return object }
        return [:]
    }

    private static func arrayValue(_ value: JSONValue?) -> [JSONValue] {
        if case .array(let array)? = value { return array }
        return []
    }

    private static func commands(in group: JSONValue) -> [String] {
        arrayValue(objectValue(group)["hooks"]).compactMap { hook in
            if case .string(let command)? = objectValue(hook)["command"] { return command }
            return nil
        }
    }

    /// Returns nil when the group held only our commands (so it should be dropped).
    private static func removingOurs(from group: JSONValue) -> JSONValue? {
        guard case .object(var object) = group, case .array(let hooks)? = object["hooks"] else {
            return group
        }
        let kept = hooks.filter { hook in
            guard case .string(let command)? = objectValue(hook)["command"] else { return true }
            return !command.contains(marker)
        }
        if kept.count == hooks.count { return group }
        if kept.isEmpty { return nil }
        object["hooks"] = .array(kept)
        return .object(object)
    }
}
