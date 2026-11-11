import Foundation
import os

private let characterLogger = Logger(subsystem: "ca.spollock.touchbuddy", category: "characters")

public struct CharacterManifest: Codable, Sendable {
    public var displayName: String
    public var fps: Double?
    public var voice: String?
    public var speech: SpeechTemplates?

    public init(displayName: String, fps: Double? = nil, voice: String? = nil, speech: SpeechTemplates? = nil) {
        self.displayName = displayName
        self.fps = fps
        self.voice = voice
        self.speech = speech
    }
}

extension CharacterManifest: Equatable {}

public enum AnimationSource: Equatable, Sendable {
    case gif(URL)
    case frames([URL])
}

public enum CharacterError: Error, Equatable {
    case missingManifest
    case missingIdle
    case unreadable(String)
}

public struct CharacterDescriptor: Equatable, Sendable {
    public let id: String
    public let manifest: CharacterManifest
    public let animations: [SessionState: AnimationSource]

    public init(id: String, manifest: CharacterManifest, animations: [SessionState: AnimationSource]) {
        self.id = id
        self.manifest = manifest
        self.animations = animations
    }

    public func animation(for state: SessionState) -> AnimationSource {
        guard let source = animations[state] ?? animations[.idle] else {
            preconditionFailure("CharacterDescriptor \(id) has no idle animation")
        }
        return source
    }
}

private func numericFrameOrder(_ lhs: URL, _ rhs: URL) -> Bool {
    let lhsStem = lhs.deletingPathExtension().lastPathComponent
    let rhsStem = rhs.deletingPathExtension().lastPathComponent
    switch (Int(lhsStem), Int(rhsStem)) {
    case let (left?, right?):
        return left == right ? lhsStem < rhsStem : left < right
    case (.some, .none):
        return true
    case (.none, .some):
        return false
    case (.none, .none):
        return lhsStem < rhsStem
    }
}

private func animationSource(for state: SessionState, in dir: URL) -> AnimationSource? {
    let fileManager = FileManager.default
    let gif = dir.appendingPathComponent("\(state.rawValue).gif")
    if fileManager.fileExists(atPath: gif.path) {
        return .gif(gif)
    }

    let folder = dir.appendingPathComponent(state.rawValue, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
          let entries = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    else {
        return nil
    }
    let pngs = entries
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted(by: numericFrameOrder)
    return pngs.isEmpty ? nil : .frames(pngs)
}

public func loadCharacter(at dir: URL, idPrefix: String) throws -> CharacterDescriptor {
    let manifestURL = dir.appendingPathComponent("character.json")
    guard let data = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONDecoder().decode(CharacterManifest.self, from: data)
    else {
        throw CharacterError.missingManifest
    }

    guard let idle = animationSource(for: .idle, in: dir) else {
        throw CharacterError.missingIdle
    }

    var animations: [SessionState: AnimationSource] = [:]
    for state in SessionState.allCases {
        animations[state] = state == .idle ? idle : (animationSource(for: state, in: dir) ?? idle)
    }

    return CharacterDescriptor(
        id: "\(idPrefix)/\(dir.lastPathComponent)",
        manifest: manifest,
        animations: animations
    )
}

private func discover(in root: URL, idPrefix: String) -> [CharacterDescriptor] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var found: [CharacterDescriptor] = []
    for entry in entries {
        guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        do {
            found.append(try loadCharacter(at: entry, idPrefix: idPrefix))
        } catch {
            characterLogger.error("skipping character \(entry.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
    return found.sorted {
        let order = $0.manifest.displayName.localizedCaseInsensitiveCompare($1.manifest.displayName)
        return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
    }
}

public func discoverCharacters(builtInDir: URL, userDir: URL) -> [CharacterDescriptor] {
    discover(in: builtInDir, idPrefix: "builtin") + discover(in: userDir, idPrefix: "user")
}

public func resolveSelectedCharacter(
    id: String?,
    available: [CharacterDescriptor],
    defaultID: String = "builtin/sparky"
) -> CharacterDescriptor? {
    if let id, let selected = available.first(where: { $0.id == id }) {
        return selected
    }
    return available.first(where: { $0.id == defaultID }) ?? available.first
}
