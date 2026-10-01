// Modified for Vigía from Pulse (Apache-2.0).
// Clawd on the notch. Frames are the claude-status-bar sprites (MIT).
import AppKit
import SwiftUI

@MainActor
enum ClawdFrames {
    static let images: [NSImage] = clawdCrabFramePNGs.compactMap { encoded in
        guard let data = Data(base64Encoded: encoded), let image = NSImage(data: data) else { return nil }
        return adaptiveCrabFrame(image)
    }
}

struct ClawdMarkView: View {
    var isWorking: Bool
    var size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: isWorking ? 0.08 : 60)) { context in
            let frames = ClawdFrames.images
            if frames.isEmpty {
                Color.clear.frame(width: size, height: size)
            } else {
                let index = isWorking
                    ? Int(context.date.timeIntervalSinceReferenceDate / 0.08) % frames.count
                    : 0
                Image(nsImage: frames[index])
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        }
    }
}
