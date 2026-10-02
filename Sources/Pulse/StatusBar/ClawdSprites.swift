// Poses for Clawd that the walking GIF did not have, drawn on the same
// 17 × 12 grid at 3 px a cell (51 × 36) so they sit exactly where the walk
// frames do and wear the same orange. Original artwork for Vigía; Clawd is
// Anthropic's character.
import AppKit

/// What the mascot is up to, which is what decides how it moves.
enum MascotPose: Equatable, Sendable {
    /// Busy at something that moves around: a command, a search, a sub-agent.
    case run
    /// Busy at something done sitting down: thinking, reading, editing.
    case type
    /// A turn just ended: a short break with a cup of coffee.
    case coffee
    /// Idle but recently active; blinks now and then.
    case awake
    /// Idle for a long while.
    case sleep
    /// Three quarters of a limit gone: worn out, sweating.
    case tired
    /// A limit used up: nothing more to give.
    case spent

    var isWorking: Bool { self == .run || self == .type }

    /// What a mark does when nobody can say what its agent is up to: asleep
    /// through the night, coffee in the early morning, then a change of
    /// scene every five minutes. Marks with a character (`playful`) also
    /// sit down at the laptop and go off for a run; a plain logo only
    /// rests and has its coffee.
    static func ofTheDay(at date: Date, playful: Bool, calendar: Calendar = .current) -> MascotPose {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 12
        let minutes = hour * 60 + (parts.minute ?? 0)
        if hour >= 23 || hour < 6 { return .sleep }
        if hour < 9 { return .coffee }
        let slot = (minutes / 5) % 8
        let characterful: [MascotPose] = [.type, .awake, .run, .coffee, .type, .run, .awake, .coffee]
        let plain: [MascotPose] = [.awake, .coffee, .awake, .awake, .coffee, .awake, .awake, .awake]
        return playful ? characterful[slot] : plain[slot]
    }

    /// The pose for a turn in flight, from the word the status bar shows:
    /// at the laptop for commands, edits and thinking, on the move for
    /// looking things up and handing work out.
    static func working(label: String?) -> MascotPose {
        switch label {
        case "Reading", "Searching", "Browsing web", "Searching web", "Delegating": .run
        default: .type
        }
    }
}

enum ClawdSprites {
    static let cell = 3

    private static let palette: [Character: (UInt8, UInt8, UInt8)] = [
        "O": (217, 119, 87), "K": (25, 20, 20), "W": (246, 242, 235), "B": (110, 70, 50),
        "S": (225, 228, 236), "Y": (250, 204, 21), "C": (120, 200, 245), "D": (184, 96, 70), "G": (198, 202, 210), "g": (138, 144, 156), "Z": (140, 165, 240)
    ]

    static let awake0: [String] = [
        ".................",
        "...OOOOOOOOOOO...",
        "...OKKOOOOOKKO...",
        "OOOOKKOOOOOKKOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let awake1: [String] = [
        ".................",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "OOOOKKOOOOOKKOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let sleep0: [String] = [
        "..............ZZZ",
        "...OOOOOOOOOOO..Z",
        "...OOOOOOOOOOO.Z.",
        "...OKKOOOOOKKOZZZ",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let sleep1: [String] = [
        ".................",
        "...OOOOOOOOOOO.ZZ",
        "...OOOOOOOOOOO..Z",
        "...OKKOOOOOKKO.ZZ",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let coffee0: [String] = [
        "...............S.",
        "...OOOOOOOOOOOBBB",
        "...OKKOOOOOKKOWWW",
        "OOOOKKOOOOOKKOWWW",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let coffee1: [String] = [
        "..............S..",
        "...OOOOOOOOOOOBBB",
        "...OKKOOOOOKKOWWW",
        "OOOOKKOOOOOKKOWWW",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let coffee2: [String] = [
        "..............BBB",
        "...OOOOOOOOOOOWWW",
        "...OKKOOOOOKKOWWW",
        "OOOOOOOOOOOOOO...",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let type0: [String] = [
        ".................",
        "...OOOOOOOOOOO...",
        "...OKKOOOOOKKO...",
        "...OKKOOOOOKKO...",
        "...OOOOOOOOOOOOO.",
        ".OOOOOOOOOOOOOO..",
        "..OOOOOOOOOOOO...",
        "...OGGGGGGGGGO...",
        "...OGGGGgGGGGO...",
        "...OGGGGGGGGGO...",
        "...OGGGGGGGGGO...",
        "...ggggggggggg..."
    ]

    static let type1: [String] = [
        ".................",
        "...OOOOOOOOOOO...",
        "...OKKOOOOOKKO...",
        "...OKKOOOOOKKO...",
        ".OOOOOOOOOOOOO...",
        "..OOOOOOOOOOOOOO.",
        "...OOOOOOOOOOOOO.",
        "...OGGGGGGGGGO...",
        "...OGGGGgGGGGO...",
        "...OGGGGGGGGGO...",
        "...OGGGGGGGGGO...",
        "...ggggggggggg..."
    ]

    static let tired0: [String] = [
        "..............C..",
        "...OOOOOOOOOOO...",
        "...ODDOOOOODDO...",
        "...OKKOOOOOKKO...",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let tired1: [String] = [
        ".................",
        "...OOOOOOOOOOOC..",
        "...ODDOOOOODDO...",
        "...OKKOOOOOKKO...",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let tired2: [String] = [
        ".................",
        "...OOOOOOOOOOO...",
        "...ODDOOOOODDOC..",
        "...OKKOOOOOKKO...",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let spent0: [String] = [
        "....Y.......Y....",
        "...OOOOOOOOOOO...",
        "...OKOKOOOKOKO...",
        "...OOKOOOOOKOO...",
        "...OKOKOOOKOKO...",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let spent1: [String] = [
        "......Y...Y......",
        "...OOOOOOOOOOO...",
        "...OKOKOOOKOKO...",
        "...OOKOOOOOKOO...",
        "...OKOKOOOKOKO...",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    /// Full-colour frames for a pose, in the order they play.
    @MainActor
    static let frames: [String: [NSImage]] = [
        "awake": [awake0, awake1].map(render),
        "sleep": [sleep0, sleep1].map(render),
        "coffee": [coffee0, coffee1, coffee2].map(render),
        "type": [type0, type1].map(render),
        "tired": [tired0, tired1, tired2, tired1].map(render),
        "spent": [spent0, spent1].map(render)
    ]

    private static func render(_ rows: [String]) -> NSImage {
        let width = rows[0].count * cell, height = rows.count * cell
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4, bitsPerPixel: 32
        ), let data = rep.bitmapData else { return NSImage(size: NSSize(width: width, height: height)) }
        data.initialize(repeating: 0, count: width * height * 4)
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() {
                guard let (r, g, b) = palette[character] else { continue }
                for dy in 0..<cell {
                    for dx in 0..<cell {
                        let offset = ((row * cell + dy) * width + column * cell + dx) * 4
                        data[offset] = r; data[offset + 1] = g; data[offset + 2] = b; data[offset + 3] = 255
                    }
                }
            }
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
}
