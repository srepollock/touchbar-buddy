import TouchBuddyCore

private let palette: Palette = [
    "N": 0x1F2A44, "B": 0x3D6FD8, "L": 0x6E97F0, "S": 0xC4CCD6,
    "D": 0x5C6879, "W": 0xF4F1E8, "R": 0xFF5A5F, "Y": 0xFFD23F,
]

private func repeated(_ char: Character, _ count: Int) -> String {
    String(repeating: char, count: count)
}

private let bodyLines: [String] =
    [".NNNNNNNNNNNNN..", "N" + repeated("B", 13) + "N.", "N" + repeated("B", 14) + "N"]
    + Array(repeating: "NL" + repeated("B", 13) + "N", count: 13)
    + [".NNNNNNNNNNNNNN."]

private let shutterLines = [
    "SSSSSSSS",
    "SSSSDDSS",
    "SSSSDDSS",
    "SSSSDDSS",
    "DDDDDDDD",
]

private let feet = ["NN", "NN"]
private let armDown = ["BB", "BB", "BB", "NN"]
private let armUp = ["NN", "BB", "BB", "BB"]
private let smile = ["NWWN", "WNNW"]

private enum Face {
    case open, blink, happy, look(Int), bang, bangInverted

    func stamp(_ sprite: Sprite) -> Sprite {
        let label = Array(repeating: repeated("W", 10), count: 7)
        let base = sprite.stamped(label, x: 7, y: 13)
        switch self {
        case .open:
            return base.stamped(["NN", "NN"], x: 9, y: 14).stamped(["NN", "NN"], x: 13, y: 14).stamped(smile, x: 10, y: 17)
        case .blink:
            return base.stamped(["WW", "NN"], x: 9, y: 14).stamped(["WW", "NN"], x: 13, y: 14).stamped(smile, x: 10, y: 17)
        case .happy:
            return base.stamped(["WNW", "NWN"], x: 8, y: 14).stamped(["WNW", "NWN"], x: 13, y: 14)
                .stamped(["NNNN", "WNNW"], x: 10, y: 17)
        case .look(let dx):
            return base.stamped(["NN", "NN"], x: 9 + dx, y: 14).stamped(["NN", "NN"], x: 13 + dx, y: 14)
                .stamped(["NNNN"], x: 10, y: 18)
        case .bang:
            let dark = Array(repeating: repeated("N", 10), count: 7)
            return sprite.stamped(dark, x: 7, y: 13).stamped(exclamation("Y", bar: 4), x: 11, y: 13)
        case .bangInverted:
            let red = Array(repeating: repeated("R", 10), count: 7)
            return sprite.stamped(red, x: 7, y: 13).stamped(exclamation("W", bar: 4), x: 11, y: 13)
        }
    }
}

private enum Arms {
    case down, up, left, right
}

private func floppy(face: Face, shutter: Int = 8, arms: Arms = .down) -> Sprite {
    var sprite = Sprite.blank
        .stamped(bodyLines, x: 4, y: 4)
        .stamped(shutterLines, x: shutter, y: 5)
        .stamped(feet, x: 7, y: 21).stamped(feet, x: 16, y: 21)
    let leftUp = arms == .up || arms == .left
    let rightUp = arms == .up || arms == .right
    sprite = sprite.stamped(leftUp ? armUp : armDown, x: 2, y: leftUp ? 7 : 12)
    sprite = sprite.stamped(rightUp ? armUp : armDown, x: 20, y: rightUp ? 7 : 12)
    return face.stamp(sprite)
}

func floppyArt() -> CharacterArt {
    let idle: [Sprite] = [
        floppy(face: .open),
        floppy(face: .open),
        floppy(face: .open, shutter: 9).shifted(dy: 1),
        floppy(face: .open, shutter: 9).shifted(dy: 1),
        floppy(face: .blink),
        floppy(face: .open),
    ]

    let slide = [6, 7, 9, 10, 9, 7]
    let working: [Sprite] = slide.enumerated().map { index, position in
        let direction = index < 3 ? 1 : -1
        return floppy(
            face: .look(direction), shutter: position, arms: index % 2 == 0 ? .left : .right
        ).shifted(dy: index % 2 == 0 ? 0 : 1)
    }

    let needsInput: [Sprite] = [
        floppy(face: .bang, shutter: 6, arms: .up),
        floppy(face: .bangInverted, shutter: 10, arms: .down).shifted(dy: -2),
        floppy(face: .bang, shutter: 10, arms: .up),
        floppy(face: .bangInverted, shutter: 6, arms: .down).shifted(dy: -2),
    ]

    let finished: [Sprite] = [
        floppy(face: .happy, shutter: 7).shifted(dy: 1),
        confetti(floppy(face: .happy, shutter: 8, arms: .up).shifted(dy: -2),
                 [(1, 4, "Y"), (22, 5, "L"), (1, 14, "W"), (22, 12, "Y")]),
        confetti(floppy(face: .happy, shutter: 10, arms: .up).shifted(dy: -4),
                 [(1, 1, "L"), (22, 2, "Y"), (0, 9, "Y"), (22, 8, "W"), (2, 16, "L")]),
        confetti(floppy(face: .happy, shutter: 8, arms: .up).shifted(dy: -2),
                 [(2, 6, "W"), (21, 7, "L"), (0, 15, "Y"), (22, 16, "Y")]),
        confetti(floppy(face: .happy, shutter: 6), [(1, 11, "Y"), (22, 13, "L")]),
    ]

    return CharacterArt(
        folder: "floppy",
        displayName: "Floppy",
        palette: palette,
        animations: [
            (.idle, idle), (.working, working), (.needsInput, needsInput), (.finished, finished),
        ],
        speech: [
            .permission: [
                "{project} wants to {detail}. Remember Y/N prompts?",
                "{project}: permission to {detail}, please. Authentic!",
                "Insert approval: {project} needs {detail}.",
            ],
            .question: [
                "{project} has a question: {detail}",
                "{project}: {detail} Mind answering? Takes 1.44 MB.",
                "Quick one from {project}: {detail}",
            ],
            .working: [
                "{project}: seeking sectors, running {tool}.",
                "{project} is writing to disk. Hear the whirr?",
                "{project}: {tool} in progress. No hot-swapping.",
            ],
            .finished: [
                "{project}: saved! Eject safely.",
                "{project} is done. Write-protected. Probably.",
                "Task complete in {project}. Nice and tidy.",
            ],
            .idle: [
                "{project}: idle. Defragmenting my thoughts.",
                "{project} is quiet. Spinning down.",
                "{project}: waiting. Like a good drive.",
            ],
            .allClear: [
                "No disks in the drive. All clear.",
                "Drive A: is empty. Nostalgic, really.",
                "Nothing to read. Nothing to write.",
            ],
        ]
    )
}
