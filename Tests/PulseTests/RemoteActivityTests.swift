import Foundation
import Testing
@testable import Pulse

@Suite("Remote activity")
struct RemoteActivityTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("A tool call is working, named by the tool, and outlives a quiet minute")
    func toolCall() {
        var ledger = RemoteActivityLedger()
        ledger.record(source: "bot", event: "PreToolUse", tool: "Bash", at: t0)
        let state = ledger.state(now: t0.addingTimeInterval(120))
        #expect(state?.isWorking == true)
        #expect(state?.label == "Running command")
        #expect(ledger.state(now: t0.addingTimeInterval(400)) == nil)
    }

    @Test("The model's move expires sooner, and Stop ends the turn at once")
    func modelAndStop() {
        var ledger = RemoteActivityLedger()
        ledger.record(source: "bot", event: "UserPromptSubmit", tool: nil, at: t0)
        #expect(ledger.state(now: t0.addingTimeInterval(30))?.label == "Thinking…")
        #expect(ledger.state(now: t0.addingTimeInterval(100)) == nil)

        ledger.record(source: "bot", event: "PreToolUse", tool: "Read", at: t0)
        ledger.record(source: "bot", event: "Stop", tool: nil, at: t0.addingTimeInterval(1))
        #expect(ledger.state(now: t0.addingTimeInterval(2)) == nil)
    }

    @Test("Two sources are independent, and unknown events change nothing")
    func sources() {
        var ledger = RemoteActivityLedger()
        ledger.record(source: "a", event: "PreToolUse", tool: "Edit", at: t0)
        ledger.record(source: "b", event: "Stop", tool: nil, at: t0)
        ledger.record(source: "a", event: "test", tool: nil, at: t0.addingTimeInterval(1))
        #expect(ledger.state(now: t0.addingTimeInterval(5))?.label == "Editing")
    }

    @Test("The parser wants POST /activity, a capped body, and the whole of it")
    func parsing() {
        func req(_ line: String, _ headers: String, _ body: String) -> Data {
            Data("\(line)\r\n\(headers)\r\n\r\n\(body)".utf8)
        }
        let body = #"{"event":"Stop"}"#
        let good = req("POST /activity HTTP/1.1", "Authorization: Bearer abc\r\nContent-Length: \(body.utf8.count)", body)
        #expect(RemoteActivityReceiver.parse(good) == .request(authorization: "Bearer abc", body: Data(body.utf8)))

        #expect(RemoteActivityReceiver.parse(req("GET /activity HTTP/1.1", "", "")) == .rejected(404))
        #expect(RemoteActivityReceiver.parse(req("POST /other HTTP/1.1", "", "")) == .rejected(404))
        #expect(RemoteActivityReceiver.parse(req("POST /activity HTTP/1.1", "Content-Length: 99999", "")) == .rejected(413))
        #expect(RemoteActivityReceiver.parse(req("POST /activity HTTP/1.1", "Content-Length: 50", "short")) == .incomplete)
        #expect(RemoteActivityReceiver.parse(Data("POST /activity HTT".utf8)) == .incomplete)
    }

    @Test("Token comparison accepts only the exact token and never an empty one")
    func token() {
        #expect(RemoteActivityReceiver.constantTimeEqual("abc", "abc"))
        #expect(!RemoteActivityReceiver.constantTimeEqual("abc", "abd"))
        #expect(!RemoteActivityReceiver.constantTimeEqual("", ""))
    }
}
