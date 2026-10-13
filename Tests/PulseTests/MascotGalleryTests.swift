import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// Every character in every pose draws something, in colour and in one ink.
/// With `VIGIA_CAPTURE_DIR` set, also writes a contact sheet of them there,
/// which is how the poses are reviewed by eye.
@Suite("Mascot gallery")
@MainActor
struct MascotGalleryTests {
    private static let characters: [MascotCharacter] = [.floatBot, .starBuddy, .cloudGhost]

    @Test("Each vector character draws every pose, coloured and as a template")
    func everyPoseDraws() throws {
        for character in Self.characters {
            for pose in MascotPose.allCases {
                for colour in [true, false] {
                    let image = try #require(VectorMascots.image(character, pose: pose, size: 20, colour: colour))
                    #expect(Self.inkedFraction(image) > 0.05, "\(character) \(pose) colour: \(colour)")
                }
            }
        }
    }

    @Test("Antigravity's mark is Float Bot unless Star Buddy or the bot is chosen; no Gemini character of its own")
    func characterChoice() {
        let antigravity = AccountKey(.antigravity), codex = AccountKey(.codex), grok = AccountKey(.grok)
        let plain = AppSettings(enabledAccounts: [Provider.antigravity.rawValue])
        #expect(plain.mascotCharacter(for: antigravity) == .floatBot)
        #expect(plain.mascotCharacter(for: codex) == .cloudGhost)
        #expect(plain.mascotCharacter(for: AccountKey(.claudeCode)) == .clawd)
        #expect(plain.mascotCharacter(for: grok) == .bot)
        #expect(MascotCharacter.options(for: .antigravity) == [.floatBot, .starBuddy, .bot])
        #expect(MascotCharacter.options(for: .gemini) == [.bot])

        let chosen = AppSettings(enabledAccounts: [Provider.antigravity.rawValue],
                                 mascotCharacters: [antigravity.id: MascotCharacter.starBuddy.rawValue,
                                                    grok.id: MascotCharacter.starBuddy.rawValue,
                                                    codex.id: "retired-character"])
        #expect(chosen.mascotCharacter(for: antigravity) == .starBuddy)
        // A character the provider does not offer, or one that no longer
        // exists, reads as the provider's own.
        #expect(chosen.mascotCharacter(for: grok) == .bot)
        #expect(chosen.mascotCharacter(for: codex) == .cloudGhost)
    }

    @Test("Clawd has a frame for every pose on the walking sprite's grid")
    func clawdEveryPose() {
        for pose in MascotPose.allCases {
            for colour in [true, false] {
                let frame = ClawdFrames.frame(for: pose, at: 0.7, colour: colour)
                #expect(frame?.size == NSSize(width: 51, height: 36), "\(pose)")
            }
        }
    }

    @Test("Contact sheet, when asked for")
    func contactSheet() throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIA_CAPTURE_DIR"] else { return }
        let poses = MascotPose.allCases
        let cell: CGFloat = 64
        let sheet = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: "").frame(width: 90)
                ForEach(poses, id: \.self) { pose in
                    Text(verbatim: "\(pose)").font(.system(size: 9)).frame(width: cell)
                }
            }
            ForEach(Self.characters, id: \.self) { character in
                ForEach([true, false], id: \.self) { colour in
                    HStack(spacing: 6) {
                        Text(verbatim: "\(character.title)\(colour ? "" : " (mono)")")
                            .font(.system(size: 10)).frame(width: 90, alignment: .leading)
                        ForEach(poses, id: \.self) { pose in
                            Canvas { context, size in
                                VectorMascots.draw(character, pose: pose, time: 1.3, colour: colour, in: &context, size: size)
                            }
                            .frame(width: cell, height: cell)
                            .background(colour ? Color(white: 0.16) : Color(white: 0.92))
                            .foregroundStyle(colour ? Color.white : Color.black)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text(verbatim: "Clawd").font(.system(size: 10)).frame(width: 90, alignment: .leading)
                ForEach(poses, id: \.self) { pose in
                    if let frame = ClawdFrames.frame(for: pose, at: 0.7, colour: true) {
                        Image(nsImage: frame).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                            .frame(width: cell, height: cell).background(Color(white: 0.16))
                    }
                }
            }
            HStack(spacing: 6) {
                Text(verbatim: "20 pt").font(.system(size: 10)).frame(width: 90, alignment: .leading)
                ForEach(poses, id: \.self) { pose in
                    HStack(spacing: 1) {
                        ForEach(Self.characters, id: \.self) { character in
                            Canvas { context, size in
                                VectorMascots.draw(character, pose: pose, time: 1.3, colour: true, in: &context, size: size)
                            }
                            .frame(width: 20, height: 20)
                        }
                    }
                    .frame(width: cell, height: 24)
                    .background(Color(white: 0.92))
                }
            }
        }
        .padding(10)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appending(path: "mascotas-poses.png"))
    }

    /// The share of pixels with any coverage at all.
    private static func inkedFraction(_ image: NSImage) -> Double {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
        var inked = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                inked += 1
            }
        }
        return Double(inked) / Double(max(1, rep.pixelsWide * rep.pixelsHigh))
    }
}
