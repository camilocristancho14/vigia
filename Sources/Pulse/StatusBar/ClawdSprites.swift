// Poses for Clawd that the walking GIF did not have, drawn on the same
// 17 × 12 grid at 3 px a cell (51 × 36) so they sit exactly where the walk
// frames do and wear the same orange. Original artwork for Vigía; Clawd is
// Anthropic's character.
import AppKit

/// What the mascot is up to, which is what decides how it moves.
enum MascotPose: Equatable, Sendable, CaseIterable {
    /// Busy at something that moves around: a command, a search, a sub-agent.
    case run
    /// Busy at something done sitting down: reading, editing, running a tool.
    case type
    /// Busy, and it is the model's move: thinking the answer through.
    case thinking
    /// A turn just started: still getting up.
    case waking
    /// A turn is open but waiting for a person: a question, a permission.
    case waiting
    /// A turn just finished, for a few seconds.
    case celebrate
    /// A turn ended a little while ago: a short break with a cup of coffee.
    case coffee
    /// Idle but recently active; blinks now and then.
    case awake
    /// Idle: a stretch between jobs.
    case stretch
    /// Idle: a little game to pass the time.
    case play
    /// Idle for a long while.
    case sleep
    /// Three quarters of a limit gone: worn out, sweating.
    case tired
    /// A limit used up: nothing more to give.
    case spent
    /// The turn failed, or the session died in the middle of one.
    case error

    var isWorking: Bool { self == .run || self == .type || self == .thinking }

    /// What an idle mark does through the working day, rotated every five
    /// minutes. None of these is a working pose: a mark that is not working
    /// must never look as though it were.
    static let daytime: [MascotPose] = [.awake, .coffee, .play, .stretch]
    /// Early in the morning: getting up and going, not yet at play.
    static let morning: [MascotPose] = [.waking, .coffee, .stretch, .awake]

    /// What a mark does when nobody can say what its agent is up to: asleep
    /// through the night, then a change of scene every five minutes.
    ///
    /// `slot` is the mark's place among the marks on screen, in the order of
    /// the rail. The marks are dealt the rotation together, so on any one
    /// surface they all do something different; past four of them the
    /// rotation repeats, each pose as few times as it can.
    static func ofTheDay(slot: Int = 0, at date: Date, calendar: Calendar = .current) -> MascotPose {
        let hour = calendar.component(.hour, from: date)
        if hour >= 23 || hour < 6 { return .sleep }
        return idle(slot: slot, at: date, calendar: calendar)
    }

    /// The idle rotation without the night: for a mark whose agent was busy
    /// minutes ago, whatever the hour.
    static func idle(slot: Int = 0, at date: Date, calendar: Calendar = .current) -> MascotPose {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 12
        let minutes = hour * 60 + (parts.minute ?? 0)
        let scenes = (6..<9).contains(hour) ? morning : daytime
        let turn = minutes / 5 + max(0, slot)
        return scenes[turn % scenes.count]
    }

    /// The pose for a turn in flight, from the word the status bar shows:
    /// thinking while it is the model's move, at the laptop for commands and
    /// edits, on the move for looking things up and handing work out.
    static func working(label: String?) -> MascotPose {
        switch label {
        case "Reading", "Searching", "Browsing web", "Searching web", "Delegating": .run
        case "Thinking…", nil: .thinking
        default: .type
        }
    }
}

/// A hash that is the same in every run of the app.
///
/// Swift's `hashValue` is seeded per process, so anything keyed off it — a
/// mark's animation phase — came out different every launch. FNV-1a, 64-bit.
enum StableHash {
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// A phase offset in seconds, spread over `span`, for a mark's clock.
    static func phase(_ text: String, span: Double = 37) -> Double {
        Double(fnv1a(text) % 1000) / 1000 * span
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

    // Thinking, getting up, waiting on a person, celebrating, stretching,
    // playing and a failed turn, in the same 17 × 12 grid and palette.

    static let thinking0: [String] = [
        "...W.............",
        "...OOOOOOOOOOO...",
        "...OOKKOOOOKKO...",
        "OOOOOOOOOOOOOO...",
        "OOOOOOOOOOOOOO...",
        "OOOOOOOOOOOOOOOO.",
        "...OOOOOOOOOOOOO.",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let thinking1: [String] = [
        "...W...W.........",
        "...OOOOOOOOOOO...",
        "...OOKKOOOOKKO...",
        "OOOOOOOOOOOOOO...",
        "OOOOOOOOOOOOOO...",
        "OOOOOOOOOOOOOOOO.",
        "...OOOOOOOOOOOOO.",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let thinking2: [String] = [
        "...W...W...W.....",
        "...OOOOOOOOOOO...",
        "...OOKKOOOOKKO...",
        "OOOOOOOOOOOOOO...",
        "OOOOOOOOOOOOOO...",
        "OOOOOOOOOOOOOOOO.",
        "...OOOOOOOOOOOOO.",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let waking0: [String] = [
        ".................",
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
        "................."
    ]

    static let waking1: [String] = [
        "..............S..",
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

    static let waking2: [String] = [
        "........Y........",
        "...OOOOOOOOOOO...",
        "...OWKOOOOOWKO...",
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

    static let waiting0: [String] = [
        "..............YYY",
        "...OOOOOOOOOOO..Y",
        "...OKKOOOOOKKO.Y.",
        "OOOOKKOOOOOKKO...",
        "OOOOOOOOOOOOOO.Y.",
        "OOOOOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let waiting1: [String] = [
        "...OOOOOOOOOOOYYY",
        "...OKKOOOOOKKO..Y",
        "OOOOKKOOOOOKKO.Y.",
        "OOOOOOOOOOOOOO...",
        "OOOOOOOOOOOOOO.Y.",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "................."
    ]

    static let celebrate0: [String] = [
        ".Y......Z......C.",
        "OOOOOOOOOOOOOOOOO",
        ".O.OOKOOOOOOKO.O.",
        "...OKOKOOOOKOK...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let celebrate1: [String] = [
        "O..OOOOOOOOOOO..Z",
        "OOOOOKOOOOOOKOOOO",
        "...OKOKOOOOKOK...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "................."
    ]

    static let stretch0: [String] = [
        ".................",
        "...OOOOOOOOOOO...",
        ".OOOKKOOOOOKKOOO.",
        "..OOKKOOOOOKKOO..",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let stretch1: [String] = [
        "..O...........O..",
        "..OOOOOOOOOOOOO..",
        "..OOOOOOOOOOOOO..",
        "...OKKOOOOOKKO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O..."
    ]

    static let play0: [String] = [
        ".Y...............",
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

    static let play1: [String] = [
        "...OOOOOYOOOOO...",
        "...OKKOOOOOKKO...",
        "OOOOKKOOOOOKKOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "................."
    ]

    static let play2: [String] = [
        "...............Y.",
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

    static let play3: [String] = [
        "...OOOOOYOOOOO...",
        "...OKKOOOOOKKO...",
        "OOOOKKOOOOOKKOOOO",
        "OOOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOOO",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...OOOOOOOOOOO...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "...O..O...O..O...",
        "................."
    ]

    static let error0: [String] = [
        "..g..........g...",
        "...DDDDDDDDDDD...",
        "...DKDKDDDKDKD...",
        "DDDDDKDDDDDKDDDDD",
        "DDDDKDKDDDKDKDDDD",
        "DDDDDDDDDDDDDDDDD",
        "...DDDDDDDDDDD...",
        "...DDDDDDDDDDD...",
        "...DDDDDDDDDDD...",
        "...D..D...D..D...",
        "...D..D...D..D...",
        "...D..D...D..D..."
    ]

    static let error1: [String] = [
        ".................",
        "...g........S....",
        "...DDDDDDDDDDD...",
        "...DKDKDDDKDKD...",
        "DDDDDKDDDDDKDDDDD",
        "DDDDKDKDDDKDKDDDD",
        "DDDDDDDDDDDDDDDDD",
        "...DDDDDDDDDDD...",
        "...DDDDDDDDDDD...",
        "...DDDDDDDDDDD...",
        "...O..O...O..O...",
        "................."
    ]

    /// Full-colour frames for a pose, in the order they play.
    @MainActor
    static let frames: [String: [NSImage]] = [
        "awake": [awake0, awake1].map(render),
        "sleep": [sleep0, sleep1].map(render),
        "coffee": [coffee0, coffee1, coffee2].map(render),
        "type": [type0, type1].map(render),
        "tired": [tired0, tired1, tired2, tired1].map(render),
        "spent": [spent0, spent1].map(render),
        "thinking": [thinking0, thinking1, thinking2].map(render),
        "waking": [waking0, waking1, waking2].map(render),
        "waiting": [waiting0, waiting1].map(render),
        "celebrate": [celebrate0, celebrate1].map(render),
        "stretch": [stretch0, stretch1].map(render),
        "play": [play0, play1, play2, play3].map(render),
        "error": [error0, error1].map(render)
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
