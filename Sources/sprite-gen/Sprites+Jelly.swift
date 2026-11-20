import Foundation
import TouchBuddyCore

private let palette: Palette = [
    "J": 0xB48CF2, "H": 0xE4C9FF, "D": 0x8B63D8, "K": 0xFF9EC4,
    "N": 0x2A1B4F, "W": 0xF4F1E8, "Y": 0xFFD23F,
]

private struct Bell {
    let width: Int
    let height: Int
    let top: Int
}

/// Dome with a darker rim, a scalloped frill and a highlight; centred on x = 12.
private func bellSprite(_ bell: Bell) -> Sprite {
    var sprite = Sprite.blank
    let halfMax = Double(bell.width) / 2
    for row in 0..<bell.height {
        let u = (Double(row) + 0.5) / Double(bell.height)
        let half = max(2.0, halfMax * sqrt(1 - pow(1 - u, 2)))
        let left = Int((12 - half).rounded(.up))
        let right = Int((12 + half).rounded(.down)) - 1
        let y = bell.top + row
        for x in left...right {
            let isEdge = x == left || x == right
            let char: Character
            if row == 0 || isEdge {
                char = "D"
            } else if row == bell.height - 1 {
                char = x % 2 == 0 ? "D" : "J"
            } else {
                char = "J"
            }
            sprite = sprite.pixels([(x, y)], char)
        }
    }
    return sprite
        .pixels([(9, bell.top + 1), (10, bell.top + 1), (8, bell.top + 2)], "H")
}

private func tentacles(
    _ sprite: Sprite, bell: Bell, phase: Double, amplitude: Double, length: Int
) -> Sprite {
    let strands = [8, 10, 12, 14, 16].map { $0 - (bell.width < 15 ? 1 : 0) }
    let spread = Double(bell.width) / 16
    var result = sprite
    for (index, baseX) in strands.enumerated() {
        let anchor = 12 + Int((Double(baseX - 12) * spread).rounded())
        var previousX = anchor
        for step in 0..<length {
            let sway = amplitude * sin(phase + Double(index) * 1.2 + Double(step) * 0.8) * Double(step) / Double(length)
            let x = anchor + Int(sway.rounded())
            let y = bell.top + bell.height + step
            guard y < gridSize else { continue }
            let char: Character = step >= length - 2 ? "K" : "J"
            result = result.pixels([(x, y), (previousX, y)], char)
            previousX = x
        }
    }
    return result
}

private enum Eyes {
    case open, blink, happy, wide

    func stamp(_ sprite: Sprite, bell: Bell) -> Sprite {
        let y = bell.top + bell.height - 6
        switch self {
        case .open:
            return sprite.stamped(["NN", "NN"], x: 9, y: y).stamped(["NN", "NN"], x: 13, y: y)
        case .blink:
            return sprite.stamped(["NN"], x: 9, y: y + 1).stamped(["NN"], x: 13, y: y + 1)
        case .happy:
            return sprite.stamped(["JNJ", "NJN"], x: 8, y: y).stamped(["JNJ", "NJN"], x: 13, y: y)
        case .wide:
            return sprite.stamped(["NN", "NN", "NN"], x: 9, y: y - 2).stamped(["NN", "NN", "NN"], x: 13, y: y - 2)
        }
    }
}

private enum Mouth {
    case small, grin, round

    func stamp(_ sprite: Sprite, bell: Bell) -> Sprite {
        let y = bell.top + bell.height - 3
        switch self {
        case .small: return sprite.stamped(["NN"], x: 11, y: y)
        case .grin: return sprite.stamped(["NNNN"], x: 10, y: y)
        case .round: return sprite.stamped(["NN", "NN"], x: 11, y: y - 1)
        }
    }
}

private func jelly(
    _ eyes: Eyes, _ mouth: Mouth, bell: Bell, phase: Double, amplitude: Double = 1.4, length: Int = 8
) -> Sprite {
    let body = bellSprite(bell)
    let withFace = mouth.stamp(eyes.stamp(body, bell: bell), bell: bell)
        .pixels([(bell.width > 14 ? 7 : 8, bell.top + bell.height - 4), (bell.width > 14 ? 16 : 15, bell.top + bell.height - 4)], "K")
    return tentacles(withFace, bell: bell, phase: phase, amplitude: amplitude, length: length)
}

func jellyArt() -> CharacterArt {
    let relaxed = Bell(width: 16, height: 9, top: 5)
    let rest = Bell(width: 15, height: 10, top: 5)

    let idle: [Sprite] = [
        jelly(.open, .small, bell: relaxed, phase: 0),
        jelly(.open, .small, bell: relaxed, phase: 0.8).shifted(dx: 1),
        jelly(.open, .small, bell: rest, phase: 1.6).shifted(dx: 1, dy: -1),
        jelly(.open, .small, bell: rest, phase: 2.4).shifted(dy: -1),
        jelly(.blink, .small, bell: relaxed, phase: 3.2),
        jelly(.open, .small, bell: relaxed, phase: 4.0).shifted(dx: -1),
    ]

    let squeeze = [
        Bell(width: 18, height: 8, top: 4), Bell(width: 16, height: 9, top: 4),
        Bell(width: 12, height: 11, top: 4), Bell(width: 14, height: 10, top: 4),
    ]
    let working: [Sprite] = (0..<8).map { frame in
        let bell = squeeze[frame % squeeze.count]
        let bubbles: [(Int, Int, Character)] = [
            (3, 21 - (frame * 2) % 18, "W"), (20, 20 - (frame * 2 + 6) % 18, "W"),
        ]
        return confetti(
            jelly(.open, .small, bell: bell, phase: Double(frame) * 1.1, amplitude: 2.2, length: 8), bubbles
        )
    }

    let bang = exclamation("Y", bar: 4, dot: 2)
    let flared = Bell(width: 17, height: 10, top: 8)
    let needsInput: [Sprite] = [
        jelly(.wide, .round, bell: flared, phase: 0, amplitude: 3, length: 5).stamped(bang, x: 11, y: 1),
        jelly(.wide, .round, bell: flared, phase: 2, amplitude: 3, length: 5).shifted(dx: 1, dy: 1).stamped(bang, x: 11, y: 1),
        jelly(.wide, .round, bell: flared, phase: 4, amplitude: 3, length: 5).stamped(bang, x: 11, y: 1),
        jelly(.wide, .round, bell: flared, phase: 6, amplitude: 3, length: 5).shifted(dx: -1, dy: 1).stamped(bang, x: 11, y: 1),
    ]

    let finishBell = Bell(width: 16, height: 9, top: 6)
    let finished: [Sprite] = [
        jelly(.happy, .grin, bell: finishBell, phase: 0),
        confetti(jelly(.happy, .grin, bell: finishBell, phase: 1.5, amplitude: 2).shifted(dy: -3),
                 [(2, 4, "Y"), (21, 5, "H"), (1, 14, "W"), (22, 12, "Y")]),
        confetti(jelly(.happy, .grin, bell: Bell(width: 12, height: 11, top: 6), phase: 3, amplitude: 2).shifted(dy: -5),
                 [(1, 1, "H"), (22, 1, "Y"), (0, 8, "Y"), (22, 7, "W"), (2, 16, "H")]),
        confetti(jelly(.happy, .grin, bell: finishBell, phase: 4.5, amplitude: 2).shifted(dy: -3),
                 [(3, 6, "W"), (20, 7, "H"), (0, 15, "Y"), (22, 16, "Y")]),
        confetti(jelly(.happy, .grin, bell: finishBell, phase: 6), [(1, 12, "Y"), (22, 14, "H")]),
    ]

    return CharacterArt(
        folder: "jelly",
        displayName: "Jelly",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "Softly... {project} wishes to {detail}.",
                "{project} drifts near: may it {detail}?",
                "A gentle ask from {project}: {detail}",
            ],
            .question: [
                "{project} floats a question: {detail}",
                "Whenever you're ready, {project}: {detail}",
                "{project} wonders, softly: {detail}",
            ],
            .working: [
                "{project} pulses along. Running {tool}.",
                "Drifting through {project}... {tool}.",
                "{project}: flowing, flowing. {tool}.",
            ],
            .finished: [
                "{project} has settled. All is well.",
                "Gently done: {project} is finished.",
                "{project}: complete. Breathe out.",
            ],
            .idle: [
                "{project} floats, calm and still.",
                "Nothing stirs in {project}. Peaceful.",
                "{project}: drifting, unhurried.",
            ],
            .allClear: [
                "No sessions. Just calm water.",
                "All clear. Let the tide carry you.",
                "Stillness. Nothing to do.",
            ],
        ]
    )
}
