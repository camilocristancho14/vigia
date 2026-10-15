// Modified for Vigía from Pulse (Apache-2.0).
// Clawd. The walking frames are the claude-status-bar sprites (MIT); the other
// poses are drawn on the same grid in `ClawdSprites`.
import AppKit
import SwiftUI

@MainActor
enum ClawdFrames {
    /// The walking GIF, in the colours it was drawn in.
    static let walkColour: [NSImage] = clawdCrabFramePNGs.compactMap { encoded in
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return NSImage(data: data)
    }

    /// The same frames as one-ink templates, which take the colour of the
    /// surface they are on. The default on the notch.
    static let images: [NSImage] = walkColour.map { adaptiveCrabFrame($0) }

    private static let poseColour = ClawdSprites.frames
    private static let poseAdaptive = ClawdSprites.frames.mapValues { frames in frames.map { adaptiveCrabFrame($0) } }

    /// How often a pose needs a new frame; a still pose asks rarely.
    static func interval(for pose: MascotPose) -> TimeInterval {
        switch pose {
        case .run: 0.05
        case .type, .play: 0.16
        case .coffee, .waiting, .celebrate: 0.25
        case .awake, .thinking: 0.2
        case .sleep, .stretch: 0.45
        case .tired, .waking: 0.3
        case .spent, .error: 0.35
        case .testing: 0.15
        case .longCommand: 0.25
        }
    }

    /// Each pose's frames and how long each is held, for the ones that simply
    /// cycle. Coffee and awake keep their own beats below.
    private static let cycles: [MascotPose: (key: String, step: TimeInterval)] = [
        .type: ("type", 0.16), .sleep: ("sleep", 0.9), .tired: ("tired", 0.3), .spent: ("spent", 0.35),
        .thinking: ("thinking", 0.45), .waiting: ("waiting", 0.4), .celebrate: ("celebrate", 0.25),
        .stretch: ("stretch", 1.1), .play: ("play", 0.22), .error: ("error", 0.7),
        .testing: ("testing", 0.3), .longCommand: ("hourglass", 0.6)
    ]

    /// The frame to show `seconds` into a pose.
    static func frame(for pose: MascotPose, at seconds: TimeInterval, colour: Bool) -> NSImage? {
        let walk = colour ? walkColour : images
        let sets = colour ? poseColour : poseAdaptive
        switch pose {
        case .run:
            guard !walk.isEmpty else { return nil }
            return walk[Int(seconds / 0.05) % walk.count]
        case .coffee:
            guard let frames = sets["coffee"] else { return walk.first }
            // Steam drifts, then a sip, then back to steaming.
            let beat = Int((seconds.truncatingRemainder(dividingBy: 4)) / 0.5)
            return frames[[0, 1, 0, 1, 2, 2, 0, 1][beat]]
        case .awake:
            guard let frames = sets["awake"] else { return walk.first }
            // Eyes shut for a moment every four seconds or so.
            return frames[seconds.truncatingRemainder(dividingBy: 4.2) >= 4.0 ? 1 : 0]
        case .waking:
            guard let frames = sets["waking"] else { return walk.first }
            // Up from a crouch, eyes opening, once a cycle of three seconds.
            let beat = seconds.truncatingRemainder(dividingBy: 3)
            return frames[beat < 1 ? 0 : beat < 1.8 ? 1 : 2]
        case .type, .sleep, .tired, .spent, .thinking, .waiting, .celebrate, .stretch, .play, .error,
             .testing, .longCommand:
            guard let cycle = cycles[pose], let frames = sets[cycle.key] else { return walk.first }
            return frames[Int(seconds / cycle.step) % frames.count]
        }
    }
}

struct ClawdMarkView: View {
    var pose: MascotPose
    /// Claude's own orange, rather than the ink of the surface behind it.
    var colour = false
    var size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: ClawdFrames.interval(for: pose))) { context in
            if let frame = ClawdFrames.frame(
                for: pose, at: context.date.timeIntervalSinceReferenceDate, colour: colour
            ) {
                Image(nsImage: frame)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Color.clear.frame(width: size, height: size)
            }
        }
    }
}
