import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Trends screen")
@MainActor
struct TrendsModelTests {
	private static let utc: Calendar = {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = .gmt
		return c
	}()

	private func loaded(variant: String? = nil, api: FixtureAPIClient = FixtureAPIClient(directory: Repo.fixtures))
		async -> TrendsModel
	{
		api.use(variant: variant, for: "getTrends")
		let model = TrendsModel(context: makeEnvironment(api: api).context!, calendar: Self.utc)
		await model.load()
		return model
	}

	private func day(_ text: String) -> Date { ChartDates.day(text, calendar: Self.utc)! }

	@Test("the dual-line rating chart: Official steps and Live per Section, lens emphasized")
	func ratingChart() async {
		let chart = await loaded().ratingChart
		#expect(chart.mode == .uscf && chart.emphasized == .official && !chart.isEmpty)
		#expect(chart.official.count == 12 && chart.live.count == 25 && chart.typed.isEmpty)
		#expect(chart.official.first?.rating == 1800)
		#expect(chart.live.first?.detail == "TEST OPEN JANUARY")
	}

	@Test("touch to read the rating chart: the Official step in force and the nearest Section")
	func ratingReadout() async throws {
		let model = await loaded()
		let readout = try #require(model.ratingReadout(at: day("2024-01-08")))
		#expect(readout.lines.map(\.series) == ["Official Rating", "Live Rating"])
		#expect(readout.lines[0].value == "1800")
		#expect(readout.lines[1].value == "1800" && readout.lines[1].detail == "TEST OPEN JANUARY, from 1782")
	}

	@Test("USCF off: the chart degrades to typed header ratings with the trend line")
	func typedChart() async throws {
		let model = await loaded(variant: "lichess_only")
		let chart = model.ratingChart
		#expect(chart.mode == .typed && chart.typed.count == 4 && chart.official.isEmpty)
		#expect(chart.trend.count == 4)
		let readout = try #require(model.ratingReadout(at: day("2024-01-07")))
		#expect(readout.lines.map(\.series) == ["Rating"] && readout.lines[0].value == "1800")
	}

	@Test("cumulative win rate, touch to read")
	func winRate() async throws {
		let model = await loaded()
		#expect(model.winRate.count == 4)
		let readout = try #require(model.winRateReadout(at: day("2024-01-07")))
		#expect(readout.value == "33.3%" && readout.detail == "1 win in 3 Games")
	}

	@Test("games per month and win rate by day of week, Monday first")
	func months() async {
		let model = await loaded()
		#expect(model.months.map(\.label) == ["Jan 2024", "Jun 2024"])
		#expect(model.months.map(\.games) == [3, 4])
		#expect(model.weekdays.map(\.day) == [.sat, .sun])
	}

	@Test("the activity calendar: one cell per played day, net glyph, week and weekday")
	func calendar() async throws {
		let years = await loaded().calendar
		let year = try #require(years.first)
		#expect(year.year == 2024 && year.summary == "7 Games, 4 wins, 1 loss")
		let first = try #require(year.cells.first)
		// 2024-01-06 is a Saturday in the week starting Monday 2024-01-01.
		#expect(first.week == 0 && first.weekday == 5)
		#expect(first.glyph == "+" && first.intensity == 1)
		#expect(first.accessibilityLabel == "2024-01-06: 2 Games, 1 win, 1 draw, 0 losses")
		#expect(first.games.map(\.opponent) == ["Opponent A", "Opponent B"])
		#expect(year.weeks == 53)
	}

	@Test("results by time control and the fatigue check")
	func conditions() async {
		let model = await loaded()
		#expect(model.timeControls.map(\.label) == ["40/80, SD30; +30", "30+5", "(not recorded)"])
		#expect(model.rounds.map(\.label) == ["Round 1", "Round 2", "Round 3", "Round 4"])
		#expect(model.rounds.allSatisfy { !$0.reliable })
	}

	@Test("game length: binned by outcome, and the averages")
	func lengths() async {
		let model = await loaded()
		let bins = model.lengthBins
		#expect(bins.reduce(0) { $0 + $1.count } == 7)
		// Bins of one move; in the 4-move bin the Draw stacks on the two Wins.
		#expect(bins.filter { $0.start == 4 }.map(\.base) == [0, 2])
		#expect(bins.first?.label == "3 moves")
		#expect(model.averageLengths.map(\.label) == ["Wins", "Draws", "Losses"])
		#expect(model.averageLengths.map(\.value) == ["4.2", "3.5", "3.0"])
	}

	@Test("the upset tracker: giant kills with signed margins")
	func upsets() async throws {
		let model = await loaded()
		let kill = try #require(model.giantKills.first)
		#expect(kill.gameId == "chap0001" && kill.margin == "+120")
		#expect(kill.ratings == "1800 vs 1920")
		#expect(model.upsetLosses.isEmpty)
	}

	@Test("the empty state: nothing to chart")
	func empty() async {
		let model = await loaded(variant: "empty")
		#expect(model.isEmpty && model.ratingChart.isEmpty)
		#expect(model.calendar.isEmpty && model.winRate.isEmpty && model.averageLengths.isEmpty)
		#expect(model.ratingReadout(at: .now) == nil)
	}

	@Test("offline: the cached Trends stay readable")
	func offline() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let env = makeEnvironment(api: api)
		await TrendsModel(context: env.context!).load()
		api.fail(with: .offline)
		let relaunched = TrendsModel(context: env.context!)
		await relaunched.load()
		#expect(relaunched.resource.isOffline && relaunched.winRate.count == 4)
	}
}
