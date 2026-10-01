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
        case .type: 0.16
        case .coffee: 0.25
        case .awake: 0.2
        case .sleep: 0.45
        case .tired: 0.3
        case .spent: 0.35
        }
    }

    /// The frame to show `seconds` into a pose.
    static func frame(for pose: MascotPose, at seconds: TimeInterval, colour: Bool) -> NSImage? {
        let walk = colour ? walkColour : images
        let sets = colour ? poseColour : poseAdaptive
        switch pose {
        case .run:
            guard !walk.isEmpty else { return nil }
            return walk[Int(seconds / 0.05) % walk.count]
        case .type:
            guard let frames = sets["type"] else { return walk.first }
            return frames[Int(seconds / 0.16) % frames.count]
        case .coffee:
            guard let frames = sets["coffee"] else { return walk.first }
            // Steam drifts, then a sip, then back to steaming.
            let beat = Int((seconds.truncatingRemainder(dividingBy: 4)) / 0.5)
            return frames[[0, 1, 0, 1, 2, 2, 0, 1][beat]]
        case .awake:
            guard let frames = sets["awake"] else { return walk.first }
            // Eyes shut for a moment every four seconds or so.
            return frames[seconds.truncatingRemainder(dividingBy: 4.2) >= 4.0 ? 1 : 0]
        case .sleep:
            guard let frames = sets["sleep"] else { return walk.first }
            return frames[Int(seconds / 0.9) % frames.count]
        case .tired:
            guard let frames = sets["tired"] else { return walk.first }
            return frames[Int(seconds / 0.3) % frames.count]
        case .spent:
            guard let frames = sets["spent"] else { return walk.first }
            return frames[Int(seconds / 0.35) % frames.count]
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
