import Foundation
import Testing
@testable import TouchBuddyCore

private let helperPath = "/Applications/TouchBuddy.app/Contents/MacOS/touchbuddy-hook"
private var ourCommand: String { HookInstaller.hookCommand(helperPath: helperPath) }

private func parse(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private let ownerSettings = """
{
  "permissions": { "allow": ["Bash(git status)", "Read(*)"], "deny": [] },
  "env": { "FOO": "bar", "RETRIES": 3 },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/usr/local/bin/guard.sh", "timeout": 10 } ] },
      { "hooks": [ { "type": "command", "command": "echo pre-any" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "prettier --write" } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command", "command": "osascript -e 'beep'" } ] }
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "echo start" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "echo prompt" } ] }
    ]
  }
}
"""

private func groups(_ settings: JSONValue, _ event: String) -> [JSONValue] {
    guard case .object(let root) = settings, case .object(let hooks)? = root["hooks"],
          case .array(let list)? = hooks[event] else { return [] }
    return list
}

/// Test fixture: a settings object as the retired installer used to write it.
private func installed(_ settings: JSONValue) -> JSONValue {
    guard case .object(var root) = settings else { return settings }
    var hooks: [String: JSONValue] = [:]
    if case .object(let existing)? = root["hooks"] { hooks = existing }
    for event in HookInstaller.events {
        var list: [JSONValue] = []
        if case .array(let groups)? = hooks[event] { list = groups }
        hooks[event] = .array(list + [ourGroup()])
    }
    root["hooks"] = .object(hooks)
    return .object(root)
}

private func writeInstalled(at url: URL) throws {
    let existing = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    let data = try JSONEncoder().encode(installed(existing ?? .object([:])))
    try data.write(to: url)
}

private func ourGroup() -> JSONValue {
    .object(["hooks": .array([.object([
        "type": .string("command"), "command": .string(ourCommand), "timeout": .number(5),
    ])])])
}

@Test func hookCommandFormat() {
    #expect(ourCommand == "[ -x '\(helperPath)' ] && '\(helperPath)'; exit 0")
    #expect(ourCommand.contains(HookInstaller.marker))
}

@Test func uninstallRemovesOnlyOurs() throws {
    let original = try parse(ownerSettings)
    let withOurs = installed(original)
    #expect(HookInstaller.uninstall(from: withOurs) == original)
    #expect(!HookInstaller.isInstalled(in: HookInstaller.uninstall(from: withOurs)))
}

@Test func uninstallKeepsOtherCommandsInSharedGroup() throws {
    let shared = try parse("""
    { "hooks": { "Stop": [ { "hooks": [
      { "type": "command", "command": "echo mine" },
      { "type": "command", "command": "\(ourCommand)" }
    ] } ] } }
    """)
    let expected = try parse("""
    { "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "echo mine" } ] } ] } }
    """)
    #expect(HookInstaller.uninstall(from: shared) == expected)
}

@Test func uninstallDropsEmptiedHooksObject() throws {
    let original = try parse(#"{ "env": { "A": "b" } }"#)
    let withOurs = installed(original)
    #expect(HookInstaller.uninstall(from: withOurs) == original)
}

@Test func numbersEncodeWithoutFraction() throws {
    let data = try JSONEncoder().encode(JSONValue.object(["a": .number(5), "b": .number(1.5)]))
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"a\":5"))
    #expect(!text.contains("5.0"))
    #expect(text.contains("1.5"))
}

@Test func uninstallFileRemovesOursAndBacksUp() throws {
    let dir = try makeTempDirectory()
    let url = dir.appendingPathComponent("settings.local.json")
    try Data(ownerSettings.utf8).write(to: url)
    try writeInstalled(at: url)
    try HookInstaller.uninstallFile(at: url, now: Date(timeIntervalSince1970: 1_700_000_100))
    let written = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    #expect(written == (try parse(ownerSettings)))
}

@Test func hookCommandExitsZeroWhenMissing() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", HookInstaller.hookCommand(helperPath: "/nonexistent")]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

@Test func defaultSettingsURLHonoursOverride() {
    let url = HookInstaller.defaultSettingsURL(environment: ["TOUCHBUDDY_CLAUDE_SETTINGS_LOCAL": "/tmp/x/settings.local.json"])
    #expect(url.path == "/tmp/x/settings.local.json")
    let fallback = HookInstaller.defaultSettingsURL(environment: [:])
    #expect(fallback.path.hasSuffix("/.claude/settings.local.json"))
}

private func backups(in dir: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.contains(".touchbuddy-backup-") }.sorted()
}

private func mode(_ url: URL) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
}

@Test func sameSecondBackupsAreNeverOverwritten() throws {
    let dir = try makeTempDirectory()
    let url = dir.appendingPathComponent("settings.local.json")
    try Data(ownerSettings.utf8).write(to: url)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try writeInstalled(at: url)
    let firstInstalled = try Data(contentsOf: url)
    try HookInstaller.uninstallFile(at: url, now: now)
    try writeInstalled(at: url)
    try HookInstaller.uninstallFile(at: url, now: now)
    let names = try backups(in: dir)
    #expect(names.count == 2)
    let first = try #require(names.first { !$0.hasSuffix("-1") })
    #expect(try Data(contentsOf: dir.appendingPathComponent(first)) == firstInstalled)
}

@Test func uninstallFileMissingFileDoesNothing() throws {
    let dir = try makeTempDirectory()
    try HookInstaller.uninstallFile(at: dir.appendingPathComponent("settings.local.json"), now: Date())
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
}

@Test func uninstallFileNotInstalledDoesNothing() throws {
    let dir = try makeTempDirectory()
    let url = dir.appendingPathComponent("settings.local.json")
    let bytes = Data("{ \"env\": {\"A\":\"b\"} }".utf8)
    try bytes.write(to: url)
    try HookInstaller.uninstallFile(at: url, now: Date())
    #expect(try Data(contentsOf: url) == bytes)
    #expect(try backups(in: dir).isEmpty)
}

@Test func hookCommandEscapesSingleQuotes() throws {
    let command = HookInstaller.hookCommand(helperPath: "/tmp/it's here/touchbuddy-hook")
    #expect(command.contains("'/tmp/it'\\''s here/touchbuddy-hook'"))
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

@Test func uninstallRemovesPermissionRequest() {
    #expect(HookInstaller.events.contains("PermissionRequest"))
    let result = installed(.object([:]))
    #expect(groups(result, "PermissionRequest") == [ourGroup()])
    let removed = HookInstaller.uninstall(from: result)
    #expect(groups(removed, "PermissionRequest").isEmpty)
}

