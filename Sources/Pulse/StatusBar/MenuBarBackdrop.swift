import AppKit
import Observation
import SwiftUI

/// What is behind the menu bar on each screen, so a mascot never sits on a
/// colour it cannot be seen against.
///
/// **Read from the wallpaper, not from the screen.** Looking at the pixels
/// that are really there needs Screen Recording permission, which is a lot to
/// ask for a mascot's colour. The bar is the wallpaper's top strip, blurred
/// and tinted a little, so the average of that strip under the right half of
/// the screen — where the status items live — is close enough to tell orange
/// from green. Dynamic wallpapers are read at the frame the system names.
///
/// **One answer, decided by the primary screen.** The status item is one
/// image; the system re-tints it for the other displays itself, so the
/// primary bar's backdrop is the one worth reading.
struct MenuBarColour: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = MenuBarColour(red: 1, green: 1, blue: 1)
    static let black = MenuBarColour(red: 0, green: 0, blue: 0)

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// WCAG contrast ratio, 1 (identical) to 21 (black on white).
    func contrast(with other: MenuBarColour) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent))
    }

    /// Below this a shape is lost against its ground. WCAG asks 3:1 for
    /// graphics; a mascot is big and solid, so a little under that will do.
    static let needed = 2.4

    /// A "redmean" colour distance, 0 to about 765. Luminance contrast alone
    /// calls orange on green invisible, though the eye separates them easily
    /// by hue; this is the cheap measure that does not.
    func distance(from other: MenuBarColour) -> Double {
        let mean = (red + other.red) / 2 * 255
        let dr = (red - other.red) * 255, dg = (green - other.green) * 255, db = (blue - other.blue) * 255
        return (((512 + mean) * dr * dr) / 256 + 4 * dg * dg + ((767 - mean) * db * db) / 256).squareRoot()
    }

    /// Far enough apart in hue, or in brightness, to be told apart.
    static let apart = 150.0

    func shows(on backdrop: MenuBarColour) -> Bool {
        contrast(with: backdrop) >= Self.needed || distance(from: backdrop) >= Self.apart
    }

    /// The colour to draw with: `preferred` when it can be seen on every
    /// backdrop, otherwise white or black, whichever is better on the worst
    /// one. With no backdrops known, `preferred` is left alone.
    static func legible(_ preferred: MenuBarColour, over backdrops: [MenuBarColour]) -> MenuBarColour {
        guard !backdrops.isEmpty else { return preferred }
        if backdrops.allSatisfy({ preferred.shows(on: $0) }) { return preferred }
        func worst(_ ink: MenuBarColour) -> Double { backdrops.map { ink.contrast(with: $0) }.min() ?? 21 }
        return worst(.white) >= worst(.black) ? .white : .black
    }
}

@MainActor
@Observable
final class MenuBarBackdrop {
    static let shared = MenuBarBackdrop()

    /// One colour per screen, empty until the first read or when no
    /// wallpaper could be read.
    private(set) var colours: [MenuBarColour] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var scan: Task<Void, Never>?

    func start() {
        guard observers.isEmpty else { return }
        let onChange: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: onChange))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onChange))
        // A wallpaper changed from System Settings posts nothing public.
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        guard scan == nil else { return }
        let screens = NSScreen.screens.map { screen -> Request in
            let url = NSWorkspace.shared.desktopImageURL(for: screen)
            return Request(url: url, size: screen.frame.size)
        }
        // The reading runs detached and takes nothing from `self`; only the
        // publishing, back on the main actor, touches it.
        scan = Task { @MainActor [weak self] in
            let found = await Task.detached(priority: .utility) {
                screens.compactMap(Self.sample)
            }.value
            guard let self else { return }
            self.scan = nil
            if found != self.colours { self.colours = found }
        }
    }

    // MARK: - Reading the wallpaper

    struct Request: Sendable {
        var url: URL?
        var size: CGSize
    }

    /// Points of menu bar, and the share of the screen's width from the right
    /// that the status items occupy.
    nonisolated static let barHeight = 26.0
    nonisolated static let rightShare = 0.55

    /// The average colour of the bar's strip of `request`'s wallpaper.
    nonisolated static func sample(_ request: Request) -> MenuBarColour? {
        guard let url = request.url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary),
              request.size.width > 0, request.size.height > 0
        else { return nil }

        let iw = Double(image.width), ih = Double(image.height)
        // Fill (the default) scales the image to cover the screen and crops
        // the middle; the other modes are read the same way, which is right
        // for the common case and merely close for the rest.
        let scale = max(request.size.width / iw, request.size.height / ih)   // points per image pixel
        let visibleW = request.size.width / scale
        let visibleH = request.size.height / scale
        let x0 = (iw - visibleW) / 2
        let y0 = (ih - visibleH) / 2
        let rect = CGRect(
            x: x0 + visibleW * (1 - rightShare), y: y0,
            width: visibleW * rightShare, height: max(1, barHeight / scale)
        ).intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1, let strip = image.cropping(to: rect) else { return nil }

        // Drawn into a 1×1 so the system does the averaging.
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return MenuBarColour(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    // MARK: - What to draw with

    /// The menu bar's own ink, which macOS picks from the wallpaper's
    /// brightness: the best guess for anything drawn "in the system colour".
    var systemInk: MenuBarColour {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
    }

    /// The bar the status item is really drawn on: the primary display's.
    /// macOS adapts the same image to the other displays' bars by itself —
    /// measured on an orange bar, an orange mark came out pale cream — so
    /// forcing white everywhere because *one* bar is orange took the colour
    /// away from the green bar where it showed fine.
    private var primary: [MenuBarColour] { colours.prefix(1).map { $0 } }

    /// `preferred` if it can be seen on the primary bar, else white or black.
    func legible(_ preferred: Color) -> Color {
        MenuBarColour.legible(MenuBarColour(preferred), over: primary).color
    }

    /// The system ink, unless it is lost against some screen's bar — and then
    /// white or black. Nil means "leave it to the system".
    func inkOverride() -> Color? {
        let system = systemInk
        let chosen = MenuBarColour.legible(system, over: primary)
        return chosen == system ? nil : chosen.color
    }
}
