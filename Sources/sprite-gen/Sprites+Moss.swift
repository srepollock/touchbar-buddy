import TouchBuddyCore

private let palette: Palette = [
    "D": 0x4A3A5C, "P": 0x9B7EBD, "W": 0xFFF4DC, "S": 0xF3E2C0,
    "T": 0xD9C29A, "G": 0x6FBF73, "K": 0x3A2A2A, "C": 0xF28B82,
]

private let capLines = [
    "....DDDDDDDDDD....",
    "..DDPPPPPPPPPPDD..",
    ".DPWWPPPPPPWWPPPD.",
    "DPPWWPPPWWPPWWPPPD",
    "DPPPPPPPWWPPWWPPPD",
    "DDDDDDDDDDDDDDDDDD",
]
private let stemLines =
    Array(repeating: "DSSSSSSSTD", count: 8) + [".DDDDDDDD.", "DD......DD"]

private let leavesV = ["GGG..GGG", ".GGGGGG."]
private let leavesFlat = ["        ", "GGGGGGGG"]
private let leavesLeft = ["GGG     ", ".GGGGGG."]
private let leavesRight = ["     GGG", ".GGGGGG."]

private let gearPlus = ["  W  ", " WWW ", "WW WW", " WWW ", "  W  "]
private let gearCross = ["W   W", " WWW ", " W W ", " WWW ", "W   W"]

private enum Eyes {
    case open, blink, happy

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .open: return sprite.stamped(["KK", "KK"], x: 9, y: 16).stamped(["KK", "KK"], x: 13, y: 16)
        case .blink: return sprite.stamped(["SS", "KK"], x: 9, y: 16).stamped(["SS", "KK"], x: 13, y: 16)
        case .happy: return sprite.stamped(["SKS", "KSK"], x: 8, y: 16).stamped(["SKS", "KSK"], x: 13, y: 16)
        }
    }
}

private enum Mouth {
    case calm, open, grin

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .calm: return sprite.stamped(["KSSK", "SKKS"], x: 10, y: 19)
        case .open: return sprite.stamped(["KK", "KK"], x: 11, y: 19)
        case .grin: return sprite.stamped(["KKKK", "SKKS"], x: 10, y: 19)
        }
    }
}

private func moss(
    leaves: [String] = leavesV, eyes: Eyes = .open, mouth: Mouth = .calm,
    brows: Bool = false, leftArm: Bool? = nil, rightArm: Bool? = nil
) -> Sprite {
    var sprite = Sprite.blank
        .stamped(capLines, x: 3, y: 7)
        .stamped(stemLines, x: 7, y: 13)
        .stamped(["GG", "GG"], x: 11, y: 5)
        .stamped(leaves, x: 8, y: 3)
    // arm == true: raised, false: hanging, nil: none
    if let up = leftArm { sprite = sprite.stamped(up ? ["DD", "SS", "SS"] : ["SS", "SS", "DD"], x: 5, y: up ? 13 : 15) }
    if let up = rightArm { sprite = sprite.stamped(up ? ["DD", "SS", "SS"] : ["SS", "SS", "DD"], x: 17, y: up ? 13 : 15) }
    if brows { sprite = sprite.stamped(["DD"], x: 9, y: 15).stamped(["DD"], x: 13, y: 15) }
    sprite = sprite.stamped(["CC"], x: 8, y: 18).stamped(["CC"], x: 14, y: 18)
    return mouth.stamp(eyes.stamp(sprite))
}

func mossArt() -> CharacterArt {
    let idle: [Sprite] = [
        moss(),
        moss(leaves: leavesLeft),
        moss().shifted(dy: 1),
        moss(leaves: leavesRight).shifted(dy: 1),
        moss(),
        moss(eyes: .blink),
    ]

    let spin = [leavesFlat, leavesLeft, leavesV, leavesRight]
    let working: [Sprite] = (0..<4).map { step in
        moss(leaves: spin[step], mouth: .open, brows: true)
            .stamped(step % 2 == 0 ? gearPlus : gearCross, x: 18, y: 1)
    }

    let needsInput: [Sprite] = (0..<4).map { step in
        let raisedLeft = step % 2 == 0
        let sprite = moss(
            leaves: raisedLeft ? leavesLeft : leavesRight, mouth: .open,
            leftArm: raisedLeft, rightArm: !raisedLeft
        )
        return (step % 2 == 0 ? sprite : sprite.shifted(dy: -2)).stamped(exclamation("C"), x: 21, y: 0)
    }

    let finished: [Sprite] = [
        moss(eyes: .happy, mouth: .grin).shifted(dy: 1),
        confetti(moss(leaves: leavesFlat, eyes: .happy, mouth: .grin, leftArm: true, rightArm: true).shifted(dy: -2),
                 [(1, 6, "C"), (22, 7, "G"), (1, 14, "W"), (22, 15, "P")]),
        confetti(moss(leaves: leavesFlat, eyes: .happy, mouth: .grin, leftArm: true, rightArm: true).shifted(dy: -3),
                 [(1, 2, "G"), (22, 1, "C"), (0, 9, "P"), (23, 10, "W"), (2, 17, "C")]),
        confetti(moss(leaves: leavesV, eyes: .happy, mouth: .grin, leftArm: true, rightArm: true).shifted(dy: -2),
                 [(2, 9, "W"), (21, 5, "P"), (1, 17, "G"), (22, 18, "C")]),
        confetti(moss(eyes: .happy), [(1, 12, "C"), (22, 14, "G")]),
    ]

    return CharacterArt(
        folder: "moss",
        displayName: "Moss",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "{project} would like your okay: {detail} 🍄",
                "A small request from {project}: {detail}",
                "When you have a moment: {detail} ({project})",
            ],
            .question: [
                "{project} wonders: {detail} 🌱",
                "A gentle question from {project}: {detail}",
                "Whenever you're ready, {project}: {detail}",
            ],
            .working: [
                "{project} is growing along nicely 🌱",
                "Slow and steady in {project}...",
                "{project}: tending to {tool} 🍄",
            ],
            .finished: [
                "{project} is all done. Lovely work 🍄",
                "All tucked in: {project} finished.",
                "{project} bloomed! Time for tea ☕",
            ],
            .idle: [
                "{project} is resting quietly 🍄",
                "Cosy and calm in {project}.",
                "{project}: nothing to do. Breathe in...",
            ],
            .allClear: [
                "All is calm. Nothing needs you 🌿",
                "No sessions. Time for tea ☕",
                "Peaceful. Enjoy the quiet.",
            ],
        ]
    )
}
