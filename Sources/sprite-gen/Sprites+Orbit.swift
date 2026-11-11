import Foundation
import TouchBuddyCore

private let palette: Palette = [
    "P": 0x5B6BD8, "Q": 0x8795F5, "D": 0x3A3F9E, "Y": 0xFFD23F,
    "G": 0xB88A1E, "W": 0xF4F1E8, "N": 0x151B3A, "S": 0xB8BEC9,
]

private let planetCentre = (x: 12.0, y: 11.0)
private let planetRadius = 6.7

/// Indigo planet (lit top-left) with a tilted gold ring; the back half of the ring hides behind the planet.
private func planet() -> Sprite {
    var sprite = Sprite.blank
    let tilt = -0.22
    let ringCentreY = planetCentre.y + 3.5
    for y in 0..<gridSize {
        for x in 0..<gridSize {
            let dx = Double(x) + 0.5 - planetCentre.x
            let dy = Double(y) + 0.5 - planetCentre.y
            let distance = hypot(dx, dy)
            let onPlanet = distance <= planetRadius
            if onPlanet {
                let diagonal = dx + dy
                let char: Character = diagonal > 4.2 ? "D" : (diagonal < -3.4 && distance > 3.5 ? "Q" : "P")
                sprite = sprite.pixels([(x, y)], char)
            }
            let ringX = Double(x) + 0.5 - 12
            let ringY = Double(y) + 0.5 - ringCentreY
            let u = ringX * cos(tilt) + ringY * sin(tilt)
            let v = -ringX * sin(tilt) + ringY * cos(tilt)
            let e = (u / 10) * (u / 10) + (v / 2.7) * (v / 2.7)
            guard abs(e - 1) < 0.3 else { continue }
            if v >= 0 {
                sprite = sprite.pixels([(x, y)], "Y")
            } else if !onPlanet {
                sprite = sprite.pixels([(x, y)], "G")
            }
        }
    }
    return sprite
}

private let basePlanet = planet()

private enum Eyes {
    case open, blink, happy, wide, focus

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .open:
            return sprite.stamped(["WN", "NN", "NN"], x: 9, y: 8).stamped(["WN", "NN", "NN"], x: 13, y: 8)
        case .blink:
            return sprite.stamped(["NN"], x: 9, y: 10).stamped(["NN"], x: 13, y: 10)
        case .happy:
            return sprite.stamped(["PNP", "NPN"], x: 8, y: 9).stamped(["PNP", "NPN"], x: 13, y: 9)
        case .wide:
            return sprite.stamped(["WN", "NN", "NN", "NN"], x: 9, y: 7).stamped(["WN", "NN", "NN", "NN"], x: 13, y: 7)
        case .focus:
            return sprite.stamped(["NN", "NN"], x: 9, y: 9).stamped(["NN", "NN"], x: 13, y: 9)
                .stamped(["NN"], x: 9, y: 7).stamped(["NN"], x: 13, y: 7)
        }
    }
}

private enum Mouth {
    case smile, grin, round, flat

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .smile: return sprite.stamped(["NPPN", "PNNP"], x: 10, y: 12)
        case .grin: return sprite.stamped(["NNNN", "PNNP"], x: 10, y: 12)
        case .round: return sprite.stamped(["NN", "NN"], x: 11, y: 12)
        case .flat: return sprite.stamped(["NNNN"], x: 10, y: 13)
        }
    }
}

private func moonSprite(_ step: Int) -> (lines: [String], x: Int, y: Int) {
    let angle = Double(step) * Double.pi / 4 - Double.pi / 2
    let x = Int((12 + 10.2 * cos(angle) - 1.5).rounded())
    let y = Int((12 + 9.8 * sin(angle) - 1.5).rounded())
    return (["WWW", "WWS", "WSS"], x, y)
}

private func orbit(
    _ eyes: Eyes, _ mouth: Mouth, moon step: Int, dx: Int = 0, dy: Int = 0
) -> Sprite {
    let body = mouth.stamp(eyes.stamp(basePlanet)).shifted(dx: dx, dy: dy)
    let moon = moonSprite(step)
    return body.stamped(moon.lines, x: moon.x, y: moon.y)
}

func orbitArt() -> CharacterArt {
    let idle: [Sprite] = (0..<16).map { frame in
        let eyes: Eyes = frame == 12 ? .blink : .open
        return orbit(eyes, .smile, moon: frame / 2, dy: (frame / 4) % 2 == 0 ? 0 : 1)
    }

    let working: [Sprite] = (0..<8).map { frame in
        orbit(.focus, .flat, moon: frame * 2, dy: frame % 2)
    }

    let bang = exclamation("W", bar: 6, dot: 2)
    let needsInput: [Sprite] = [
        orbit(.wide, .round, moon: 1, dx: -1).stamped(bang, x: 2, y: 2),
        orbit(.wide, .round, moon: 1, dx: 1, dy: 1).stamped(bang, x: 2, y: 2),
        orbit(.wide, .round, moon: 1, dx: -1).stamped(bang, x: 2, y: 2),
        orbit(.wide, .round, moon: 1, dx: 1, dy: 1).stamped(bang, x: 2, y: 2),
    ]

    let finished: [Sprite] = [
        orbit(.happy, .grin, moon: 0, dy: 1),
        confetti(orbit(.happy, .grin, moon: 2, dy: -2),
                 [(1, 3, "Y"), (22, 4, "Q"), (0, 13, "W"), (22, 11, "Y")]),
        confetti(orbit(.happy, .grin, moon: 4, dy: -3),
                 [(2, 1, "Q"), (21, 1, "Y"), (0, 8, "Y"), (23, 6, "W"), (3, 15, "Q")]),
        confetti(orbit(.happy, .grin, moon: 6, dy: -2),
                 [(3, 4, "W"), (20, 3, "Q"), (0, 15, "Y"), (23, 14, "Y")]),
        confetti(orbit(.happy, .grin, moon: 7), [(1, 10, "Y"), (22, 12, "Q")]),
    ]

    return CharacterArt(
        folder: "orbit",
        displayName: "Orbit",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "{project} reaches for the cosmos: {detail}",
                "The stars ask: may {project} {detail}?",
                "{project} awaits your blessing to {detail}.",
            ],
            .question: [
                "A question drifts from {project}: {detail}",
                "{project} wonders aloud: {detail}",
                "Ponder this, traveller. {project}: {detail}",
            ],
            .working: [
                "{project} orbits onward. Running {tool}.",
                "Worlds turn within {project}...",
                "{project}: {tool} spins through the void.",
            ],
            .finished: [
                "{project} has landed. Wondrous!",
                "A new star is born: {project} is done.",
                "{project}: complete. The universe approves.",
            ],
            .idle: [
                "{project} drifts, calm among the stars.",
                "All is quiet in {project}'s orbit.",
                "{project}: idle. Gazing at the void.",
            ],
            .allClear: [
                "No sessions. Just endless sky.",
                "All clear across the cosmos.",
                "The void is calm. Nothing awaits.",
            ],
        ]
    )
}
