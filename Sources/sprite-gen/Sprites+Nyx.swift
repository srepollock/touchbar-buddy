import TouchBuddyCore

private let palette: Palette = [
    "N": 0x1E1B3A, "B": 0x4B4690, "W": 0x9C93F0, "V": 0xD8D3FF,
    "Y": 0xFFD23F, "F": 0xFF9F43, "L": 0xC9A66B, "R": 0xFF5A5F,
]

private enum Wings {
    case up, mid, down

    // Left wing, 8 wide, x 1...8. The right wing is its mirror image.
    private static let midLines = [
        "......NN", "....NNWW", "..NNWWWW", ".NWWVVWW", "NWWVVWWW",
        "NWWWWWWW", "NWWWWWWW", ".NWWWWWW", "..NNWWWW", "....NNNN",
    ]
    private static let upLines = [
        "NN......", "NWN.....", "NWWNN...", ".NWWWNN.", ".NWVVWWN", "..NWVVWN",
        "..NWWWWN", "...NWWWN", "...NWWWN", "....NWWN", "....NNNN",
    ]

    func stamp(_ sprite: Sprite) -> Sprite {
        let (lines, y): ([String], Int)
        switch self {
        case .mid: (lines, y) = (Wings.midLines, 8)
        case .up: (lines, y) = (Wings.upLines, 3)
        case .down: (lines, y) = (Wings.midLines, 11)
        }
        return sprite.stamped(lines, x: 1, y: y).stamped(mirrored(lines), x: 15, y: y)
    }
}

private let headLines = [
    "..NNNN..", ".NBBBBN.", "NBBBBBBN", "NBBBBBBN", ".NBBBBN.",
]
private let thoraxLines = ["NBBBBN", "NBVVBN", "NBBBBN", ".NBBN.", ".NBBN.", "..NN.."]

private enum Eyes {
    case open, blink, joy, wide

    func stamp(_ sprite: Sprite) -> Sprite {
        let lines: [String]
        switch self {
        case .open: lines = ["YY", "YY"]
        case .blink: lines = ["BB", "YY"]
        case .joy: lines = ["YY", "BB"]
        case .wide: lines = ["WY", "YY"]
        }
        return sprite.stamped(lines, x: 9, y: 10).stamped(lines, x: 13, y: 10)
    }
}

private func lantern(_ sprite: Sprite, handle: (x: Int, y: Int), flame: Character = "F") -> Sprite {
    sprite
        .line(from: (14, 14), to: handle, "N")
        .stamped(["L"], x: handle.x, y: handle.y)
        .stamped([".LLL.", "LYYYL", "L\(flame)\(flame)\(flame)L", "LYYYL", ".LLL."], x: handle.x - 2, y: handle.y + 1)
}

private func glow(_ sprite: Sprite, handle: (x: Int, y: Int)) -> Sprite {
    let cy = handle.y + 3
    return sprite.pixels(
        [(handle.x - 4, cy), (handle.x + 3, cy), (handle.x - 3, cy - 3), (handle.x + 3, cy - 3),
         (handle.x - 3, cy + 3), (handle.x + 3, cy + 3), (handle.x, handle.y - 2)],
        "Y"
    )
}

private func nyx(
    wings: Wings, eyes: Eyes = .open, handle: (x: Int, y: Int) = (19, 14), flame: Character = "F"
) -> Sprite {
    var sprite = wings.stamp(Sprite.blank)
        .stamped(thoraxLines, x: 9, y: 13)
        .stamped(headLines, x: 8, y: 8)
        .pixels([(8, 7), (7, 6), (6, 5), (5, 4), (7, 5), (15, 7), (16, 6), (17, 5), (18, 4), (16, 5)], "N")
        .pixels([(10, 19), (13, 19)], "N")
    sprite = eyes.stamp(sprite)
    return lantern(sprite, handle: handle, flame: flame)
}

func nyxArt() -> CharacterArt {
    let idle: [Sprite] = [
        nyx(wings: .mid),
        nyx(wings: .up, flame: "V"),
        nyx(wings: .mid),
        nyx(wings: .down, flame: "V"),
        nyx(wings: .mid),
        nyx(wings: .mid, eyes: .blink),
    ]

    let swing = [17, 19, 21, 19]
    let working: [Sprite] = (0..<4).map { step in
        let dots = [1, 2, 3, 0][step]
        let sprite = nyx(wings: step % 2 == 0 ? .up : .mid, handle: (swing[step], 14), flame: step % 2 == 0 ? "F" : "V")
        let lit = (0..<dots).map { (9 + $0 * 3, 1) }
        return sprite.pixels(lit.flatMap { [($0.0, $0.1), ($0.0 + 1, $0.1), ($0.0, $0.1 + 1), ($0.0 + 1, $0.1 + 1)] }, "V")
    }

    let needsInput: [Sprite] = (0..<4).map { step in
        let raised = (x: step % 2 == 0 ? 20 : 19, y: 6)
        let sprite = nyx(wings: step % 2 == 0 ? .up : .mid, eyes: .wide, handle: raised, flame: step % 2 == 0 ? "F" : "V")
        let moved = step % 2 == 0 ? sprite : sprite.shifted(dy: -1)
        return moved.stamped(exclamation("R", bar: 4, dot: 2), x: 11, y: 0)
    }

    let raised = (x: 20, y: 6)
    let finished: [Sprite] = [
        nyx(wings: .down, eyes: .joy).shifted(dy: 1),
        confetti(glow(nyx(wings: .up, eyes: .joy, handle: raised, flame: "V"), handle: raised).shifted(dy: -1),
                 [(1, 1, "Y"), (3, 14, "V"), (0, 8, "R")]),
        confetti(glow(nyx(wings: .up, eyes: .joy, handle: raised, flame: "V"), handle: raised).shifted(dy: -3),
                 [(0, 3, "R"), (2, 12, "Y"), (22, 1, "V"), (1, 18, "V")]),
        confetti(glow(nyx(wings: .mid, eyes: .joy, handle: raised, flame: "V"), handle: raised).shifted(dy: -1),
                 [(1, 2, "V"), (2, 15, "Y"), (22, 18, "R")]),
        nyx(wings: .mid, eyes: .joy, flame: "V"),
    ]

    return CharacterArt(
        folder: "nyx",
        displayName: "Nyx",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "{project} begs your blessing: {detail}!",
                "Shall {project} proceed? {detail}",
                "The fate of {project} hangs: {detail}!",
            ],
            .question: [
                "{project} cries out: {detail}?!",
                "A question stirs in {project}: {detail}",
                "{project} demands an answer: {detail}",
            ],
            .working: [
                "{project}: the plot thickens... 🌙",
                "Behold, {project} toils in the dark 🕯️",
                "{project}: I tend the flame with {tool}!",
            ],
            .finished: [
                "It is done! {project} is complete! 🌙",
                "{project} triumphs! Sing, moonlight!",
                "The deed is finished: {project} ✨",
            ],
            .idle: [
                "{project} sleeps beneath the moon 🌙",
                "{project}: silence... too silent.",
                "My lantern waits on {project}.",
            ],
            .allClear: [
                "The night is clear. No sessions 🌙",
                "Silence falls. Nothing calls to you.",
                "The lantern burns, alone.",
            ],
        ]
    )
}
