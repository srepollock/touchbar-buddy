import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TouchBuddyCore

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("touchbuddy-characters-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeImage(gray: UInt8 = 128, width: Int = 2, height: Int = 2) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: CGFloat(gray) / 255, green: 0.2, blue: 0.4, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func writePNG(to url: URL, width: Int = 2, height: Int = 2) throws {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, makeImage(width: width, height: height), nil)
    #expect(CGImageDestinationFinalize(destination))
}

private func writeGIF(
    to url: URL, frames: Int = 2, delay: Double = 0.1,
    delayKey: CFString = kCGImagePropertyGIFDelayTime, size: Int = 2
) throws {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil)!
    let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
    CGImageDestinationSetProperties(destination, fileProps)
    for index in 0..<frames {
        let frameProps = [kCGImagePropertyGIFDictionary: [delayKey: delay]] as CFDictionary
        CGImageDestinationAddImage(destination, makeImage(gray: UInt8(40 + (index % 2) * 100), width: size, height: size), frameProps)
    }
    #expect(CGImageDestinationFinalize(destination))
}

private func writeManifest(_ name: String, to dir: URL) throws {
    let json = #"{"displayName": "\#(name)", "fps": 6, "voice": "Samantha"}"#
    try Data(json.utf8).write(to: dir.appendingPathComponent("character.json"))
}

private func makeCharacter(
    in parent: URL, folder: String, name: String, withIdle: Bool = true, withManifest: Bool = true
) throws -> URL {
    let dir = parent.appendingPathComponent(folder, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if withManifest { try writeManifest(name, to: dir) }
    if withIdle { try writeGIF(to: dir.appendingPathComponent("idle.gif")) }
    return dir
}

private func descriptor(id: String, name: String) -> CharacterDescriptor {
    let source = AnimationSource.gif(URL(fileURLWithPath: "/tmp/\(name).gif"))
    return CharacterDescriptor(
        id: id,
        manifest: CharacterManifest(displayName: name, fps: nil, voice: nil, speech: nil),
        animations: [.idle: source]
    )
}

@Suite struct CharactersTests {
    @Test func loadsPNGFolderCharacter() throws {
        let root = try makeTempDir()
        let dir = try makeCharacter(in: root, folder: "robo", name: "Robo", withIdle: false)
        let working = dir.appendingPathComponent("working", isDirectory: true)
        let idle = dir.appendingPathComponent("idle", isDirectory: true)
        for folder in [working, idle] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writePNG(to: folder.appendingPathComponent("1.png"))
            try writePNG(to: folder.appendingPathComponent("2.png"))
        }

        let character = try loadCharacter(at: dir, idPrefix: "user")

        #expect(character.id == "user/robo")
        #expect(character.manifest.displayName == "Robo")
        #expect(character.manifest.fps == 6)
        #expect(character.manifest.voice == "Samantha")
        guard case .frames(let urls) = character.animation(for: .working) else {
            Issue.record("expected frames")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["1.png", "2.png"])
    }

    @Test func loadsGIFCharacter() throws {
        let root = try makeTempDir()
        let dir = try makeCharacter(in: root, folder: "sparky", name: "Sparky")
        try writeGIF(to: dir.appendingPathComponent("finished.gif"))

        let character = try loadCharacter(at: dir, idPrefix: "builtin")

        #expect(character.id == "builtin/sparky")
        #expect(character.animation(for: .finished) == .gif(dir.appendingPathComponent("finished.gif")))
    }

    @Test func missingStatesFallBackToIdle() throws {
        let root = try makeTempDir()
        let dir = try makeCharacter(in: root, folder: "sparky", name: "Sparky")

        let character = try loadCharacter(at: dir, idPrefix: "builtin")

        let idle = AnimationSource.gif(dir.appendingPathComponent("idle.gif"))
        for state in SessionState.allCases {
            #expect(character.animations[state] == idle)
            #expect(character.animation(for: state) == idle)
        }
    }

    @Test func missingIdleThrows() throws {
        let root = try makeTempDir()
        let dir = try makeCharacter(in: root, folder: "noidle", name: "No Idle", withIdle: false)
        try writeGIF(to: dir.appendingPathComponent("working.gif"))

        #expect(throws: CharacterError.missingIdle) {
            try loadCharacter(at: dir, idPrefix: "user")
        }
    }

    @Test func missingManifestThrows() throws {
        let root = try makeTempDir()
        let dir = try makeCharacter(in: root, folder: "nomanifest", name: "x", withManifest: false)

        #expect(throws: CharacterError.missingManifest) {
            try loadCharacter(at: dir, idPrefix: "user")
        }
    }

    @Test func discoverSkipsBrokenAndOrdersBuiltinsFirst() throws {
        let builtIn = try makeTempDir()
        let user = try makeTempDir()
        _ = try makeCharacter(in: builtIn, folder: "sparky", name: "Sparky")
        _ = try makeCharacter(in: builtIn, folder: "alpha", name: "Alpha")
        _ = try makeCharacter(in: user, folder: "zed", name: "Zed")
        _ = try makeCharacter(in: user, folder: "bob", name: "Bob")
        _ = try makeCharacter(in: user, folder: "noidle", name: "No Idle", withIdle: false)
        _ = try makeCharacter(in: user, folder: "nomanifest", name: "x", withManifest: false)
        let badManifest = try makeCharacter(in: user, folder: "badjson", name: "x")
        try Data("not json".utf8).write(to: badManifest.appendingPathComponent("character.json"))

        let found = discoverCharacters(builtInDir: builtIn, userDir: user)

        #expect(found.map(\.id) == ["builtin/alpha", "builtin/sparky", "user/bob", "user/zed"])
    }

    @Test func discoverTreatsMissingDirectoriesAsEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        #expect(discoverCharacters(builtInDir: missing, userDir: missing).isEmpty)
    }

    @Test func resolveReturnsSelectedWhenAvailable() {
        let available = [descriptor(id: "builtin/sparky", name: "Sparky"), descriptor(id: "user/bob", name: "Bob")]
        #expect(resolveSelectedCharacter(id: "user/bob", available: available)?.id == "user/bob")
    }

    @Test func resolveFallsBackToDefaultWhenSelectedDeleted() {
        let available = [descriptor(id: "user/bob", name: "Bob"), descriptor(id: "builtin/sparky", name: "Sparky")]
        #expect(resolveSelectedCharacter(id: "user/gone", available: available)?.id == "builtin/sparky")
        #expect(resolveSelectedCharacter(id: nil, available: available)?.id == "builtin/sparky")
    }

    @Test func resolveUsesFirstWhenDefaultMissing() {
        let available = [descriptor(id: "user/bob", name: "Bob"), descriptor(id: "user/zed", name: "Zed")]
        #expect(resolveSelectedCharacter(id: "user/gone", available: available)?.id == "user/bob")
        #expect(resolveSelectedCharacter(id: nil, available: []) == nil)
    }

    @Test func gifFramesDecodeWithDelays() throws {
        let root = try makeTempDir()
        let url = root.appendingPathComponent("anim.gif")
        try writeGIF(to: url, frames: 2, delay: 0.1)

        let frames = try loadFrames(.gif(url), fps: 8)

        #expect(frames.count == 2)
        for frame in frames {
            #expect(abs(frame.duration - 0.1) < 0.001)
            #expect(frame.image.width == 2)
        }
    }

    @Test func pngFramesSortedNumerically() throws {
        let root = try makeTempDir()
        let dir = try makeCharacter(in: root, folder: "c", name: "C", withIdle: false)
        let idle = dir.appendingPathComponent("idle", isDirectory: true)
        try FileManager.default.createDirectory(at: idle, withIntermediateDirectories: true)
        for name in ["10.png", "2.png", "1.png", "b.png", "a.png"] {
            try writePNG(to: idle.appendingPathComponent(name))
        }
        try Data("x".utf8).write(to: idle.appendingPathComponent("notes.txt"))

        let character = try loadCharacter(at: dir, idPrefix: "user")

        guard case .frames(let urls) = character.animation(for: .idle) else {
            Issue.record("expected frames")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["1.png", "2.png", "10.png", "a.png", "b.png"])

        let frames = try loadFrames(.frames(urls), fps: 4)
        #expect(frames.count == 5)
        #expect(frames.allSatisfy { abs($0.duration - 0.25) < 0.0001 })
    }

    @Test func gifDelayClampsToMinimum() throws {
        let root = try makeTempDir()
        let url = root.appendingPathComponent("fast.gif")
        try writeGIF(to: url, frames: 2, delay: 0.001, delayKey: kCGImagePropertyGIFUnclampedDelayTime)

        let frames = try loadFrames(.gif(url), fps: 8)

        #expect(frames.allSatisfy { $0.duration == 0.02 })
    }

    @Test func gifDelayTimeOnlyFallback() throws {
        let root = try makeTempDir()
        let url = root.appendingPathComponent("slow.gif")
        try writeGIF(to: url, frames: 2, delay: 0.3, delayKey: kCGImagePropertyGIFDelayTime)

        let frames = try loadFrames(.gif(url), fps: 8)

        #expect(frames.allSatisfy { abs($0.duration - 0.3) < 0.001 })
    }

    @Test func pngDurationHandlesDegenerateFPS() throws {
        let root = try makeTempDir()
        let url = root.appendingPathComponent("1.png")
        try writePNG(to: url)

        #expect(try loadFrames(.frames([url]), fps: 0)[0].duration == 0.125)
        #expect(try loadFrames(.frames([url]), fps: .nan)[0].duration == 0.125)
        #expect(try loadFrames(.frames([url]), fps: .infinity)[0].duration == 0.125)
        #expect(try loadFrames(.frames([url]), fps: 1e308)[0].duration == 0.02)
    }

    @Test func tooManyFramesThrows() throws {
        let root = try makeTempDir()
        let url = root.appendingPathComponent("long.gif")
        try writeGIF(to: url, frames: 501, delay: 0.1, size: 1)

        #expect(throws: CharacterError.unreadable(url.path)) {
            try loadFrames(.gif(url), fps: 8)
        }
    }

    @Test func oversizedDimensionThrows() throws {
        let root = try makeTempDir()
        let url = root.appendingPathComponent("wide.png")
        try writePNG(to: url, width: 4097, height: 1)

        #expect(throws: CharacterError.unreadable(url.path)) {
            try loadFrames(.frames([url]), fps: 8)
        }
    }

    @Test func largeFramesAreDownsampledAndSmallOnesKeepSize() throws {
        let root = try makeTempDir()
        let big = root.appendingPathComponent("big.png")
        let small = root.appendingPathComponent("small.png")
        try writePNG(to: big, width: 512, height: 512)
        try writePNG(to: small, width: 48, height: 48)

        let frames = try loadFrames(.frames([big, small]), fps: 8)

        #expect(frames[0].image.width <= 256 && frames[0].image.height <= 256)
        #expect(frames[1].image.width == 48 && frames[1].image.height == 48)
    }

    @Test func discoverFollowsSymlinkedFolders() throws {
        let builtIn = try makeTempDir()
        let user = try makeTempDir()
        let elsewhere = try makeTempDir()
        let real = try makeCharacter(in: elsewhere, folder: "real", name: "Linked")
        try FileManager.default.createSymbolicLink(
            at: user.appendingPathComponent("linked"), withDestinationURL: real
        )

        let found = discoverCharacters(builtInDir: builtIn, userDir: user)

        #expect(found.map(\.id) == ["user/linked"])
    }

    @Test func discoverSkipsCorruptIdle() throws {
        let builtIn = try makeTempDir()
        let user = try makeTempDir()
        let dir = try makeCharacter(in: user, folder: "corrupt", name: "Corrupt", withIdle: false)
        try Data((0..<256).map { _ in UInt8.random(in: 0...255) }).write(to: dir.appendingPathComponent("idle.gif"))
        _ = try makeCharacter(in: user, folder: "fine", name: "Fine")

        let found = discoverCharacters(builtInDir: builtIn, userDir: user)

        #expect(found.map(\.id) == ["user/fine"])
    }

    @Test func idleGifDirectoryIsNotTreatedAsGIF() throws {
        let root = try makeTempDir()
        let dir = try makeCharacter(in: root, folder: "odd", name: "Odd", withIdle: false)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("idle.gif", isDirectory: true), withIntermediateDirectories: true
        )

        #expect(throws: CharacterError.missingIdle) {
            try loadCharacter(at: dir, idPrefix: "user")
        }
    }

    @Test func uppercaseGifExtensionIsAccepted() throws {
        let root = try makeTempDir()
        let dir = try makeCharacter(in: root, folder: "caps", name: "Caps", withIdle: false)
        try writeGIF(to: dir.appendingPathComponent("idle.GIF"))

        let character = try loadCharacter(at: dir, idPrefix: "user")

        #expect(character.animation(for: .idle) == .gif(dir.appendingPathComponent("idle.GIF")))
    }

    @Test func corruptGIFThrowsUnreadable() throws {
        let root = try makeTempDir()
        let url = root.appendingPathComponent("bad.gif")
        try Data((0..<256).map { _ in UInt8.random(in: 0...255) }).write(to: url)

        #expect(throws: CharacterError.unreadable(url.path)) {
            try loadFrames(.gif(url), fps: 8)
        }
    }
}
