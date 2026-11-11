import Foundation
import Testing
@testable import TouchBuddyCore

private let now = Date(timeIntervalSince1970: 1_000_000)

private func run(_ stdin: String, env: [String: String] = [:], store: SessionStore) -> Int32 {
    runHook(stdin: Data(stdin.utf8), environment: env, store: store, claudePID: 123, now: now)
}

private func fileCount(_ dir: URL) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: dir.path).count) ?? 0
}

@Test func emptyStdinReturnsZeroWritesNothing() throws {
    let dir = try makeTempDirectory()
    #expect(run("", store: SessionStore(directory: dir)) == 0)
    #expect(fileCount(dir) == 0)
}

@Test func garbageStdinReturnsZeroWritesNothing() throws {
    let dir = try makeTempDirectory()
    #expect(run("not json {{{", store: SessionStore(directory: dir)) == 0)
    #expect(fileCount(dir) == 0)
}

@Test func missingSessionIDWritesNothing() throws {
    let dir = try makeTempDirectory()
    #expect(run("{\"hook_event_name\":\"Stop\",\"cwd\":\"/tmp/p\"}", store: SessionStore(directory: dir)) == 0)
    #expect(fileCount(dir) == 0)
}

@Test func unsanitisableSessionIDWritesNothing() throws {
    let dir = try makeTempDirectory()
    let json = "{\"session_id\":\"../..\",\"hook_event_name\":\"Stop\",\"cwd\":\"/tmp/p\"}"
    #expect(run(json, store: SessionStore(directory: dir)) == 0)
    #expect(fileCount(dir) == 0)
}

@Test func validPreToolUseWritesRecord() throws {
    let dir = try makeTempDirectory()
    let store = SessionStore(directory: dir)
    let json = """
    {"session_id":"abc","cwd":"/tmp/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}
    """
    let env = ["ITERM_SESSION_ID": "w0t1p0:ABCD-1234", "CLAUDE_CODE_ENTRYPOINT": "cli"]
    #expect(run(json, env: env, store: store) == 0)
    let record = try #require(store.load(sessionID: "abc"))
    #expect(record.state == .working)
    #expect(record.detail == "ls")
    #expect(record.itermSessionID == "w0t1p0:ABCD-1234")
    #expect(record.entrypoint == "cli")
    #expect(record.claudePID == 123)
    #expect(record.updatedAt == now)
}

@Test func sessionEndDeletesFile() throws {
    let dir = try makeTempDirectory()
    let store = SessionStore(directory: dir)
    try store.write(sampleRecord(id: "abc"))
    #expect(run("{\"session_id\":\"abc\",\"hook_event_name\":\"SessionEnd\"}", store: store) == 0)
    #expect(store.load(sessionID: "abc") == nil)
}

@Test func unknownEventLeavesStoreUntouched() throws {
    let dir = try makeTempDirectory()
    let store = SessionStore(directory: dir)
    #expect(run("{\"session_id\":\"abc\",\"hook_event_name\":\"Whatever\"}", store: store) == 0)
    #expect(fileCount(dir) == 0)
}
