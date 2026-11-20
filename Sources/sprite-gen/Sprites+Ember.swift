import Foundation
import TouchBuddyCore

private let palette: Palette = [
    "R": 0xE8412B, "O": 0xFF8A1F, "Y": 0xFFD23F, "W": 0xFFF4C2, "N": 0x3A1410,
]

/// A teardrop flame whose tip leans by `lean` px. Red shell, orange body, yellow belly.
private func flame(height: Int, lean: Double, cx: Double = 12, maxHalf: Double = 7.5) -> Sprite {
    let bottom = 21
    var sprite = Sprite.blank
    for row in 0..<height {
        let t = (Double(row) + 0.5) / Double(height)
        let half = max(0.7, maxHalf * pow(t, 0.6) * sqrt(max(0, 1 - pow(t, 6))))
        let centre = cx + lean * pow(1 - t, 1.5)
        let y = bottom - height + 1 + row
        for x in 0..<gridSize {
            let distance = abs(Double(x) + 0.5 - centre)
            guard distance <= half else { continue }
            let char: Character
            if t > 0.8 && distance <= half - 2 {
                char = "Y"
            } else if t > 0.28 && distance <= half - 1.2 {
                char = "O"
            } else {
                char = "R"
            }
            sprite = sprite.pixels([(x, y)], char)
        }
    }
    return sprite
}

private enum Face {
    case open, blink, happy, focus, angry

    func stamp(_ sprite: Sprite, fx: Int = 12) -> Sprite {
        switch self {
        case .open:
            return sprite.stamped(["NN", "NN"], x: fx - 3, y: 15).stamped(["NN", "NN"], x: fx + 1, y: 15)
                .stamped(["NN"], x: fx - 1, y: 19)
        case .blink:
            return sprite.stamped(["NN"], x: fx - 3, y: 16).stamped(["NN"], x: fx + 1, y: 16)
                .stamped(["NN"], x: fx - 1, y: 19)
        case .happy:
            return sprite.stamped(["ONNO", "NOON"], x: fx - 4, y: 15).stamped(["ONNO", "NOON"], x: fx + 1, y: 15)
                .stamped(["NNNN", "YNNY"], x: fx - 2, y: 19)
        case .focus:
            return sprite.stamped(["NN", "NN"], x: fx - 3, y: 15).stamped(["NN", "NN"], x: fx + 1, y: 15)
                .stamped(["NN"], x: fx - 3, y: 13).stamped(["NN"], x: fx + 1, y: 13)
                .stamped(["NNNN"], x: fx - 2, y: 19)
        case .angry:
            return sprite.stamped(["NN", "NN", "NN"], x: fx - 3, y: 15).stamped(["NN", "NN", "NN"], x: fx + 1, y: 15)
                .line(from: (fx - 4, 12), to: (fx - 2, 14), "N")
                .line(from: (fx + 3, 12), to: (fx + 1, 14), "N")
                .stamped(["NN", "NN"], x: fx - 1, y: 19)
        }
    }
}

func emberArt() -> CharacterArt {
    func ember(_ face: Face, height: Int = 17, lean: Double = 0) -> Sprite {
        face.stamp(flame(height: height, lean: lean))
    }

    let idle: [Sprite] = [
        ember(.open, height: 17, lean: 1),
        ember(.open, height: 16, lean: 0),
        ember(.open, height: 17, lean: -1),
        ember(.open, height: 16, lean: 0),
        ember(.blink, height: 17, lean: 1),
        ember(.open, height: 17, lean: 0),
    ]

    let working: [Sprite] = [
        confetti(ember(.focus, height: 18, lean: 3), [(6, 7, "Y"), (18, 10, "W"), (4, 14, "O")]),
        confetti(ember(.focus, height: 15, lean: -3), [(17, 4, "Y"), (5, 9, "W"), (19, 15, "O")]),
        confetti(ember(.focus, height: 18, lean: 2), [(8, 3, "W"), (19, 7, "Y"), (3, 12, "O")]),
        confetti(ember(.focus, height: 16, lean: -2), [(15, 2, "Y"), (4, 6, "W"), (20, 13, "O")]),
        confetti(ember(.focus, height: 18, lean: 3), [(5, 4, "W"), (18, 6, "Y"), (21, 14, "O")]),
        confetti(ember(.focus, height: 15, lean: -3), [(7, 2, "Y"), (19, 11, "W"), (3, 15, "O")]),
    ]

    func flare(_ lean: Double, bang: Character, height: Int = 20) -> Sprite {
        Face.angry.stamp(flame(height: height, lean: lean, cx: 10), fx: 10)
            .stamped(exclamation(bang, bar: 5, dot: 2), x: 19, y: 2)
    }
    let needsInput: [Sprite] = [
        flare(3, bang: "Y"),
        flare(-3, bang: "W", height: 21),
        flare(3, bang: "Y", height: 21),
        flare(-3, bang: "W"),
    ]

    let finished: [Sprite] = [
        ember(.happy, height: 16).shifted(dy: 1),
        confetti(ember(.happy, height: 18, lean: 2).shifted(dy: -2),
                 [(3, 4, "Y"), (20, 5, "W"), (2, 13, "O"), (21, 11, "Y")]),
        confetti(ember(.happy, height: 19, lean: -2).shifted(dy: -3),
                 [(2, 1, "W"), (21, 2, "Y"), (1, 8, "Y"), (22, 7, "O"), (3, 15, "W")]),
        confetti(ember(.happy, height: 18, lean: 2).shifted(dy: -2),
                 [(4, 6, "O"), (19, 4, "Y"), (1, 15, "Y"), (22, 15, "W")]),
        confetti(ember(.happy, height: 16), [(2, 12, "Y"), (21, 14, "O")]),
    ]

    return CharacterArt(
        folder: "ember",
        displayName: "Ember",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "{project} needs to {detail}. Say yes already!",
                "Hurry up! {project} wants to {detail}.",
                "{project}: {detail}. Approve it, I'm burning here!",
            ],
            .question: [
                "{project} asks: {detail} Answer NOW.",
                "Hey! {project} needs you. {detail}",
                "Waiting on you, {project}: {detail} Come on!",
            ],
            .working: [
                "{project} is on fire! Running {tool}.",
                "Hot hot hot: {project} is cooking.",
                "{project}: {tool} blazing. Don't slow me down!",
            ],
            .finished: [
                "{project} done! Burned right through it.",
                "Finished {project}. Too easy. Next!",
                "{project}: complete. That was a scorcher!",
            ],
            .idle: [
                "{project} is idle. I'm getting restless!",
                "Nothing in {project}. Give me something to burn.",
                "{project}: sitting here smouldering...",
            ],
            .allClear: [
                "No sessions? Boring. Light something up!",
                "All clear. Just embers. Ugh.",
                "Nothing burning. Hurry up and start!",
            ],
        ]
    )
}
