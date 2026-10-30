import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Display rules")
struct DisplayTests {
	@Test("ratings are whole numbers")
	func ratings() {
		#expect(RatingFormat.whole(1523) == "1523")
		#expect(RatingFormat.whole(1522.5) == "1523")
		#expect(RatingFormat.whole(1522.49) == "1522")
		#expect(RatingFormat.whole(nil as Int?) == "Unrated")
		#expect(RatingFormat.change(12) == "+12")
		#expect(RatingFormat.change(-8) == "-8")
		#expect(RatingFormat.change(0.4) == "0")
	}

	@Test("mine and engine Tags read differently")
	func tags() {
		let mine = TagDisplay(API.Tag(name: "time-trouble", source: .mine))
		let engine = TagDisplay(API.Tag(name: "tactical-blunder", source: .engine))
		#expect(mine.text == "#time-trouble" && mine.style == .mine && mine.symbol == nil)
		#expect(engine.style == .engine && engine.symbol != nil)
		#expect(engine.accessibilityLabel == "Engine Tag tactical-blunder")
	}

	@Test("freshness per source, from the meta fixtures")
	func freshness() throws {
		let meta = try JSONDecoder().decode(API.MetaPayload.self, from: Repo.fixture("getMeta"))
		let now = try #require(ISODates.timestamp("2026-01-01T00:00:30Z"))
		let lines = FreshnessSummary(meta.freshness, now: now).lines
		#expect(lines.map(\.source) == ["Lichess", "USCF"])
		#expect(lines.allSatisfy { $0.text == "Synced just now" && !$0.isWarning })

		let lichessOnly = try JSONDecoder().decode(
			API.MetaPayload.self, from: Repo.fixture("getMeta.lichess_only"))
		#expect(FreshnessSummary(lichessOnly.freshness, now: now).lines.map(\.source) == ["Lichess"])
	}

	@Test("USCF unavailable since and the Lichess cache fallback are warnings")
	func freshnessWarnings() {
		let f = API.MetaFreshness(
			lichess: .init(cachedAt: "2026-01-01T00:00:00.123456Z", source: .cache, syncedAt: nil),
			uscf: .init(available: true, enabled: true, syncedAt: nil, unavailableSince: "2026-01-01 00:00 UTC"))
		let lines = FreshnessSummary(f, now: ISODates.timestamp("2026-01-01T02:00:01Z")!).lines
		#expect(lines[0].isWarning && lines[0].text == "Couldn't reach Lichess. Showing Games cached 2 hours ago")
		#expect(lines[1] == .init(source: "USCF", text: "USCF unavailable since 2026-01-01 00:00 UTC", isWarning: true))
	}

	@Test("web links point at the matching dashboard page")
	func webLinks() {
		let api = URL(string: "https://chess-dashboard.fly.dev/api/v1/")!
		#expect(WebPage.overview.url(apiBaseURL: api).absoluteString == "https://chess-dashboard.fly.dev/")
		#expect(WebPage.reconciliation.url(apiBaseURL: api).absoluteString == "https://chess-dashboard.fly.dev/reconciliation")
		#expect(WebPage.game("abc").url(apiBaseURL: api).absoluteString == "https://chess-dashboard.fly.dev/game/abc")
		#expect(WebPage.lessonsReview(opponent: "uscf-1").url(apiBaseURL: api).absoluteString
			== "https://chess-dashboard.fly.dev/lessons?review=1&opponent=uscf-1")
		let local = URL(string: "http://localhost:8050/api/v1/")!
		#expect(WebPage.trends.url(apiBaseURL: local).absoluteString == "http://localhost:8050/trends")
	}

	@Test("theme tokens carry the web's values")
	func theme() {
		#expect(Theme.win == ThemeColor(red: 48, green: 209, blue: 88, alpha: 1))
		#expect(Theme.border.alpha == 0.5)
	}
}
