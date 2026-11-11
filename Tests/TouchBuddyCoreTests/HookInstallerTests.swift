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

private func ourGroup() -> JSONValue {
    .object(["hooks": .array([.object([
        "type": .string("command"), "command": .string(ourCommand), "timeout": .number(5),
    ])])])
}

@Test func hookCommandFormat() {
    #expect(ourCommand == "[ -x '\(helperPath)' ] && '\(helperPath)'; exit 0")
    #expect(ourCommand.contains(HookInstaller.marker))
}

@Test func installIntoEmpty() {
    let result = HookInstaller.install(into: .object([:]), command: ourCommand)
    for event in HookInstaller.events {
        #expect(groups(result, event) == [ourGroup()])
    }
    #expect(HookInstaller.isInstalled(in: result))
}

@Test func installPreservesExistingHooks() throws {
    let original = try parse(ownerSettings)
    let result = HookInstaller.install(into: original, command: ourCommand)
    for event in ["PreToolUse", "PostToolUse", "Notification", "SessionStart", "UserPromptSubmit"] {
        let before = groups(original, event)
        let after = groups(result, event)
        #expect(Array(after.prefix(before.count)) == before)
        #expect(after.count == before.count + 1)
        #expect(after.last == ourGroup())
    }
    #expect(groups(result, "Stop") == [ourGroup()])
    #expect(groups(result, "SessionEnd") == [ourGroup()])
}

@Test func installPreservesUnrelatedKeys() throws {
    let original = try parse(ownerSettings)
    let result = HookInstaller.install(into: original, command: ourCommand)
    guard case .object(let before) = original, case .object(let after) = result else {
        Issue.record("expected objects"); return
    }
    #expect(after["permissions"] == before["permissions"])
    #expect(after["env"] == before["env"])
}

@Test func installIsIdempotent() throws {
    let once = HookInstaller.install(into: try parse(ownerSettings), command: ourCommand)
    let twice = HookInstaller.install(into: once, command: ourCommand)
    #expect(once == twice)
}

@Test func uninstallRemovesOnlyOurs() throws {
    let original = try parse(ownerSettings)
    let installed = HookInstaller.install(into: original, command: ourCommand)
    #expect(HookInstaller.uninstall(from: installed) == original)
    #expect(!HookInstaller.isInstalled(in: HookInstaller.uninstall(from: installed)))
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
    let installed = HookInstaller.install(into: original, command: ourCommand)
    #expect(HookInstaller.uninstall(from: installed) == original)
}

@Test func numbersEncodeWithoutFraction() throws {
    let data = try JSONEncoder().encode(JSONValue.object(["a": .number(5), "b": .number(1.5)]))
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"a\":5"))
    #expect(!text.contains("5.0"))
    #expect(text.contains("1.5"))
}

@Test func installFileCreatesMissingFile() throws {
    let url = try makeTempDirectory().appendingPathComponent("settings.local.json")
    try HookInstaller.installFile(at: url, command: ourCommand, now: Date())
    let written = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    #expect(HookInstaller.isInstalled(in: written))
}

@Test func installFileBacksUpExisting() throws {
    let dir = try makeTempDirectory()
    let url = dir.appendingPathComponent("settings.local.json")
    let original = Data(ownerSettings.utf8)
    try original.write(to: url)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try HookInstaller.installFile(at: url, command: ourCommand, now: now)

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let backup = dir.appendingPathComponent("settings.local.json.touchbuddy-backup-\(formatter.string(from: now))")
    #expect(try Data(contentsOf: backup) == original)
    let written = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    #expect(HookInstaller.isInstalled(in: written))
}

@Test func installFileRefusesInvalidJSON() throws {
    let dir = try makeTempDirectory()
    let url = dir.appendingPathComponent("settings.local.json")
    let bytes = Data("{ not json".utf8)
    try bytes.write(to: url)
    #expect(throws: HookInstallerError.invalidJSON) {
        try HookInstaller.installFile(at: url, command: ourCommand, now: Date())
    }
    #expect(try Data(contentsOf: url) == bytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
}

@Test func installFileRefusesNonObjectRoot() throws {
    let url = try makeTempDirectory().appendingPathComponent("settings.local.json")
    try Data("[1,2]".utf8).write(to: url)
    #expect(throws: HookInstallerError.notAnObject) {
        try HookInstaller.installFile(at: url, command: ourCommand, now: Date())
    }
}

@Test func installFileWritesThroughSymlink() throws {
    let dir = try makeTempDirectory()
    let target = dir.appendingPathComponent("real.json")
    let link = dir.appendingPathComponent("settings.local.json")
    try Data("{}".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    try HookInstaller.installFile(at: link, command: ourCommand, now: Date())

    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
    let written = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: target))
    #expect(HookInstaller.isInstalled(in: written))
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(names.contains { $0.hasPrefix("real.json.touchbuddy-backup-") })
}

@Test func uninstallFileRemovesOursAndBacksUp() throws {
    let dir = try makeTempDirectory()
    let url = dir.appendingPathComponent("settings.local.json")
    try Data(ownerSettings.utf8).write(to: url)
    try HookInstaller.installFile(at: url, command: ourCommand, now: Date(timeIntervalSince1970: 1_700_000_000))
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
    let original = Data(ownerSettings.utf8)
    try original.write(to: url)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try HookInstaller.installFile(at: url, command: ourCommand, now: now)
    try HookInstaller.uninstallFile(at: url, now: now)
    let names = try backups(in: dir)
    #expect(names.count == 2)
    let first = try #require(names.first { !$0.hasSuffix("-1") })
    #expect(try Data(contentsOf: dir.appendingPathComponent(first)) == original)
}

@Test func installKeepsExistingMode() throws {
    let dir = try makeTempDirectory()
    let url = dir.appendingPathComponent("settings.local.json")
    try Data("{}".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    try HookInstaller.installFile(at: url, command: ourCommand, now: Date())
    #expect(try mode(url) == 0o600)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("tmp") }
    #expect(leftovers.isEmpty)
}

@Test func newFileIsMode0600() throws {
    let url = try makeTempDirectory().appendingPathComponent("settings.local.json")
    try HookInstaller.installFile(at: url, command: ourCommand, now: Date())
    #expect(try mode(url) == 0o600)
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

@Test func installFileRefusesNonObjectHooks() throws {
    for json in [#"{ "hooks": [] }"#, #"{ "hooks": { "Stop": {} } }"#] {
        let dir = try makeTempDirectory()
        let url = dir.appendingPathComponent("settings.local.json")
        let bytes = Data(json.utf8)
        try bytes.write(to: url)
        #expect(throws: HookInstallerError.notAnObject) {
            try HookInstaller.installFile(at: url, command: ourCommand, now: Date())
        }
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try backups(in: dir).isEmpty)
    }
}

@Test func installFileThroughDanglingSymlinkKeepsLink() throws {
    let dir = try makeTempDirectory()
    let target = dir.appendingPathComponent("real.json")
    let link = dir.appendingPathComponent("settings.local.json")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "real.json")
    try HookInstaller.installFile(at: link, command: ourCommand, now: Date())
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "real.json")
    let written = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: target))
    #expect(HookInstaller.isInstalled(in: written))
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
