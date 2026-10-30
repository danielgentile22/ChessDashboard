import Foundation
import Observation

/// The Trends screen: rating, win rate, and activity over time. The activity
/// calendar, the dual-line rating chart (Official and Live), cumulative win
/// rate, Games per month, win rate by day of week, Game length, results by
/// time control, the fatigue check, and the upset tracker.
@MainActor @Observable
public final class TrendsModel {
	public let resource = ScreenResource<API.TrendsPayload>()
	private let context: ScreenContext
	/// The calendar chart dates are placed in (the device's, or UTC in tests).
	private let chartCalendar: Calendar

	public init(context: ScreenContext, calendar: Calendar = .current) {
		self.context = context
		self.chartCalendar = calendar
	}

	public func load() async {
		await resource.load(Endpoints.getTrends(filters: context.filters.state), in: context)
	}

	public var payload: API.TrendsPayload? { resource.value }

	/// No Games match the filters: the screen shows the empty state.
	public var isEmpty: Bool { payload?.gamesCount == 0 }

	private func date(_ text: String?) -> Date? { ChartDates.day(text, calendar: chartCalendar) }

	// MARK: Rating chart

	public struct RatingPoint: Hashable, Sendable, Identifiable {
		public let id: Int
		public let date: Date
		public let rating: Int
		/// The Rated Event for a Live point; "" otherwise.
		public let detail: String
		/// The Live Rating before the Section; nil for the first Section ever.
		public let preRating: Int?
	}

	public struct TrendPoint: Hashable, Sendable, Identifiable {
		public let id: Int
		public let date: Date
		public let value: Double
	}

	public struct RatingChart: Hashable, Sendable {
		public let mode: API.TrendsRatingChartMode
		/// The active lens's line is full strength; the other recedes.
		public let emphasized: API.Lens
		public let official: [RatingPoint]
		public let live: [RatingPoint]
		public let typed: [RatingPoint]
		public let trend: [TrendPoint]
		public var isEmpty: Bool { official.isEmpty && live.isEmpty && typed.isEmpty }
		public var emptyMessage: String {
			mode == .uscf ? "No rating data in this date range" : "No rating data"
		}
	}

	public var ratingChart: RatingChart {
		guard let chart = payload?.ratingChart else {
			return RatingChart(mode: .typed, emphasized: .official, official: [], live: [], typed: [], trend: [])
		}
		let official = chart.official.enumerated().compactMap { i, p -> RatingPoint? in
			guard let d = date(p.month), let r = p.rating else { return nil }
			return RatingPoint(id: i, date: d, rating: r, detail: "", preRating: nil)
		}
		let live = chart.live.enumerated().compactMap { i, p -> RatingPoint? in
			guard let d = date(p.endDate), let r = p.rating else { return nil }
			return RatingPoint(id: i, date: d, rating: r, detail: p.eventName, preRating: p.preRating)
		}
		let typed = chart.typed.enumerated().compactMap { i, p -> RatingPoint? in
			guard let d = date(p.date), let r = p.rating else { return nil }
			return RatingPoint(id: i, date: d, rating: r, detail: "", preRating: nil)
		}
		let trend = chart.typed.enumerated().compactMap { i, p -> TrendPoint? in
			guard let d = date(p.date), let t = p.trend else { return nil }
			return TrendPoint(id: i, date: d, value: t)
		}
		return RatingChart(
			mode: chart.mode, emphasized: chart.emphasized, official: official, live: live, typed: typed,
			trend: trend)
	}

	/// What a finger on the rating chart reads.
	public struct Readout: Hashable, Sendable {
		public struct Line: Hashable, Sendable {
			public let series: String
			public let value: String
			public let detail: String
		}
		public let date: Date
		public let lines: [Line]
	}

	/// The nearest Live Rating or typed rating, and the Official Rating the
	/// drawn step line shows at the same x (the last supplement on or before
	/// it). The rule is drawn at the nearest point, so the Official Rating is
	/// read there too, never at the raw finger position; before the first
	/// supplement there is no Official line, so no Official Rating.
	public func ratingReadout(at date: Date) -> Readout? {
		let chart = ratingChart
		let live = ChartDates.nearest(chart.live, to: date, by: \.date)
		let typed = ChartDates.nearest(chart.typed, to: date, by: \.date)
		let anchor = typed?.date ?? live?.date ?? date
		var lines: [Readout.Line] = []
		if let official = chart.official.last(where: { $0.date <= anchor }) {
			lines.append(.init(series: "Official Rating", value: RatingFormat.whole(official.rating), detail: ""))
		}
		if let live {
			let from = live.preRating.map { "from \(RatingFormat.whole($0))" } ?? "first rated Section"
			lines.append(.init(
				series: "Live Rating", value: RatingFormat.whole(live.rating), detail: "\(live.detail), \(from)"))
		}
		if let typed {
			lines.append(.init(series: "Rating", value: RatingFormat.whole(typed.rating), detail: ""))
		}
		guard !lines.isEmpty else { return nil }
		return Readout(date: anchor, lines: lines)
	}

	// MARK: Win rate

	public struct WinRatePoint: Hashable, Sendable, Identifiable {
		public let id: Int
		public let date: Date
		public let pct: Double
		public let wins: Int
		public let games: Int
	}

	public var winRate: [WinRatePoint] {
		(payload?.winRate ?? []).enumerated().compactMap { i, p in
			date(p.date).map {
				WinRatePoint(id: i, date: $0, pct: p.winRatePct, wins: p.cumWins, games: p.cumGames)
			}
		}
	}

	public struct ValueReadout: Hashable, Sendable {
		public let date: Date
		public let value: String
		public let detail: String
	}

	public func winRateReadout(at date: Date) -> ValueReadout? {
		ChartDates.nearest(winRate, to: date, by: \.date).map { p in
			ValueReadout(
				date: p.date, value: Self.percent(p.pct),
				detail: "\(Self.count(p.wins, "win", "wins")) in \(Self.count(p.games, "Game", "Games"))")
		}
	}

	// MARK: Months and weekdays

	public struct MonthBar: Hashable, Sendable, Identifiable {
		public let date: Date
		public let label: String
		public let games: Int
		public let wins: Int
		public let winRate: String
		public var id: Date { date }
	}

	public var months: [MonthBar] {
		(payload?.gamesPerMonth ?? []).compactMap { m in
			date(m.yearMonth).map { d in
				MonthBar(
					date: d, label: Self.monthLabel(m.yearMonth), games: m.games, wins: m.wins,
					winRate: Self.percent(m.winRatePct))
			}
		}
	}

	public struct WeekdayBar: Hashable, Sendable, Identifiable {
		public let day: API.TrendsWeekdayDayOfWeek
		public let games: Int
		public let wins: Int
		public let pct: Double
		public var id: String { day.rawValue }
	}

	/// Monday first, like the web.
	public var weekdays: [WeekdayBar] {
		let order = API.TrendsWeekdayDayOfWeek.allCases
		return (payload?.winRateByWeekday ?? [])
			.sorted { order.firstIndex(of: $0.dayOfWeek)! < order.firstIndex(of: $1.dayOfWeek)! }
			.map { WeekdayBar(day: $0.dayOfWeek, games: $0.games, wins: $0.wins, pct: $0.winRatePct) }
	}

	// MARK: Activity calendar

	public struct CalendarCell: Hashable, Sendable, Identifiable {
		public let date: String
		/// Column: weeks since the Monday on or before Jan 1.
		public let week: Int
		/// Row: 0 is Monday.
		public let weekday: Int
		/// Net result clamped to -3...3: drives the color.
		public let intensity: Int
		/// The color-independent channel: "+" won on balance, "−" lost, "" even.
		public let glyph: String
		public let accessibilityLabel: String
		public let games: [API.TrendsCalendarGame]
		public var id: String { date }
	}

	public struct CalendarYear: Hashable, Sendable, Identifiable {
		public let year: Int
		public let summary: String
		/// Week columns the year spans (53 or 54).
		public let weeks: Int
		public let cells: [CalendarCell]
		public var id: Int { year }
	}

	public var calendar: [CalendarYear] {
		(payload?.calendar ?? []).map { y in
			let start = Self.firstMonday(of: y.year)
			let weeks = Self.utc.dateComponents([.day], from: start, to: Self.utcDay(y.year, 12, 31)).day! / 7 + 1
			let cells = y.days.compactMap { d -> CalendarCell? in
				guard let text = d.date, let day = ISODates.day(text) else { return nil }
				let offset = Self.utc.dateComponents([.day], from: start, to: day).day!
				let label = "\(text): \(Self.count(d.games, "Game", "Games")), "
					+ "\(Self.count(d.win, "win", "wins")), \(Self.count(d.draw, "draw", "draws")), "
					+ Self.count(d.loss, "loss", "losses")
				return CalendarCell(
					date: text, week: offset / 7, weekday: offset % 7, intensity: max(-3, min(3, d.net)),
					glyph: d.net > 0 ? "+" : d.net < 0 ? "−" : "", accessibilityLabel: label, games: d.gameList)
			}
			let summary = "\(Self.count(y.games, "Game", "Games")), \(Self.count(y.wins, "win", "wins")), "
				+ Self.count(y.losses, "loss", "losses")
			return CalendarYear(year: y.year, summary: summary, weeks: weeks, cells: cells)
		}
	}

	private static let utc: Calendar = {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = .gmt
		return c
	}()

	private static func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
		utc.date(from: DateComponents(year: year, month: month, day: day))!
	}

	private static func firstMonday(of year: Int) -> Date {
		let jan1 = utcDay(year, 1, 1)
		// Gregorian weekday: 1 is Sunday; days back to Monday.
		let back = (utc.component(.weekday, from: jan1) + 5) % 7
		return utc.date(byAdding: .day, value: -back, to: jan1)!
	}

	// MARK: Game length

	public struct LengthBin: Hashable, Sendable, Identifiable {
		public let start: Int
		public let width: Int
		public let outcome: API.Outcome
		public let count: Int
		/// Where this bar starts in its bin's stack (Wins, then Draws, then Losses).
		public let base: Int
		public var id: String { "\(start)-\(outcome.rawValue)" }
		public var label: String { width == 1 ? "\(start) moves" : "\(start) to \(start + width - 1) moves" }
	}

	/// Game lengths in bins of a round width (1, 2, 5, 10, or 20 moves),
	/// at most about 12 bins, per outcome.
	public var lengthBins: [LengthBin] {
		let lengths = payload?.gameLengths ?? []
		guard let longest = lengths.map(\.moves).max() else { return [] }
		let width = [1, 2, 5, 10, 20].first { longest / $0 < 12 } ?? 20
		var counts: [String: (Int, API.Outcome, Int)] = [:]
		for g in lengths {
			let start = g.moves / width * width
			let key = "\(start)-\(g.outcome.rawValue)"
			counts[key, default: (start, g.outcome, 0)].2 += 1
		}
		let order = API.Outcome.allCases
		let sorted = counts.values.sorted {
			($0.0, order.firstIndex(of: $0.1)!) < ($1.0, order.firstIndex(of: $1.1)!)
		}
		var stacked: [Int: Int] = [:]
		return sorted.map { start, outcome, count in
			let base = stacked[start, default: 0]
			stacked[start] = base + count
			return LengthBin(start: start, width: width, outcome: outcome, count: count, base: base)
		}
	}

	public struct AverageLength: Hashable, Sendable, Identifiable {
		public let outcome: API.Outcome
		public let label: String
		/// Full moves, one decimal.
		public let value: String
		public var id: String { label }
	}

	/// Mean full moves by outcome; an outcome with no Games is left out.
	public var averageLengths: [AverageLength] {
		guard let a = payload?.averageLength else { return [] }
		let all: [(API.Outcome, String, Double?)] = [(.win, "Wins", a.win), (.draw, "Draws", a.draw), (.loss, "Losses", a.loss)]
		return all.compactMap { outcome, label, value in
			value.map { AverageLength(outcome: outcome, label: label, value: String(format: "%.1f", $0)) }
		}
	}

	// MARK: Playing conditions

	public struct TimeControlRow: Hashable, Sendable, Identifiable {
		public let id: Int
		public let label: String
		public let speed: API.TrendsTimeControlSpeed
		public let games: Int
		public let win: Int
		public let draw: Int
		public let loss: Int
		public let winRate: String
	}

	public var timeControls: [TimeControlRow] {
		(payload?.timeControls ?? []).enumerated().map { i, t in
			TimeControlRow(
				id: i, label: t.timeControl.isEmpty ? "(not recorded)" : t.timeControl, speed: t.speed,
				games: t.games, win: t.win, draw: t.draw, loss: t.loss, winRate: Self.percent(t.winRatePct))
		}
	}

	public struct RoundBar: Hashable, Sendable, Identifiable {
		public let round: Int
		public let label: String
		public let scorePct: Double
		public let games: Int
		public let win: Int
		public let draw: Int
		public let loss: Int
		/// Fewer than 3 Games: dimmed, "too few to conclude".
		public let reliable: Bool
		public var id: Int { round }
	}

	public var rounds: [RoundBar] {
		(payload?.rounds ?? []).map { r in
			RoundBar(
				round: r.round, label: "Round \(r.round)", scorePct: r.scorePct, games: r.games, win: r.win,
				draw: r.draw, loss: r.loss, reliable: r.reliable)
		}
	}

	// MARK: Upsets

	public struct UpsetRow: Hashable, Sendable, Identifiable {
		public let gameId: API.GameId
		public let opponent: String
		public let date: String
		/// "1800 vs 1920": my rating, then theirs.
		public let ratings: String
		/// "+120" for a giant kill, "-80" for an upset loss.
		public let margin: String
		public var id: String { gameId }
	}

	public var giantKills: [UpsetRow] { (payload?.upsets.giantKills ?? []).map { Self.upset($0, sign: 1) } }
	public var upsetLosses: [UpsetRow] { (payload?.upsets.upsetLosses ?? []).map { Self.upset($0, sign: -1) } }

	private static func upset(_ u: API.TrendsUpset, sign: Int) -> UpsetRow {
		let g = u.game
		return UpsetRow(
			gameId: g.gameId, opponent: g.opponent, date: g.date ?? "Undated",
			ratings: "\(RatingFormat.whole(g.playerRating)) vs \(RatingFormat.whole(g.opponentRating))",
			margin: RatingFormat.change(sign * u.margin))
	}

	// MARK: Formatting

	static func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }

	static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

	static func monthLabel(_ yearMonth: String) -> String {
		let parts = yearMonth.split(separator: "-").compactMap { Int($0) }
		guard parts.count == 2, (1...12).contains(parts[1]) else { return yearMonth }
		let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
		return "\(names[parts[1] - 1]) \(parts[0])"
	}
}
