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

	@Test("percentages: whole, up to one decimal, spoken, share")
	func percents() {
		#expect(PercentFormat.whole(57.14) == "57%")
		#expect(PercentFormat.whole(42.5) == "43%")
		#expect(PercentFormat.upToOneDecimal(57.14) == "57.1%")
		#expect(PercentFormat.upToOneDecimal(50) == "50%")
		#expect(PercentFormat.spoken(66.6) == "67 percent")
		#expect(PercentFormat.share(1, of: 3) == "33%")
		#expect(PercentFormat.share(0, of: 0) == "0%")
	}

	@Test("a record reads in words, never W/D/L")
	func records() {
		#expect(RecordText.record(win: 3, draw: 1, loss: 2) == "3 wins, 1 draw, 2 losses")
		#expect(RecordText.record(win: 1, draw: 0, loss: 1) == "1 win, 0 draws, 1 loss")
		#expect(RecordText.recordWithGames(win: 3, draw: 1, loss: 2) == "3 wins, 1 draw, 2 losses, 6 Games")
		#expect(RecordText.games(1) == "1 Game")
	}

	@Test("touch to read picks the nearest point, ties to the earlier one")
	func nearestPoint() {
		let moves = [1.0, 2.0, 4.0]
		#expect(ChartSelection.nearest(moves, to: 3, by: { $0 }) == 2)
		#expect(ChartSelection.nearest(moves, to: 3.6, by: { $0 }) == 4)
		#expect(ChartSelection.nearest([Double](), to: 1, by: { $0 }) == nil)
		let day = ChartDates.day("2024-03-10")!
		let days = ["2024-03-01", "2024-03-12"].compactMap { ChartDates.day($0) }
		#expect(ChartDates.nearest(days, to: day, by: { $0 }) == days[1])
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
