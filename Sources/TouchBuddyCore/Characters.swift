import Foundation
import ImageIO
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

private func isDirectory(_ url: URL) -> Bool {
    var flag: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
}

private func isReadableImage(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
    return CGImageSourceGetCount(source) > 0
}

private func animationSource(for state: SessionState, in dir: URL) throws -> AnimationSource? {
    let fileManager = FileManager.default
    let gifName = "\(state.rawValue).gif"
    let siblings = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
    if let name = siblings.first(where: { $0.lowercased() == gifName && !isDirectory(dir.appendingPathComponent($0)) }) {
        return .gif(dir.appendingPathComponent(name))
    }

    let folder = dir.appendingPathComponent(state.rawValue, isDirectory: true)
    guard isDirectory(folder),
          let names = try? fileManager.contentsOfDirectory(atPath: folder.path)
    else {
        return nil
    }
    let pngs = names
        .filter { ($0 as NSString).pathExtension.lowercased() == "png" }
        .map { folder.appendingPathComponent($0) }
        .sorted(by: numericFrameOrder)
    return pngs.isEmpty ? nil : .frames(pngs)
}

public func loadCharacter(at dir: URL, idPrefix: String) throws -> CharacterDescriptor {
    let manifestURL = dir.appendingPathComponent("character.json")
    guard let data = try? Data(contentsOf: manifestURL) else {
        throw CharacterError.missingManifest
    }
    let manifest: CharacterManifest
    do {
        manifest = try JSONDecoder().decode(CharacterManifest.self, from: data)
    } catch {
        characterLogger.error("invalid manifest \(manifestURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        throw CharacterError.missingManifest
    }

    guard let idle = try animationSource(for: .idle, in: dir) else {
        throw CharacterError.missingIdle
    }
    let probe: URL
    switch idle {
    case .gif(let url): probe = url
    case .frames(let urls): probe = urls[0]
    }
    guard isReadableImage(probe) else {
        throw CharacterError.unreadable(probe.path)
    }

    var animations: [SessionState: AnimationSource] = [:]
    for state in SessionState.allCases {
        animations[state] = state == .idle ? idle : (try animationSource(for: state, in: dir) ?? idle)
    }

    return CharacterDescriptor(
        id: "\(idPrefix)/\(dir.lastPathComponent)",
        manifest: manifest,
        animations: animations
    )
}

private func discover(in root: URL, idPrefix: String) -> [CharacterDescriptor] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
        return []
    }
    let entries = names.filter { !$0.hasPrefix(".") }.map { root.appendingPathComponent($0, isDirectory: true) }

    var found: [CharacterDescriptor] = []
    for entry in entries {
        guard isDirectory(entry) else { continue }
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
