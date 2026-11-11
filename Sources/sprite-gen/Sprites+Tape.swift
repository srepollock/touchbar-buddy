import TouchBuddyCore

private let palette: Palette = [
    "N": 0x2A2F3E, "O": 0xE8743B, "W": 0xF4E9CF, "K": 0x12151D,
    "R": 0xB8392B, "Y": 0xFFD23F, "L": 0xF59A66,
]

private func repeated(_ char: Character, _ count: Int) -> String {
    String(repeating: char, count: count)
}

// 20 wide x 16 tall: label on top, window with two reels, tape-head trapezoid below.
private let bodyLines: [String] = [
    repeated("N", 20),
    "N" + repeated("O", 18) + "N",
    "NO" + repeated("W", 16) + "ON",
    "NOW" + repeated("R", 7) + repeated("W", 8) + "ON",
    "NO" + repeated("W", 16) + "ON",
    "N" + repeated("O", 18) + "N",
    "NOO" + repeated("K", 14) + "OON",
    "NOO" + repeated("K", 14) + "OON",
    "NOO" + repeated("K", 14) + "OON",
    "NOO" + repeated("K", 14) + "OON",
    "NOO" + repeated("K", 14) + "OON",
    "N" + repeated("O", 18) + "N",
    "NOOO" + repeated("W", 12) + "OOON",
    "NOOOO" + repeated("W", 10) + "OOOON",
    "NOOOOO" + repeated("W", 8) + "OOOOON",
    repeated("N", 20),
]

private let feet = ["NN", "NN"]
private let armDown = ["OO", "OO", "OO", "NN"]
private let armUp = ["NN", "OO", "OO", "OO"]

private enum Reel {
    case plus, cross, open, blink, happy, wide

    /// "_" is the window colour behind the reel.
    var lines: [String] {
        switch self {
        case .plus:
            return ["_WWW_", "WWKWW", "WKWKW", "WWKWW", "_WWW_"]
        case .cross:
            return ["_WWW_", "WKWKW", "WWWWW", "WKWKW", "_WWW_"]
        case .open:
            return ["_WWW_", "WWKWW", "WWKWW", "WWKWW", "_WWW_"]
        case .wide:
            return ["_WWW_", "WWWWW", "WWKWW", "WWWWW", "_WWW_"]
        case .blink:
            return ["_____", "_____", "WWWWW", "_____", "_____"]
        case .happy:
            return ["_____", "_WWW_", "W___W", "_____", "_____"]
        }
    }

    func resolved(window: Character) -> [String] {
        lines.map { String($0.map { $0 == "_" ? window : $0 }) }
    }
}

private enum Mouth {
    case smile, grin, flat, round

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .smile: return sprite.stamped(["NWWN", "WNNW"], x: 10, y: 18)
        case .grin: return sprite.stamped(["NNNN", "WNNW"], x: 10, y: 18)
        case .flat: return sprite.stamped(["NNNN"], x: 10, y: 18)
        case .round: return sprite.stamped(["WNNW", "WNNW"], x: 10, y: 18)
        }
    }
}

private enum Arms {
    case down, up, left, right
}

private func tape(
    left: Reel, right: Reel? = nil, mouth: Mouth = .smile, window: Character = "K", arms: Arms = .down
) -> Sprite {
    var sprite = Sprite.blank
        .stamped(bodyLines, x: 2, y: 5)
        .stamped(feet, x: 5, y: 21).stamped(feet, x: 17, y: 21)
    if window != "K" {
        sprite = sprite.stamped(Array(repeating: repeated(window, 14), count: 5), x: 5, y: 11)
    }
    sprite = sprite
        .stamped(left.resolved(window: window), x: 6, y: 11)
        .stamped((right ?? left).resolved(window: window), x: 13, y: 11)
    let leftUp = arms == .up || arms == .left
    let rightUp = arms == .up || arms == .right
    sprite = sprite.stamped(leftUp ? armUp : armDown, x: 0, y: leftUp ? 8 : 13)
    sprite = sprite.stamped(rightUp ? armUp : armDown, x: 22, y: rightUp ? 8 : 13)
    return mouth.stamp(sprite)
}

func tapeArt() -> CharacterArt {
    let idle: [Sprite] = [
        tape(left: .open),
        tape(left: .open),
        tape(left: .open).shifted(dy: 1),
        tape(left: .open).shifted(dy: 1),
        tape(left: .blink),
        tape(left: .open),
    ]

    let working: [Sprite] = (0..<6).map { step in
        let reel: Reel = step % 2 == 0 ? .plus : .cross
        return tape(left: reel, mouth: step % 3 == 0 ? .round : .flat, arms: step % 2 == 0 ? .left : .right)
            .shifted(dy: step % 2)
    }

    let bang = exclamation("Y", bar: 3, dot: 1)
    let needsInput: [Sprite] = [
        tape(left: .wide, mouth: .round, window: "Y", arms: .up).stamped(bang, x: 11, y: 0),
        tape(left: .wide, mouth: .round, window: "K", arms: .down).shifted(dy: 1).stamped(bang, x: 11, y: 0),
        tape(left: .wide, mouth: .round, window: "Y", arms: .up).stamped(bang, x: 11, y: 0),
        tape(left: .wide, mouth: .round, window: "K", arms: .down).shifted(dy: 1).stamped(bang, x: 11, y: 0),
    ]

    let finished: [Sprite] = [
        tape(left: .happy, mouth: .grin).shifted(dy: 1),
        confetti(tape(left: .happy, mouth: .grin, arms: .up).shifted(dy: -2),
                 [(1, 3, "Y"), (21, 4, "L"), (1, 12, "W"), (22, 11, "Y")]),
        confetti(tape(left: .happy, mouth: .grin, arms: .up).shifted(dy: -4),
                 [(1, 1, "L"), (22, 1, "Y"), (0, 7, "Y"), (22, 6, "W"), (2, 14, "L")]),
        confetti(tape(left: .happy, mouth: .grin, arms: .up).shifted(dy: -2),
                 [(3, 5, "W"), (20, 6, "L"), (0, 13, "Y"), (22, 14, "Y")]),
        confetti(tape(left: .happy, mouth: .grin), [(1, 10, "Y"), (22, 12, "L")]),
    ]

    return CharacterArt(
        folder: "tape",
        displayName: "Tape",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "Hey, {project} wants to {detail}. Cool with you?",
                "{project} is asking to {detail}. Drop the needle?",
                "Mellow request from {project}: {detail}",
            ],
            .question: [
                "{project} needs your take: {detail}",
                "Real quick, {project}: {detail}",
                "{project}'s got a question, friend: {detail}",
            ],
            .working: [
                "{project} is rolling. Running {tool}.",
                "Spinning up {project}. Easy does it.",
                "{project}: {tool} on repeat. Good vibes.",
            ],
            .finished: [
                "{project} is a wrap. That's a hit.",
                "Track done in {project}. Smooth.",
                "{project}: finished. Flip the tape?",
            ],
            .idle: [
                "{project} is chilling. Side A, paused.",
                "Nothing spinning in {project}. Nice.",
                "{project}: quiet. Cue the lo-fi.",
            ],
            .allClear: [
                "No sessions. Rewinding, man.",
                "All clear. Silence is a track too.",
                "Nothing playing. Stay mellow.",
            ],
        ]
    )
}
