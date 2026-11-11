import Foundation
import TouchBuddyCore

let gridSize = 24

/// A 24x24 grid of palette characters. "." is transparent.
struct Sprite {
    private(set) var rows: [[Character]]

    static let blank = Sprite(rows: Array(repeating: Array(repeating: ".", count: gridSize), count: gridSize))

    /// Stamps `lines` with their top-left at (x, y). A space leaves the cell untouched, "." clears it.
    func stamped(_ lines: [String], x: Int, y: Int) -> Sprite {
        var copy = self
        for (dy, line) in lines.enumerated() {
            for (dx, char) in line.enumerated() where char != " " {
                let px = x + dx
                let py = y + dy
                precondition(px >= 0 && px < gridSize && py >= 0 && py < gridSize, "stamp out of bounds at (\(px),\(py))")
                copy.rows[py][px] = char
            }
        }
        return copy
    }

    func pixels(_ points: [(Int, Int)], _ char: Character) -> Sprite {
        var copy = self
        for (px, py) in points {
            precondition(px >= 0 && px < gridSize && py >= 0 && py < gridSize, "pixel out of bounds at (\(px),\(py))")
            copy.rows[py][px] = char
        }
        return copy
    }

    func line(from start: (Int, Int), to end: (Int, Int), _ char: Character) -> Sprite {
        var points: [(Int, Int)] = []
        var (x, y) = start
        let dx = abs(end.0 - x)
        let dy = -abs(end.1 - y)
        let stepX = x < end.0 ? 1 : -1
        let stepY = y < end.1 ? 1 : -1
        var error = dx + dy
        while true {
            points.append((x, y))
            if x == end.0 && y == end.1 { break }
            let doubled = 2 * error
            if doubled >= dy { error += dy; x += stepX }
            if doubled <= dx { error += dx; y += stepY }
        }
        return pixels(points, char)
    }

    /// Moves the whole sprite. Pixels pushed off the grid are a bug in the art, so fail loudly.
    func shifted(dx: Int = 0, dy: Int = 0) -> Sprite {
        var result = Sprite.blank
        for (y, row) in rows.enumerated() {
            for (x, char) in row.enumerated() where char != "." {
                let nx = x + dx
                let ny = y + dy
                precondition(nx >= 0 && nx < gridSize && ny >= 0 && ny < gridSize, "shift clipped pixel \(char) at (\(x),\(y)) by (\(dx),\(dy))")
                result.rows[ny][nx] = char
            }
        }
        return result
    }

    var lines: [String] { rows.map { String($0) } }
}

func mirrored(_ lines: [String]) -> [String] {
    lines.map { String($0.reversed()) }
}

typealias Palette = [Character: UInt32]

struct CharacterArt {
    let folder: String
    let displayName: String
    let palette: Palette
    let animations: [(state: SessionState, frames: [Sprite])]
    let speech: [SpeechKind: [String]]
}

/// A "!" glyph, `bar` rows tall plus a gap row and a `dot` rows tall dot, 2 px wide.
func exclamation(_ char: Character, bar: Int = 5, dot: Int = 2) -> [String] {
    let stroke = String(repeating: char, count: 2)
    return Array(repeating: stroke, count: bar) + ["  "] + Array(repeating: stroke, count: dot)
}

/// Scatters single-pixel confetti: each point is (x, y, palette char).
func confetti(_ sprite: Sprite, _ points: [(Int, Int, Character)]) -> Sprite {
    points.reduce(sprite) { $0.pixels([($1.0, $1.1)], $1.2) }
}

func repeated(_ char: Character, _ count: Int) -> String {
    String(repeating: char, count: count)
}

enum ArmPose {
    case down, up, left, right
}

/// Stamps two 2 px wide arms: `fill` limbs with a dark "N" hand at the bottom (down) or top (up).
func withArms(
    _ sprite: Sprite, _ pose: ArmPose, fill: Character, leftX: Int, rightX: Int, downY: Int, upY: Int
) -> Sprite {
    let pair = String(repeating: fill, count: 2)
    let down = [pair, pair, pair, "NN"]
    let up = ["NN", pair, pair, pair]
    let leftUp = pose == .up || pose == .left
    let rightUp = pose == .up || pose == .right
    return sprite
        .stamped(leftUp ? up : down, x: leftX, y: leftUp ? upY : downY)
        .stamped(rightUp ? up : down, x: rightX, y: rightUp ? upY : downY)
}
