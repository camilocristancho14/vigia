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

    /// What each of the vector characters looks like at menu-bar size, as
    /// pixels, so "the animation is visible" can be a measurement.
    private static func pixels(_ character: MascotCharacter, _ pose: MascotPose, at time: Double,
                               colour: Bool = true) -> [UInt32] {
        let renderer = ImageRenderer(content:
            Canvas(rendersAsynchronously: false) { context, size in
                VectorMascots.draw(character, pose: pose, time: time, colour: colour, in: &context, size: size)
            }
            .frame(width: 22, height: 22)
        )
        renderer.scale = 1
        guard let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return [] }
        var out: [UInt32] = []
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let a = UInt32((c?.alphaComponent ?? 0) * 255)
                out.append(a < 60 ? 0 : UInt32((c?.redComponent ?? 0) * 255) << 16 | UInt32((c?.greenComponent ?? 0) * 255) << 8
                           | UInt32((c?.blueComponent ?? 0) * 255) | 0xFF00_0000)
            }
        }
        return out
    }

    private static func differing(_ a: [UInt32], _ b: [UInt32]) -> Int {
        zip(a, b).filter { $0 != $1 }.count
    }

    @Test("At menu-bar size a working mark visibly moves, and each pose is told from the others")
    func animationsAreVisibleAtBarSize() {
        for character in Self.characters {
            // Moves: over a second and a bit, the frames of a working pose
            // differ from each other by more than a stray pixel or two.
            for pose in [MascotPose.type, .thinking, .run, .waiting, .celebrate] {
                let frames = stride(from: 0.0, to: 1.2, by: 0.1).map { Self.pixels(character, pose, at: $0) }
                let widest = frames.dropFirst().map { Self.differing(frames[0], $0) }.max() ?? 0
                #expect(widest >= 20, "\(character) \(pose) moves \(widest) px")
            }
            // Told apart: no two poses draw the same picture at the same moment.
            let poses: [MascotPose] = [.type, .thinking, .waiting, .celebrate, .awake, .coffee, .sleep, .tired, .error]
            let stills = poses.map { Self.pixels(character, $0, at: 1.3) }
            for i in poses.indices {
                for j in poses.indices where j > i {
                    #expect(Self.differing(stills[i], stills[j]) >= 15, "\(character) \(poses[i]) vs \(poses[j])")
                }
            }
        }
    }

    @Test("At menu-bar size the body fills its box and has no hairline detail")
    func barMarkIsBigAndSimple() {
        for character in Self.characters {
            let image = Self.pixels(character, .awake, at: 0.5)
            let inked = image.filter { $0 != 0 }.count
            // The arch is the airiest of the three, with a hollow under it;
            // even so a third of the box, where the old drawing's margins
            // left it under a quarter.
            #expect(Double(inked) / Double(22 * 22) > 0.32, "\(character) fills \(Double(inked) / 484)")
            // Rows and columns it reaches: nearly the whole box both ways.
            let rows = Set(image.indices.filter { image[$0] != 0 }.map { $0 / 22 })
            #expect(rows.count >= 17, "\(character) spans \(rows.count) rows")
        }
    }

    @Test("In the bar Clawd is exactly the size he was in 0.5.0; the other marks are the larger ones")
    func barSizes() {
        #expect(MascotCharacter.clawd.menuBarSize == 20)
        for character in [MascotCharacter.floatBot, .starBuddy, .cloudGhost, .bot] {
            #expect(character.menuBarSize == 22)
        }
        // His sprite is drawn in the same square box and the same grid as
        // then: 51 x 36 frames, fitted in 20 points.
        #expect(ClawdFrames.frame(for: .awake, at: 0, colour: true)?.size == NSSize(width: 51, height: 36))
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

    /// The marks at the size and density they really have in the menu bar,
    /// beside the same pixels enlarged without smoothing — what a person sees
    /// at arm's length, and what the eye has to make out. `VIGIA_BAR_SCALE`
    /// is the display's backing scale (1 on a plain 1080p screen, 2 on Retina)
    /// and `VIGIA_BAR_SIZE` the mark's size in points.
    @Test("Menu-bar sheet, when asked for")
    func menuBarSheet() throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIA_CAPTURE_DIR"] else { return }
        let env = ProcessInfo.processInfo.environment
        let scale = Double(env["VIGIA_BAR_SCALE"] ?? "") ?? 1
        let points = Double(env["VIGIA_BAR_SIZE"] ?? "") ?? 22
        let name = env["VIGIA_BAR_NAME"] ?? "barra"
        let poses: [MascotPose] = [.type, .thinking, .waiting, .celebrate, .awake, .coffee, .sleep, .tired, .error]
        let zoom = 6.0

        func strip(_ character: MascotCharacter, dark: Bool) throws -> NSImage {
            let row = HStack(spacing: 6) {
                ForEach(poses, id: \.self) { pose in
                    Canvas { context, size in
                        VectorMascots.draw(character, pose: pose, time: 1.3, colour: true, in: &context, size: size)
                    }
                    .frame(width: points, height: points)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(dark ? Color(white: 0.13) : Color(white: 0.92))
            .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: row)
            renderer.scale = scale
            return try #require(renderer.nsImage)
        }

        var rows: [NSImage] = []
        for character in Self.characters {
            for dark in [false, true] { rows.append(try strip(character, dark: dark)) }
        }
        let width = rows.map(\.size.width).max() ?? 0
        let sheet = VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Image(nsImage: row).interpolation(.none).resizable()
                    .frame(width: width * zoom, height: row.size.height * zoom)
            }
        }
        .padding(8).background(Color.gray)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appending(path: "mascotas-\(name).png"))
    }

    /// The status item as the app really draws it — `MenuBarMascotsView`, the
    /// view the bar hosts — in a hosting view at the display's own scale, for
    /// a few states the store can really be in.
    @Test("The real menu-bar item, when asked for")
    func realItem() throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIA_CAPTURE_DIR"] else { return }
        let env = ProcessInfo.processInfo.environment
        let scale = Double(env["VIGIA_BAR_SCALE"] ?? "") ?? 1
        let name = env["VIGIA_BAR_NAME"] ?? "item"
        let accounts: [Provider] = [.claudeCode, .antigravity, .codex, .grok]
        let marks = Dictionary(uniqueKeysWithValues: accounts.map { (AccountKey($0).id, true) })
        let star = env["VIGIA_BAR_STAR"] == "1"
        let settings = AppSettings(enabledAccounts: Set(accounts.map(\.rawValue)), botMarks: marks,
                                   mascotCharacters: star ? [AccountKey(.antigravity).id: MascotCharacter.starBuddy.rawValue] : [:])
        settings.menuBarWorkingOnly = false

        let states: [(String, Set<Provider>, [Provider: String])] = [
            ("reposo", [], [:]),
            ("trabajando", [.claudeCode, .antigravity, .codex, .grok], [.claudeCode: "Editing", .antigravity: "Running command", .codex: "Searching", .grok: "Editing"]),
            ("pensando", [.claudeCode, .antigravity, .codex, .grok], [:])
        ]
        var rows: [NSImage] = []
        for (_, running, labels) in states {
            let monitor = AgentActivityMonitor { _ in [:] }
            let store = UsageStore(settings: settings, activity: monitor)
            monitor.adoptDemo(running: running, labels: labels,
                              startedAt: Dictionary(uniqueKeysWithValues: running.map { ($0, Date().addingTimeInterval(-60)) }))
            let host = NSHostingView(rootView: MenuBarMascotsView(settings: settings, store: store))
            host.appearance = NSAppearance(named: .aqua)
            let size = host.fittingSize
            host.frame = NSRect(origin: .zero, size: NSSize(width: size.width + 8, height: 24))
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let pixelsWide = Int(host.frame.width * scale), pixelsHigh = Int(host.frame.height * scale)
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = host.frame.size
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = NSImage(size: host.frame.size)
            image.addRepresentation(rep)
            rows.append(image)
        }
        let zoom = 6.0
        let sheet = VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Image(nsImage: row).interpolation(.none).resizable()
                    .frame(width: row.size.width * zoom, height: row.size.height * zoom)
                    .background(Color(white: 0.92))
            }
        }
        .padding(8).background(Color.gray)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appending(path: "item-\(name).png"))
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
