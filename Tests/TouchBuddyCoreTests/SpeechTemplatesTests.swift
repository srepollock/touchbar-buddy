import Foundation
import Testing
@testable import TouchBuddyCore

private func makeSession(
    kind: SpeechKind = .permission,
    project: String = "touchbar-app",
    detail: String? = "bun test",
    tool: String? = "Bash"
) -> SessionRecord {
    SessionRecord(
        sessionID: "s1",
        cwd: "/tmp/\(project)",
        projectName: project,
        state: .needsInput,
        speechKind: kind,
        detail: detail,
        toolName: tool,
        updatedAt: Date(timeIntervalSince1970: 0),
        startedAt: Date(timeIntervalSince1970: 0)
    )
}

private let t0 = Date(timeIntervalSince1970: 0)
private let pickFirst: @Sendable ([String]) -> String? = { $0.first }

@Test func rendersPlaceholders() {
    let out = renderTemplate(
        "Psst — {project} wants to run {detail}.",
        values: ["project": "touchbar-app", "detail": "bun test"]
    )
    #expect(out == "Psst — touchbar-app wants to run bun test.")
}

@Test func missingValueCollapsesWhitespace() {
    #expect(renderTemplate("{project} wants to run {detail} now", values: ["project": "app"]) == "app wants to run now")
    #expect(renderTemplate("wants to run {detail}.", values: [:]) == "wants to run.")
    #expect(renderTemplate("  {tool}  hi  {unknown} there ", values: [:]) == "hi there")
}

@Test func nilSessionUsesAllClear() {
    let templates = SpeechTemplates(lines: [.allClear: ["Nothing needs you 🎉"]])
    let line = speechLine(for: nil, templates: templates, fallback: SpeechTemplates(lines: [:]), now: t0, pick: pickFirst)
    #expect(line == "Nothing needs you 🎉")
}

@Test func nilSessionWithNoAllClearAnywhereIsFactual() {
    let empty = SpeechTemplates(lines: [:])
    #expect(speechLine(for: nil, templates: empty, fallback: empty, now: t0, pick: pickFirst) == "All clear")
}

@Test func usesTemplatesForSessionKind() {
    let templates = SpeechTemplates(lines: [.permission: ["Psst — {project} wants to run {detail}. Your call 👀"]])
    let line = speechLine(for: makeSession(), templates: templates, fallback: SpeechTemplates(lines: [:]), now: t0, pick: pickFirst)
    #expect(line == "Psst — touchbar-app wants to run bun test. Your call 👀")
}

@Test func missingKindFallsBack() {
    let templates = SpeechTemplates(lines: [.permission: []])
    let fallback = SpeechTemplates(lines: [.permission: ["Fallback {project}"]])
    let line = speechLine(for: makeSession(), templates: templates, fallback: fallback, now: t0, pick: pickFirst)
    #expect(line == "Fallback touchbar-app")
}

@Test func emptyEverywhereUsesFactualDefault() {
    let empty = SpeechTemplates(lines: [:])
    #expect(speechLine(for: makeSession(), templates: empty, fallback: empty, now: t0, pick: pickFirst) == "touchbar-app: bun test")
    #expect(speechLine(for: makeSession(detail: nil), templates: empty, fallback: empty, now: t0, pick: pickFirst) == "touchbar-app")
    #expect(speechLine(for: makeSession(detail: ""), templates: empty, fallback: empty, now: t0, pick: pickFirst) == "touchbar-app")
}

@Test func decodesFromJSONKeys() throws {
    let json = #"{"permission": ["a"], "all_clear": ["b"], "bogus": ["c"]}"#
    let decoded = try JSONDecoder().decode(SpeechTemplates.self, from: Data(json.utf8))
    #expect(decoded.lines[.allClear] == ["b"])
    #expect(decoded.lines[.permission] == ["a"])
    #expect(decoded.lines.count == 2)
}

@Test func encodesAsKeyedObject() throws {
    let templates = SpeechTemplates(lines: [.allClear: ["x"]])
    let data = try JSONEncoder().encode(templates)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: [String]]
    #expect(object == ["all_clear": ["x"]])
    #expect(try JSONDecoder().decode(SpeechTemplates.self, from: data) == templates)
}

@Test func valuesAreNeverRescanned() {
    let t = "{project}|{detail}"
    #expect(renderTemplate(t, values: ["project": "p", "detail": "{project}"]) == "p|{project}")
    #expect(renderTemplate(t, values: ["project": "{detail}", "detail": "d"]) == "{detail}|d")
    #expect(renderTemplate("run {detail}", values: ["detail": "awk '{print}'"]) == "run awk '{print}'")
    #expect(renderTemplate("run {detail}", values: ["detail": "echo ${HOME}"]) == "run echo ${HOME}")
}

@Test func valuesKeepPunctuationAndWhitespace() {
    #expect(renderTemplate("run {detail}!", values: ["detail": "cd ."]) == "run cd .!")
    #expect(renderTemplate("run {detail}.", values: ["detail": "a  b"]) == "run a  b.")
}

@Test func emptyPlaceholderBeforePunctuationDropsSpace() {
    #expect(renderTemplate("wants to run {detail}!", values: [:]) == "wants to run!")
    #expect(renderTemplate("a {tool}, b", values: [:]) == "a, b")
}

@Test func decayedFinishedUsesIdleLines() {
    let templates = SpeechTemplates(lines: [.finished: ["done"], .idle: ["napping"]])
    let none = SpeechTemplates(lines: [:])
    var session = makeSession(kind: .finished)
    session.state = .finished
    let fresh = speechLine(for: session, templates: templates, fallback: none, now: Date(timeIntervalSince1970: 10), pick: pickFirst)
    #expect(fresh == "done")
    let later = Date(timeIntervalSince1970: finishedDecaySeconds + 1)
    #expect(speechLine(for: session, templates: templates, fallback: none, now: later, pick: pickFirst) == "napping")
}
