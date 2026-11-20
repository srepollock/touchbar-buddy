import CryptoKit
import Foundation

/// A local Claude Code marketplace holding one plugin whose only job is to register the TouchBuddy hooks.
public enum ClaudePlugin {
    public static let marketplaceName = "touchbuddy-local"
    public static let pluginName = "touchbuddy"
    public static var pluginID: String { "\(pluginName)@\(marketplaceName)" }

    private static let description = "TouchBuddy: shows Claude Code session status on the Touch Bar"

    /// Claude Code decides "already up to date" by string equality of the manifest version, so the hooks content hash
    /// rides along as semver build metadata: changing hooks.json always yields a version `plugin update` will fetch.
    public static func pluginVersion(base: String, hooksData: Data) -> String {
        let digest = SHA256.hash(data: hooksData).prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(base)+\(digest)"
    }

    public static func files(helperPath: String, version baseVersion: String) -> [String: Data] {
        let command = HookInstaller.hookCommand(helperPath: helperPath)
        var hooks: [String: Any] = [:]
        for event in HookInstaller.events {
            hooks[event] = [["hooks": [["type": "command", "command": command, "timeout": 5] as [String: Any]]]]
        }
        let hooksData = encode(["hooks": hooks])
        let version = pluginVersion(base: baseVersion, hooksData: hooksData)
        let marketplace: [String: Any] = [
            "name": marketplaceName,
            "owner": ["name": "TouchBuddy"],
            "description": "Local marketplace for the TouchBuddy Claude Code hooks plugin",
            "plugins": [[
                "name": pluginName,
                "source": "./\(pluginName)",
                "description": description,
                "version": version,
            ] as [String: Any]],
        ]
        let plugin: [String: Any] = [
            "name": pluginName, "version": version, "description": description, "author": ["name": "TouchBuddy"],
        ]
        return [
            ".claude-plugin/marketplace.json": encode(marketplace),
            "\(pluginName)/.claude-plugin/plugin.json": encode(plugin),
            "\(pluginName)/hooks/hooks.json": hooksData,
        ]
    }

    public static func write(to dir: URL, helperPath: String, version: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

        for (relativePath, data) in files(helperPath: helperPath, version: version) {
            let target = dir.appendingPathComponent(relativePath)
            if let existing = try? Data(contentsOf: target), existing == data { continue }
            let parent = target.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let temp = parent.appendingPathComponent(".\(target.lastPathComponent).tmp-\(UUID().uuidString)")
            do {
                try data.write(to: temp)
                guard rename(temp.path, target.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            } catch {
                try? fileManager.removeItem(at: temp)
                throw error
            }
        }
    }

    public static func installCommands(pluginDir: URL) -> [String] {
        let quotedPath = "\"" + pluginDir.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`") + "\""
        return [
            "claude plugin marketplace add \(quotedPath)",
            "claude plugin install \(pluginID)",
        ]
    }

    public static func isInstalled(installedPluginsJSON: Data?) -> Bool {
        guard let data = installedPluginsJSON,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        switch root["plugins"] {
        case let plugins as [String: Any]: return plugins.keys.contains(pluginID)
        case let plugins as [Any]:
            return plugins.contains { ($0 as? String) == pluginID || ($0 as? [String: Any])?["id"] as? String == pluginID }
        default: return false
        }
    }

    public static func defaultInstalledPluginsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/installed_plugins.json")
    }

    private static func encode(_ object: [String: Any]) -> Data {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = (try? JSONSerialization.data(withJSONObject: object, options: options)) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }
}
