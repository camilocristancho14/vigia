import SwiftUI

/// Which character an animated mark is.
///
/// Clawd is Claude Code's and the bot is everyone's; the others are drawn for
/// one provider each from the approved designs in `design/mascotas`. Antigravity
/// has two to choose from — both made of Google's sparkle and arch — and Float
/// Bot, the one shaped like Antigravity's own logo, is its default.
enum MascotCharacter: String, CaseIterable, Identifiable, Sendable {
    case clawd
    case floatBot
    case starBuddy
    case cloudGhost
    /// The upstream's shape-shifting bot, with a persona, colour and body.
    case bot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clawd: "Clawd"
        case .floatBot: "Float Bot"
        case .starBuddy: "Star Buddy"
        case .cloudGhost: "Cloud Ghost"
        case .bot: .localized("Bot")
        }
    }

    /// The characters a provider's mark can be, its default first.
    static func options(for provider: Provider) -> [MascotCharacter] {
        switch provider {
        case .claudeCode: [.clawd]
        case .antigravity: [.floatBot, .starBuddy, .bot]
        case .codex: [.cloudGhost, .bot]
        default: [.bot]
        }
    }

    static func automatic(for provider: Provider) -> MascotCharacter {
        options(for: provider)[0]
    }

    /// Whether it is one of the vector characters drawn by `VectorMascotView`.
    var isVector: Bool { self == .floatBot || self == .starBuddy || self == .cloudGhost }

    /// The colour that says which character this is, for deciding whether it
    /// can keep its colours against the menu bar behind it.
    var brand: Color {
        switch self {
        case .clawd: Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
        case .floatBot, .starBuddy: Color(hex: 0x3186FF)
        case .cloudGhost: Color(hex: 0x7A9DFF)
        case .bot: .white
        }
    }
}

extension Color {
    /// An sRGB colour from a 0xRRGGBB literal, as the design tables give them.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
