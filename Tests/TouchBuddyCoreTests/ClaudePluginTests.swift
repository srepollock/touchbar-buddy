import Foundation
import Testing
@testable import TouchBuddyCore

@Suite struct ClaudePluginTests {
    private let helper = "/Applications/TouchBuddy.app/Contents/MacOS/touchbuddy-hook"

    private func json(_ path: String, version: String = "1.2.3") throws -> [String: Any] {
        let files = ClaudePlugin.files(helperPath: helper, version: version)
        let data = try #require(files[path])
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func hooksJSONRegistersEveryEventWithGuardedCommand() throws {
        let root = try json("touchbuddy/hooks/hooks.json")
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.events))
        for event in HookInstaller.events {
            let groups = try #require(hooks[event] as? [[String: Any]])
            #expect(groups.count == 1)
            let entries = try #require(groups[0]["hooks"] as? [[String: Any]])
            #expect(entries.count == 1)
            #expect(entries[0]["type"] as? String == "command")
            #expect(entries[0]["command"] as? String == HookInstaller.hookCommand(helperPath: helper))
            #expect(entries[0]["timeout"] as? Int == 5)
        }
    }

    @Test func marketplaceListsTouchbuddyPluginWithRelativeSource() throws {
        let root = try json(".claude-plugin/marketplace.json")
        #expect(root["name"] as? String == "touchbuddy-local")
        #expect((root["owner"] as? [String: Any])?["name"] as? String != nil)
        let plugins = try #require(root["plugins"] as? [[String: Any]])
        #expect(plugins.count == 1)
        #expect(plugins[0]["name"] as? String == "touchbuddy")
        #expect(plugins[0]["source"] as? String == "./touchbuddy")
        #expect(plugins[0]["version"] as? String == "1.2.3")
    }

    @Test func pluginJSONHasNameAndVersion() throws {
        let root = try json("touchbuddy/.claude-plugin/plugin.json", version: "4.5.6")
        #expect(root["name"] as? String == "touchbuddy")
        #expect(root["version"] as? String == "4.5.6")
        #expect(root["description"] as? String != nil)
    }

    @Test func installCommandsQuotePathWithSpaces() {
        let dir = URL(fileURLWithPath: "/Users/me/Library/Application Support/TouchBuddy/claude-plugin", isDirectory: true)
        #expect(ClaudePlugin.installCommands(pluginDir: dir) == [
            "claude plugin marketplace add \"/Users/me/Library/Application Support/TouchBuddy/claude-plugin\"",
            "claude plugin install touchbuddy@touchbuddy-local",
        ])
    }

    @Test func writeIsIdempotentAndDoesNotTouchUnchangedFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-plugin-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ClaudePlugin.write(to: dir, helperPath: helper, version: "1.0.0")

        let hooksURL = dir.appendingPathComponent("touchbuddy/hooks/hooks.json")
        let pluginURL = dir.appendingPathComponent("touchbuddy/.claude-plugin/plugin.json")
        let old = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: hooksURL.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: pluginURL.path)

        try ClaudePlugin.write(to: dir, helperPath: helper, version: "1.0.0")
        func mtime(_ url: URL) throws -> Date {
            try #require(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        }
        #expect(try mtime(hooksURL) == old)
        #expect(try mtime(pluginURL) == old)

        try ClaudePlugin.write(to: dir, helperPath: helper, version: "1.1.0")
        #expect(try mtime(hooksURL) == old)
        #expect(try mtime(pluginURL) != old)
        let permissions = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(permissions == 0o700)
    }

    @Test func isInstalledToleratesMissingOrGarbage() {
        #expect(!ClaudePlugin.isInstalled(installedPluginsJSON: nil))
        #expect(!ClaudePlugin.isInstalled(installedPluginsJSON: Data("not json".utf8)))
        #expect(!ClaudePlugin.isInstalled(installedPluginsJSON: Data("[1,2]".utf8)))
        #expect(!ClaudePlugin.isInstalled(installedPluginsJSON: Data(#"{"plugins":{"other@x":[]}}"#.utf8)))
        #expect(ClaudePlugin.isInstalled(
            installedPluginsJSON: Data(#"{"version":2,"plugins":{"touchbuddy@touchbuddy-local":[{"scope":"user"}]}}"#.utf8)))
        #expect(ClaudePlugin.isInstalled(
            installedPluginsJSON: Data(#"{"plugins":["touchbuddy@touchbuddy-local"]}"#.utf8)))
    }
}
