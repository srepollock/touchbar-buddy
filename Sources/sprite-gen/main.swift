import CoreGraphics
import Foundation
import ImageIO
import TouchBuddyCore
import UniformTypeIdentifiers

// Dev tool: regenerates every built-in character's PNG frames and manifest.
// Usage: sprite-gen <Resources/Characters dir> [--sheet <preview dir>]

private let scale = 2
private let frameFPS = 8.0

private func stderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func fail(_ message: String) -> Never {
    stderr("sprite-gen: \(message)")
    exit(1)
}

private func rgba(of char: Character, palette: Palette) -> [UInt8] {
    if char == "." { return [0, 0, 0, 0] }
    guard let rgb = palette[char] else { fail("palette has no colour for '\(char)'") }
    return [UInt8((rgb >> 16) & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8(rgb & 0xFF), 255]
}

private func makeImage(_ sprite: Sprite, palette: Palette, scale: Int, background: [UInt8]? = nil) -> CGImage {
    let side = gridSize * scale
    var bytes = [UInt8](repeating: 0, count: side * side * 4)
    for (y, row) in sprite.rows.enumerated() {
        for (x, char) in row.enumerated() {
            var pixel = rgba(of: char, palette: palette)
            if pixel[3] == 0, let background { pixel = background }
            for dy in 0..<scale {
                for dx in 0..<scale {
                    let offset = ((y * scale + dy) * side + x * scale + dx) * 4
                    bytes.replaceSubrange(offset..<offset + 4, with: pixel)
                }
            }
        }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(
              width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
          )
    else { fail("could not build image") }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

private func validate(_ art: CharacterArt) {
    for (state, frames) in art.animations {
        if frames.count < 4 { fail("\(art.folder)/\(state.rawValue) has \(frames.count) frames, need >= 4") }
        var used = Set<Character>()
        for frame in frames {
            precondition(frame.rows.count == gridSize && frame.rows.allSatisfy { $0.count == gridSize })
            for row in frame.rows { used.formUnion(row) }
        }
        used.remove(".")
        let missing = used.subtracting(art.palette.keys)
        if !missing.isEmpty { fail("\(art.folder)/\(state.rawValue) uses undefined colours \(missing.sorted())") }
    }
    if art.palette.count > 8 { fail("\(art.folder) palette has \(art.palette.count) colours, max 8") }
}

private func write(_ art: CharacterArt, to root: URL) throws {
    validate(art)
    let fileManager = FileManager.default
    let characterDir = root.appendingPathComponent(art.folder, isDirectory: true)
    try fileManager.createDirectory(at: characterDir, withIntermediateDirectories: true)

    for (state, frames) in art.animations {
        let stateDir = characterDir.appendingPathComponent(state.rawValue, isDirectory: true)
        if fileManager.fileExists(atPath: stateDir.path) { try fileManager.removeItem(at: stateDir) }
        try fileManager.createDirectory(at: stateDir, withIntermediateDirectories: true)
        for (index, frame) in frames.enumerated() {
            writePNG(
                makeImage(frame, palette: art.palette, scale: scale),
                to: stateDir.appendingPathComponent("\(index + 1).png")
            )
        }
    }

    let manifest = CharacterManifest(
        displayName: art.displayName, fps: frameFPS, speech: SpeechTemplates(lines: art.speech)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(manifest)
    data.append(Data("\n".utf8))
    try data.write(to: characterDir.appendingPathComponent("character.json"))
}

/// Contact sheet for eyeballing: one row per state on the Touch Bar's black background.
private func writeSheet(_ art: CharacterArt, to dir: URL) throws {
    let previewScale = 5
    let cell = gridSize * previewScale
    let gap = 6
    let columns = art.animations.map(\.frames.count).max() ?? 0
    let width = columns * (cell + gap) + gap
    let height = art.animations.count * (cell + gap) + gap
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create sheet context") }
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    for (row, animation) in art.animations.enumerated() {
        for (column, frame) in animation.frames.enumerated() {
            let image = makeImage(frame, palette: art.palette, scale: previewScale)
            let originY = height - (row + 1) * (cell + gap)
            context.draw(image, in: CGRect(x: gap + column * (cell + gap), y: originY, width: cell, height: cell))
        }
    }
    guard let sheet = context.makeImage() else { fail("cannot render sheet") }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    writePNG(sheet, to: dir.appendingPathComponent("\(art.folder).png"))
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let outputPath = arguments.first, !outputPath.hasPrefix("--") else {
    fail("usage: sprite-gen <Resources/Characters dir> [--sheet <preview dir>]")
}
let sheetDir: URL? = arguments.firstIndex(of: "--sheet").flatMap { index in
    arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1]) : nil
}

let outputRoot = URL(fileURLWithPath: outputPath, isDirectory: true)
for art in [sparkyArt(), glitchArt(), mossArt(), nyxArt()] {
    do {
        try write(art, to: outputRoot)
        if let sheetDir { try writeSheet(art, to: sheetDir) }
    } catch {
        fail("\(art.folder): \(error)")
    }
}
