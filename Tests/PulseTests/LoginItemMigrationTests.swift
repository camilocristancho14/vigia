import Foundation
import Testing
@testable import Pulse

/// Which launch agents under Pulse's old label Vigía takes over. The decision
/// only: nothing here touches ~/Library/LaunchAgents.
@Suite("Launch agent migration")
struct LoginItemMigrationTests {
    @Test("An agent that starts Vigía is taken over", arguments: [
        "/Applications/Vigia.app/Contents/MacOS/Vigia",
        "/Users/me/Applications/Vigia.app/Contents/MacOS/Vigia",
        "/Users/me/Downloads/vigia.app/Contents/MacOS/vigia",
        "/Users/me/Code/vigia/.build/debug/Pulse",
    ])
    func adopts(_ program: String) {
        #expect(LoginItem.legacyAgentBelongsToVigia(
            programArguments: [program],
            currentExecutable: "/Users/me/Code/vigia/.build/debug/Pulse"
        ))
    }

    @Test("An agent that starts something else is left alone", arguments: [
        "/Applications/Pulse.app/Contents/MacOS/Pulse",
        "/Users/me/Code/Pulse/.build/debug/Pulse",
        "/usr/local/bin/vigia-helper",
        "",
    ])
    func leaves(_ program: String) {
        #expect(!LoginItem.legacyAgentBelongsToVigia(
            programArguments: [program],
            currentExecutable: "/Applications/Vigia.app/Contents/MacOS/Vigia"
        ))
    }

    @Test("An agent without a program, or unreadable, is left alone")
    func unreadable() {
        #expect(!LoginItem.legacyAgentBelongsToVigia(programArguments: nil, currentExecutable: "/x/Vigia"))
        #expect(!LoginItem.legacyAgentBelongsToVigia(programArguments: [], currentExecutable: nil))
    }
}
