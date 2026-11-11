import Foundation
import TouchBuddyCore

private let palette: Palette = [
    "N": 0x2B1A12, "T": 0x3FA796, "L": 0x7FD6C4, "K": 0x6B3E26,
    "S": 0xDDE4EC, "F": 0x7B8794, "P": 0xFF8FA3, "Y": 0xFFD23F,
]

private let bodyLines: [String] =
    [".NNNNNNNNNNNN.", "N" + repeated("K", 12) + "N"]
    + Array(repeating: "NL" + repeated("T", 11) + "N", count: 8)
    + [".N" + repeated("T", 10) + "N.", ".." + repeated("N", 10) + ".."]

private let handleLines = ["TTTT", "..TT", "..TT", "..TT", "..TT", "..TT", "TTTT"]

private enum Eyes {
    case sleepy, open, wide, happy

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .sleepy:
            return sprite.stamped(["NN"], x: 7, y: 16).stamped(["NN"], x: 13, y: 16)
        case .open:
            return sprite.stamped(["NN", "NN"], x: 7, y: 15).stamped(["NN", "NN"], x: 13, y: 15)
        case .wide:
            return sprite.stamped(["NN", "NN", "NN"], x: 7, y: 14).stamped(["NN", "NN", "NN"], x: 13, y: 14)
        case .happy:
            return sprite.stamped(["TNT", "NTN"], x: 7, y: 15).stamped(["TNT", "NTN"], x: 12, y: 15)
        }
    }
}

private enum Mouth {
    case small, yawn, grin, round

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .small: return sprite.stamped(["NN"], x: 10, y: 18)
        case .yawn: return sprite.stamped(["TNNT", "NNNN"], x: 9, y: 18)
        case .grin: return sprite.stamped(["NNNN", "TNNT"], x: 9, y: 18)
        case .round: return sprite.stamped(["NN", "NN"], x: 10, y: 18)
        }
    }
}

private func mug(_ eyes: Eyes, _ mouth: Mouth) -> Sprite {
    let sprite = Sprite.blank
        .stamped(bodyLines, x: 4, y: 10)
        .stamped(handleLines, x: 18, y: 13)
        .pixels([(6, 17), (15, 17)], "P")
    return mouth.stamp(eyes.stamp(sprite))
}

/// Wavy steam strands rising from the rim. `faint` strands are dimmer and shorter.
private func steam(_ sprite: Sprite, phase: Int, strands: [(x: Int, length: Int)]) -> Sprite {
    let wave = [0, 1, 1, 0, -1, -1]
    var result = sprite
    for (index, strand) in strands.enumerated() {
        for step in 0..<strand.length {
            let offset = wave[(step + phase + 2 * index) % wave.count]
            let y = 8 - step
            let char: Character = step >= strand.length - 2 ? "F" : "S"
            result = result.pixels([(strand.x + offset, y)], char)
        }
    }
    return result
}

func mugArt() -> CharacterArt {
    let faint = [(x: 8, length: 3), (x: 13, length: 4)]
    let busy = [(x: 7, length: 7), (x: 11, length: 8), (x: 15, length: 7)]

    let idle: [Sprite] = [
        steam(mug(.sleepy, .small), phase: 0, strands: faint),
        steam(mug(.sleepy, .small), phase: 1, strands: faint),
        steam(mug(.sleepy, .yawn).shifted(dy: 1), phase: 2, strands: faint),
        steam(mug(.sleepy, .yawn).shifted(dy: 1), phase: 3, strands: faint),
        steam(mug(.open, .small), phase: 4, strands: faint),
        steam(mug(.sleepy, .small), phase: 5, strands: faint),
    ]

    let working: [Sprite] = (0..<6).map { step in
        steam(mug(.open, step % 2 == 0 ? .small : .round), phase: step, strands: busy)
            .shifted(dx: step % 2 == 0 ? 0 : 1)
    }

    let bang = exclamation("Y", bar: 4, dot: 2)
    let needsInput: [Sprite] = [
        mug(.wide, .round).shifted(dx: -1).stamped(bang, x: 10, y: 2),
        mug(.wide, .round).shifted(dx: 1, dy: 1).stamped(bang, x: 10, y: 2),
        mug(.wide, .round).shifted(dx: -1).stamped(bang, x: 10, y: 2),
        mug(.wide, .round).shifted(dx: 1, dy: 1).stamped(bang, x: 10, y: 2),
    ]

    let finished: [Sprite] = [
        steam(mug(.happy, .grin), phase: 0, strands: faint).shifted(dy: 1),
        confetti(steam(mug(.happy, .grin), phase: 1, strands: faint).shifted(dy: -2),
                 [(2, 4, "Y"), (21, 5, "L"), (1, 14, "S"), (22, 12, "Y")]),
        confetti(steam(mug(.happy, .grin), phase: 2, strands: faint).shifted(dy: -3),
                 [(1, 1, "L"), (22, 1, "Y"), (0, 8, "Y"), (22, 7, "S"), (2, 16, "L")]),
        confetti(steam(mug(.happy, .grin), phase: 3, strands: faint).shifted(dy: -2),
                 [(3, 5, "S"), (20, 6, "L"), (0, 14, "Y"), (22, 15, "Y")]),
        confetti(steam(mug(.happy, .grin), phase: 4, strands: faint), [(1, 11, "Y"), (22, 13, "L")]),
    ]

    return CharacterArt(
        folder: "mug",
        displayName: "Mug",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "{project} wants to {detail}... yawn... ok?",
                "Pardon me, {project} needs to {detail}.",
                "{project}: {detail}. Need coffee first, though.",
            ],
            .question: [
                "{project} asks: {detail} ...after my coffee?",
                "Mmm... {project} has a question. {detail}",
                "{project}: {detail} Sorry, drowsy.",
            ],
            .working: [
                "{project} is brewing. Running {tool}.",
                "Caffeinated and on it: {project}.",
                "{project}: {tool} percolating. Smells good.",
            ],
            .finished: [
                "{project} is done. Time for a refill.",
                "Fresh pot of results from {project}.",
                "{project}: finished. Cheers!",
            ],
            .idle: [
                "{project} is quiet... zzz... warm.",
                "Nothing brewing in {project}. Cosy.",
                "{project}: idle. Is it nap o'clock?",
            ],
            .allClear: [
                "No sessions. Time for a nap.",
                "All clear. Pass the espresso.",
                "Nothing to brew. Zzz.",
            ],
        ]
    )
}
