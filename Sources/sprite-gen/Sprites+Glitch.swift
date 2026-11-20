import TouchBuddyCore

private let palette: Palette = [
    "N": 0x2B3340, "C": 0xAEB8C4, "S": 0x7D8896, "B": 0x0B1F17,
    "G": 0x6CFFA8, "R": 0xFF5A5F, "Y": 0xFFD23F, "W": 0xFFFFFF,
]

private let monitorLines = [
    ".NNNNNNNNNNNNNN.",
    "NCCCCCCCCCCCCCCN",
    "NCBBBBBBBBBBBBCN",
    "NCBBBBBBBBBBBBCN",
    "NCBBBBBBBBBBBBCN",
    "NCBBBBBBBBBBBBCN",
    "NCBBBBBBBBBBBBCN",
    "NCBBBBBBBBBBBBCN",
    "NCBBBBBBBBBBBBCN",
    "NCCCCCCCCCCSGCCN",
    ".NNNNNNNNNNNNNN.",
]

private let standLines = ["...NCCN...", "NCCCCCCCCN", "NNNNNNNNNN"]
private let armDown = ["SS", "SS", "SS", "NN"]
private let armUp = ["NN", "SS", "SS", "SS"]

private enum Face {
    case open, blink, happy, bang, bangInverted, code(Int)

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .open:
            return sprite
                .stamped(["GG", "GG"], x: 8, y: 12).stamped(["GG", "GG"], x: 14, y: 12)
                .stamped(["GGGG"], x: 10, y: 15)
        case .blink:
            return sprite
                .stamped(["BB", "GG"], x: 8, y: 12).stamped(["BB", "GG"], x: 14, y: 12)
                .stamped(["GGGG"], x: 10, y: 15)
        case .happy:
            return sprite
                .stamped(["BGGB", "GBBG"], x: 7, y: 12).stamped(["BGGB", "GBBG"], x: 13, y: 12)
                .stamped(["GBBBBG", "BGGGGB"], x: 9, y: 15)
        case .bang:
            return sprite.stamped(exclamation("Y", bar: 4), x: 11, y: 11)
        case .bangInverted:
            let screen = Array(repeating: String(repeating: "Y", count: 12), count: 7)
            return sprite.stamped(screen, x: 6, y: 11).stamped(exclamation("N", bar: 4), x: 11, y: 11)
        case .code(let step):
            let pattern: [(indent: Int, length: Int)] = [(0, 7), (2, 5), (0, 0), (0, 9), (2, 4), (0, 0), (0, 6), (2, 8)]
            return (0..<7).reduce(sprite) { current, row in
                let entry = pattern[(row + 2 * step) % pattern.count]
                guard entry.length > 0 else { return current }
                return current.stamped([String(repeating: "G", count: entry.length)], x: 7 + entry.indent, y: 11 + row)
            }
        }
    }
}

private enum Arms {
    case down, up, left, right
}

private func glitch(face: Face, led: Character = "R", arms: Arms = .down) -> Sprite {
    var sprite = Sprite.blank
        .stamped(monitorLines, x: 4, y: 9)
        .stamped(standLines, x: 7, y: 20)
        .stamped([String(repeating: led, count: 2), String(repeating: led, count: 2), "NN", "NN"], x: 11, y: 5)
    let leftUp = arms == .up || arms == .left
    let rightUp = arms == .up || arms == .right
    sprite = sprite.stamped(leftUp ? armUp : armDown, x: 2, y: leftUp ? 8 : 13)
    sprite = sprite.stamped(rightUp ? armUp : armDown, x: 20, y: rightUp ? 8 : 13)
    return face.stamp(sprite)
}

func glitchArt() -> CharacterArt {
    let idle: [Sprite] = [
        glitch(face: .open),
        glitch(face: .open, led: "S"),
        glitch(face: .open),
        glitch(face: .open, led: "S").shifted(dy: 1),
        glitch(face: .blink),
        glitch(face: .open),
    ]

    let working: [Sprite] = (0..<4).map { step in
        glitch(face: .code(step), led: step % 2 == 0 ? "Y" : "R", arms: step % 2 == 0 ? .left : .right)
    }

    let needsInput: [Sprite] = [
        glitch(face: .bang, led: "Y", arms: .up),
        glitch(face: .bangInverted, led: "R", arms: .down).shifted(dy: -2),
        glitch(face: .bang, led: "Y", arms: .up),
        glitch(face: .bangInverted, led: "R", arms: .down).shifted(dy: -2),
    ]

    let finished: [Sprite] = [
        glitch(face: .happy, led: "Y").shifted(dy: 1),
        confetti(glitch(face: .happy, led: "Y", arms: .up).shifted(dy: -2),
                 [(1, 4, "Y"), (21, 5, "G"), (1, 13, "W"), (22, 12, "Y")]),
        confetti(glitch(face: .happy, led: "W", arms: .up).shifted(dy: -4),
                 [(1, 1, "G"), (22, 2, "Y"), (0, 9, "Y"), (22, 8, "W"), (2, 16, "G")]),
        confetti(glitch(face: .happy, led: "Y", arms: .up).shifted(dy: -2),
                 [(2, 6, "W"), (21, 7, "G"), (0, 15, "Y"), (22, 16, "Y")]),
        confetti(glitch(face: .happy, led: "R"), [(1, 11, "Y"), (22, 13, "G")]),
    ]

    return CharacterArt(
        folder: "glitch",
        displayName: "Glitch",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "{project}: permission needed. {detail}",
                "{project} requests: {detail}. Y/N?",
                "[{project}] approve? {detail}",
            ],
            .question: [
                "{project} asks: {detail}",
                "[{project}] input required: {detail}",
                "{project}: query. {detail}",
            ],
            .working: [
                "{project}: running {tool}.",
                "[{project}] processing...",
                "{project}: busy. Don't poke.",
            ],
            .finished: [
                "{project}: done. Exit 0.",
                "[{project}] complete.",
                "{project} finished. You're welcome.",
            ],
            .idle: [
                "{project}: idle.",
                "[{project}] standing by.",
                "{project}: nothing. Still nothing.",
            ],
            .allClear: [
                "No sessions. Zero. Nada.",
                "All clear. Boring. Good.",
                "Idle. No input required.",
            ],
        ]
    )
}
