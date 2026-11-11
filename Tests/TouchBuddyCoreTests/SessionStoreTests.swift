import Foundation
import Testing
@testable import TouchBuddyCore

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("touchbuddy-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func sampleRecord(id: String = "s1") -> SessionRecord {
    SessionRecord(
        sessionID: id, cwd: "/tmp/proj", projectName: "proj",
        state: .working, speechKind: .working, detail: "bun test", toolName: "Bash",
        updatedAt: Date(timeIntervalSince1970: 2_000), startedAt: Date(timeIntervalSince1970: 1_000),
        claudePID: 99, itermSessionID: "w0t1p0:ABCD", entrypoint: "cli"
    )
}

@Test func writeThenLoadRoundTrips() throws {
    let store = SessionStore(directory: try makeTempDirectory())
    let record = sampleRecord()
    try store.write(record)
    #expect(store.load(sessionID: "s1") == record)
    #expect(store.loadAll() == [record])
}

@Test func loadAllSkipsCorruptFile() throws {
    let dir = try makeTempDirectory()
    let store = SessionStore(directory: dir)
    try store.write(sampleRecord())
    try Data("{\"sessio".utf8).write(to: dir.appendingPathComponent("bad.json"))
    #expect(store.loadAll().count == 1)
}

@Test func deleteRemovesFile() throws {
    let store = SessionStore(directory: try makeTempDirectory())
    try store.write(sampleRecord())
    store.delete(sessionID: "s1")
    #expect(store.load(sessionID: "s1") == nil)
    #expect(store.loadAll().isEmpty)
}

@Test func writeCreatesMissingDirectory() throws {
    let dir = try makeTempDirectory().appendingPathComponent("a/b", isDirectory: true)
    let store = SessionStore(directory: dir)
    try store.write(sampleRecord())
    #expect(store.load(sessionID: "s1") != nil)
}

@Test func pathsHonourTouchBuddyHome() {
    let paths = TouchBuddyPaths.resolve(environment: ["TOUCHBUDDY_HOME": "/tmp/x"])
    #expect(paths.sessions.path == "/tmp/x/sessions")
    #expect(paths.characters.path == "/tmp/x/Characters")
}

@Test func pathsDefaultToApplicationSupport() {
    let paths = TouchBuddyPaths.resolve(environment: [:])
    #expect(paths.root.path.hasSuffix("Library/Application Support/TouchBuddy"))
}

@Test func sessionIDIsSanitised() throws {
    let parent = try makeTempDirectory()
    let dir = parent.appendingPathComponent("sessions", isDirectory: true)
    let store = SessionStore(directory: dir)
    try store.write(sampleRecord(id: "../../etc"))
    let escaped = try FileManager.default.contentsOfDirectory(atPath: parent.path)
    #expect(escaped == ["sessions"])
    let inside = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(inside == ["etc.json"])
    #expect(store.load(sessionID: "../../etc") != nil)
}

@Test func emptySanitisedIDThrows() throws {
    let store = SessionStore(directory: try makeTempDirectory())
    #expect(throws: SessionStoreError.self) { try store.write(sampleRecord(id: "../..")) }
}

@Test func isProcessAliveForSelfAndBogusPID() {
    #expect(isProcessAlive(getpid()))
    #expect(!isProcessAlive(Int32.max - 1))
    #expect(!isProcessAlive(0))
    #expect(!isProcessAlive(-1))
}

@Test func ancestorLookupTerminatesAndRejectsUnknownPID() {
    _ = findClaudeAncestorPID(startingAt: getpid())
    #expect(findClaudeAncestorPID(startingAt: Int32.max - 1) == nil)
}

private typealias FakeTable = [Int32: (parentPID: Int32, command: String)]

@Test func ancestorWalkFindsClaudeTwoLevelsUp() {
    let table: FakeTable = [50: (40, "zsh"), 40: (30, "bash"), 30: (20, "claude"), 20: (1, "login")]
    #expect(findClaudeAncestorPID(startingAt: 50) { table[$0] } == 30)
}

@Test func ancestorWalkFindsNode() {
    let table: FakeTable = [50: (40, "zsh"), 40: (30, "node"), 30: (1, "login")]
    #expect(findClaudeAncestorPID(startingAt: 50) { table[$0] } == 40)
}

@Test func ancestorWalkWithNoMatchFallsBackToParentOfStart() {
    let table: FakeTable = [50: (40, "zsh"), 40: (30, "bash"), 30: (1, "launchd")]
    #expect(findClaudeAncestorPID(startingAt: 50) { table[$0] } == 40)
}

@Test func ancestorWalkLookupFailingMidWalkFallsBackToParentOfStart() {
    let table: FakeTable = [50: (40, "zsh"), 40: (30, "bash")]
    #expect(findClaudeAncestorPID(startingAt: 50) { table[$0] } == 40)
}

@Test func ancestorWalkFailingLookupOfStartReturnsNil() {
    let table: FakeTable = [40: (30, "bash")]
    #expect(findClaudeAncestorPID(startingAt: 50) { table[$0] } == nil)
}

@Test func ancestorWalkTerminatesOnCycle() {
    let table: FakeTable = [50: (40, "zsh"), 40: (50, "bash")]
    var lookups = 0
    let result = findClaudeAncestorPID(startingAt: 50) { pid in
        lookups += 1
        return table[pid]
    }
    #expect(result == 40)
    #expect(lookups <= 20)
}

@Test func filesAndDirectoryArePrivate() throws {
    let dir = try makeTempDirectory().appendingPathComponent("sessions", isDirectory: true)
    let store = SessionStore(directory: dir)
    try store.write(sampleRecord())
    let fileAttrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("s1.json").path)
    let dirAttrs = try FileManager.default.attributesOfItem(atPath: dir.path)
    #expect((fileAttrs[.posixPermissions] as? Int) == 0o600)
    #expect((dirAttrs[.posixPermissions] as? Int) == 0o700)

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
    try store.write(sampleRecord())
    let tightened = try FileManager.default.attributesOfItem(atPath: dir.path)
    #expect((tightened[.posixPermissions] as? Int) == 0o700)
}
