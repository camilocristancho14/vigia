import Foundation
import Testing
@testable import Pulse

@Suite("agy login and Google's quota reply")
struct AgyLoginTests {
    @Test("agy's saved token is read, with Go's nanosecond expiry")
    func parsesSavedToken() throws {
        let json = #"{"token":{"access_token":"a","token_type":"Bearer","refresh_token":"r","expiry":"2026-10-13T09:19:20.060509-05:00"},"auth_method":"consumer"}"#
        let saved = try #require(AgyLogin.parse(Data(json.utf8)))
        #expect(saved.accessToken == "a")
        #expect(saved.refreshToken == "r")
        #expect(saved.expiry == Date(timeIntervalSince1970: 1_791_901_160.060))
    }

    @Test("A file with neither token is no login")
    func emptyIsNil() {
        #expect(AgyLogin.parse(Data(#"{"token":{}}"#.utf8)) == nil)
        #expect(AgyLogin.parse(Data("nope".utf8)) == nil)
    }

    @Test("A still-valid saved token is used without asking Google")
    func usesValidToken() async {
        let saved = AgyLogin.Saved(accessToken: "a", refreshToken: nil, expiry: Date().addingTimeInterval(600))
        let outcome = await AgyLogin.Renewal().accessToken(for: saved, home: URL(fileURLWithPath: "/nonexistent"))
        #expect(outcome == .usable("a"))
    }

    @Test("No refresh token and a lapsed access token is a rejected login")
    func lapsedWithoutRefresh() async {
        let saved = AgyLogin.Saved(accessToken: "a", refreshToken: nil, expiry: Date().addingTimeInterval(-10))
        let outcome = await AgyLogin.Renewal().accessToken(for: saved, home: URL(fileURLWithPath: "/nonexistent"))
        #expect(outcome == .rejected)
    }

    @Test("Google's reply, groups at the top level, gives the same windows")
    func topLevelGroups() throws {
        let json = #"{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","window":"weekly","resetTime":"2026-10-20T13:20:14Z","remainingFraction":0.73},{"bucketId":"gemini-5h","window":"5h","resetTime":"2026-10-17T19:07:19Z","remainingFraction":1}]}]}"#
        let reply = try JSONDecoder().decode(AntigravityUsageService.Reply.self, from: Data(json.utf8))
        let windows = AntigravityUsageService.windows(from: reply)
        #expect(windows.map(\.id) == ["gemini-5h", "gemini-weekly"])
        #expect(windows.first?.scope == "Gemini")
    }
}
