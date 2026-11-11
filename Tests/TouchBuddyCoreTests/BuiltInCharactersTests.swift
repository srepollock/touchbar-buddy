import Foundation
import Testing
@testable import TouchBuddyCore

private let allKinds: [SpeechKind] = [.permission, .question, .working, .finished, .idle, .allClear]

private func builtInDir() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Characters", isDirectory: true)
}

private func loadBuiltIns() throws -> [CharacterDescriptor] {
    let userDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("touchbuddy-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: userDir) }
    return discoverCharacters(builtInDir: builtInDir(), userDir: userDir)
}

@Suite("Built-in characters")
struct BuiltInCharactersTests {
    @Test func allBuiltinsLoad() throws {
        let characters = try loadBuiltIns()
        #expect(characters.count == 4)
        let ids = Set(characters.map(\.id))
        #expect(ids == ["builtin/sparky", "builtin/glitch", "builtin/moss", "builtin/nyx"])
    }

    @Test func everyStateHasAtLeast4Frames() throws {
        for character in try loadBuiltIns() {
            let idle = character.animations[.idle]
            for state in SessionState.allCases {
                let source = character.animation(for: state)
                if state != .idle {
                    #expect(source != idle, "\(character.id) \(state.rawValue) fell back to idle")
                }
                let frames = try loadFrames(source, fps: character.manifest.fps ?? 8)
                #expect(frames.count >= 4, "\(character.id) \(state.rawValue)")
                for frame in frames {
                    #expect(frame.image.width == 48 && frame.image.height == 48, "\(character.id) \(state.rawValue)")
                }
            }
        }
    }

    @Test func manifestsUseEightFPS() throws {
        for character in try loadBuiltIns() {
            #expect(character.manifest.fps == 8)
        }
    }

    @Test func everySpeechKindHas3LinesWithProject() throws {
        for character in try loadBuiltIns() {
            let speech = try #require(character.manifest.speech, "\(character.id) has no speech")
            for kind in allKinds {
                let lines = speech.lines[kind] ?? []
                #expect(lines.count >= 3, "\(character.id) \(kind.rawValue)")
                for line in lines {
                    // all_clear renders with no session, so {project} would be empty there.
                    if kind != .allClear {
                        #expect(line.contains("{project}"), "\(character.id) \(kind.rawValue): \(line)")
                    }
                    #expect(line.count <= 60, "\(character.id) \(kind.rawValue) too long: \(line)")
                }
            }
        }
    }

    @Test func permissionAndQuestionLinesIncludeDetail() throws {
        for character in try loadBuiltIns() {
            let speech = try #require(character.manifest.speech)
            for kind in [SpeechKind.permission, .question] {
                for line in speech.lines[kind] ?? [] {
                    #expect(line.contains("{detail}"), "\(character.id) \(kind.rawValue): \(line)")
                }
            }
        }
    }
}
