import TouchBuddyCore

private let palette: Palette = [
    "O": 0xD97757, "D": 0xA8472B, "W": 0xFFFFFF, "K": 0x2B1A14,
    "P": 0xF4A58A, "Y": 0xFFD23F, "G": 0x5C6770, "H": 0xB8C2CC,
]

private let bodyLines = [
    "....DDDDDDD....",
    "..DDOOOOOOODD..",
    ".DOOOOOOOOOOOD.",
    "DOOOOOOOOOOOOOD",
    "DOOOOOOOOOOOOOD",
    "DOOOOOOOOOOOOOD",
    "DOOOOOOOOOOOOOD",
    "DOOOOOOOOOOOOOD",
    "DOOOOOOOOOOOOOD",
    "DOOOOOOOOOOOOOD",
    ".DOOOOOOOOOOOD.",
    "..DDOOOOOOODD..",
    "....DDDDDDD....",
    "...DDD...DDD...",
]

private let starSpark = ["  W  ", "W W W", " WWW ", "W W W", "  W  "]
private let starPlus = ["  W  ", "  W  ", "WWWWW", "  W  ", "  W  "]
private let starX = ["W   W", " W W ", "  W  ", " W W ", "W   W"]

private let armLeftUp = ["OO", "OO", "OO", "OD"]

private enum Eyes {
    case open, blink, happy, down

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .open:
            return sprite.stamped(["WK", "KK"], x: 8, y: 13).stamped(["WK", "KK"], x: 13, y: 13)
        case .blink:
            return sprite.stamped(["OO", "KK"], x: 8, y: 13).stamped(["OO", "KK"], x: 13, y: 13)
        case .happy:
            return sprite.stamped(["OKO", "KOK"], x: 7, y: 13).stamped(["OKO", "KOK"], x: 13, y: 13)
        case .down:
            return sprite.stamped(["OO", "WK", "KK"], x: 8, y: 13).stamped(["OO", "WK", "KK"], x: 13, y: 13)
        }
    }
}

private enum Mouth {
    case smile, open, flat, grin

    func stamp(_ sprite: Sprite) -> Sprite {
        switch self {
        case .smile: return sprite.stamped(["KOOOK", "OKKKO"], x: 9, y: 16)
        case .open: return sprite.stamped(["KKK", "KKK", "OKO"], x: 10, y: 16)
        case .flat: return sprite.stamped(["KKK"], x: 10, y: 17)
        case .grin: return sprite.stamped(["KKKKK", "OKPKO"], x: 9, y: 16)
        }
    }
}

private func sparky(
    eyes: Eyes = .open, mouth: Mouth = .smile, star: [String] = starSpark,
    leftArm: Bool = false, rightArm: Bool = false
) -> Sprite {
    var sprite = Sprite.blank.stamped(bodyLines, x: 4, y: 9)
    if leftArm { sprite = sprite.stamped(armLeftUp, x: 2, y: 10) }
    if rightArm { sprite = sprite.stamped(mirrored(armLeftUp), x: 19, y: 10) }
    sprite = sprite.stamped(["PP"], x: 6, y: 16).stamped(["PP"], x: 15, y: 16)
    sprite = mouth.stamp(eyes.stamp(sprite))
    return sprite.stamped(star, x: 9, y: 5)
}

private func typing(frame: Int) -> Sprite {
    let leftDown = frame % 2 == 0
    var sprite = sparky(eyes: .down, mouth: .flat, star: [starX, starPlus, starSpark, starPlus][frame % 4])
    sprite = sprite.stamped(["WW", "WW"], x: 6, y: leftDown ? 19 : 18)
    sprite = sprite.stamped(["WW", "WW"], x: 16, y: leftDown ? 18 : 19)
    return sprite.stamped([String(repeating: "G", count: 19), "GHGHGHGHGHGHGHGHGHG"], x: 2, y: 21)
}

private func confetti(_ sprite: Sprite, _ points: [(Int, Int, Character)]) -> Sprite {
    points.reduce(sprite) { $0.pixels([($1.0, $1.1)], $1.2) }
}

func sparkyArt() -> CharacterArt {
    let idle: [Sprite] = [
        sparky(),
        sparky(star: starPlus),
        sparky().shifted(dy: 1),
        sparky(star: starPlus).shifted(dy: 1),
        sparky(),
        sparky(eyes: .blink),
    ]

    let working = (0..<4).map(typing)

    let needsInput: [Sprite] = [
        sparky(mouth: .open, leftArm: true),
        sparky(mouth: .open, rightArm: true).shifted(dy: -2),
        sparky(mouth: .open, leftArm: true),
        sparky(mouth: .open, rightArm: true).shifted(dy: -2),
    ].enumerated().map { index, sprite in
        sprite.stamped(exclamation(index % 2 == 0 ? "Y" : "W"), x: 20, y: 0)
    }

    let finished: [Sprite] = [
        sparky(eyes: .happy, mouth: .grin).shifted(dy: 1),
        confetti(sparky(eyes: .happy, mouth: .grin, star: starPlus, leftArm: true, rightArm: true).shifted(dy: -2),
                 [(1, 4, "Y"), (21, 5, "P"), (3, 12, "W"), (21, 13, "Y")]),
        confetti(sparky(eyes: .happy, mouth: .grin, star: starX, leftArm: true, rightArm: true).shifted(dy: -5),
                 [(1, 1, "P"), (22, 2, "Y"), (0, 9, "Y"), (22, 10, "W"), (2, 16, "P")]),
        confetti(sparky(eyes: .happy, mouth: .grin, star: starPlus, leftArm: true, rightArm: true).shifted(dy: -2),
                 [(2, 7, "W"), (21, 8, "P"), (1, 15, "Y"), (22, 17, "Y")]),
        confetti(sparky(eyes: .happy, mouth: .smile),
                 [(1, 12, "Y"), (22, 14, "P")]),
    ]

    return CharacterArt(
        folder: "sparky",
        displayName: "Sparky",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "Psst — {project} wants to {detail}. Your call! 👀",
                "{project}: okay to {detail}? You've got this!",
                "Quick yes/no from you: {detail} in {project}?",
            ],
            .question: [
                "{project} has a question: {detail} 🤔",
                "Help me out? {project} asks: {detail}",
                "Your input please! {project}: {detail}",
            ],
            .working: [
                "{project}: on it with {tool}! ⚡",
                "{project} is humming along — nice!",
                "Busy bee in {project}, hang tight!",
            ],
            .finished: [
                "{project} is done! Great work! 🎉",
                "All wrapped up in {project} ✨",
                "Ta-da! {project} finished!",
            ],
            .idle: [
                "{project} is ready when you are!",
                "Standing by on {project} 🙂",
                "{project}: all quiet, let's go!",
            ],
            .allClear: [
                "All clear! Nothing needs you ✨",
                "No sessions — go enjoy a break!",
                "Quiet day. You're doing great!",
            ],
        ]
    )
}
