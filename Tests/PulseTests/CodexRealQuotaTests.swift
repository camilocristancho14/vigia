import Foundation
import Testing
@testable import Pulse

@Suite("Codex captured app server quota")
struct CodexRealQuotaTests {
    @Test("Free plan remains exhausted while available credits are disclosed")
    func freePlanCredits() throws {
        let url = try #require(Bundle.module.url(forResource: "codex-app-server-real", withExtension: "jsonl", subdirectory: "Fixtures"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = try text.split(whereSeparator: \.isNewline).map { line -> [String: Any] in
            try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        let quota = try #require(rows.first { $0["id"] as? Int == 3 }?["result"] as? [String: Any])
        let usage = CodexUsageService.parseAppServerResponse(quota)

        #expect(usage.plan == "Free · credits available")
        #expect(usage.creditBalance == "482")
        #expect(usage.windows.count == 1)
        #expect(usage.windows[0].kind == .other(seconds: 30 * 86_400))
        #expect(usage.windows[0].usedFraction == 1)
        #expect(usage.windows[0].isExhausted)
        #expect(usage.windows[0].resetsAt != nil)
    }
}
