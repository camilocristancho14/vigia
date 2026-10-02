import Foundation
import Testing
@testable import Pulse

@Suite("Menu bar backdrop")
struct MenuBarBackdropTests {
    private let orange = MenuBarColour(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
    private let orangeBar = MenuBarColour(red: 234 / 255, green: 130 / 255, blue: 48 / 255)
    private let greenBar = MenuBarColour(red: 84 / 255, green: 127 / 255, blue: 3 / 255)

    @Test("Contrast is 1 for the same colour and 21 for black on white")
    func ratio() {
        #expect(abs(MenuBarColour.white.contrast(with: .white) - 1) < 0.001)
        #expect(abs(MenuBarColour.white.contrast(with: .black) - 21) < 0.01)
    }

    @Test("A colour that shows is kept, one lost against a screen becomes white or black")
    func legible() {
        // Orange on green is told apart by hue, though not by brightness.
        #expect(MenuBarColour.legible(orange, over: [greenBar]) == orange)
        // The orange crab is invisible on an orange bar.
        let swapped = MenuBarColour.legible(orange, over: [orangeBar])
        #expect(swapped == .white || swapped == .black)
        #expect(swapped.contrast(with: orangeBar) >= MenuBarColour.needed)
        #expect(!orange.shows(on: orangeBar))
    }

    @Test("It has to read on the worst screen, so green and orange together give black")
    func worstScreen() {
        // Orange shows on the green bar but not the orange one, so it is out.
        #expect(MenuBarColour.legible(orange, over: [greenBar, orangeBar]) == .black)
    }

    @Test("Nothing known about the screens leaves the colour alone")
    func unknown() {
        #expect(MenuBarColour.legible(orange, over: []) == orange)
    }
}
