import Charts
import ChessDashboardKit
import SwiftUI

/// Rating, win rate, and activity over time.
struct TrendsScreen: View {
	@Environment(AppEnvironment.self) private var env
	@State private var model: TrendsModel

	init(context: ScreenContext) { _model = State(initialValue: TrendsModel(context: context)) }

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { _ in
			ScrollView {
				LazyVStack(spacing: 14) {
					if model.isEmpty {
						NoGamesView()
					} else {
						ActivityCalendar(years: model.calendar)
						RatingChartCard(model: model)
						WinRateCard(model: model)
						MonthsCard(months: model.months)
						WeekdayCard(days: model.weekdays)
						LengthCard(bins: model.lengthBins, averages: model.averageLengths)
						TimeControlCard(rows: model.timeControls)
						RoundCard(rounds: model.rounds)
						UpsetCard(
							title: "Giant kills", subtitle: "Wins over higher-rated opponents",
							rows: model.giantKills, empty: "No wins over higher-rated opponents yet",
							color: Theme.win.color)
						UpsetCard(
							title: "Upset losses", subtitle: "Losses to lower-rated opponents",
							rows: model.upsetLosses, empty: "No losses to lower-rated opponents",
							color: Theme.loss.color)
					}
				}
				.padding()
			}
			.background(Theme.bg.color)
		}
		.screenChrome(title: "Trends", page: .trends, resource: model.resource)
		.task(id: env.filters.state) { await model.load() }
		.refreshable { await model.load() }
	}
}

/// The touch-to-read bubble over a chart.
private struct ReadoutBubble: View {
	let title: String
	let lines: [(String, String)]

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title).font(.caption2).foregroundStyle(Theme.muted.color)
			ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
				HStack(alignment: .firstTextBaseline, spacing: 4) {
					Text(line.0).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text.color)
					Text(line.1).font(.caption2).foregroundStyle(Theme.muted.color).lineLimit(2)
				}
			}
		}
		.padding(8)
		.background(Theme.bg.color.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
		.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border.color, lineWidth: 1))
		.frame(maxWidth: 220, alignment: .leading)
	}
}

private let shortDate = Date.FormatStyle(date: .abbreviated, time: .omitted)

// MARK: Activity calendar

private struct ActivityCalendar: View {
	let years: [TrendsModel.CalendarYear]
	@State private var selected: TrendsModel.CalendarCell?

	private let cell: CGFloat = 13
	private let gap: CGFloat = 3

	var body: some View {
		DashboardCard(title: "Activity", subtitle: "Green won on balance, red lost. Tap a day.") {
			if years.isEmpty {
				CardEmptyText("No dated Games in this filter")
			} else {
				ForEach(years) { year in
					VStack(alignment: .leading, spacing: 6) {
						HStack {
							Text(String(year.year)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text.color)
							Spacer()
							Text(year.summary).font(.caption).foregroundStyle(Theme.muted.color)
						}
						ScrollView(.horizontal, showsIndicators: false) {
							grid(year)
						}
						// Open on the latest played week.
						.defaultScrollAnchor(UnitPoint(x: latestWeek(year), y: 0))
					}
				}
				if let selected {
					VStack(alignment: .leading, spacing: 4) {
						Text(selected.accessibilityLabel).font(.caption).foregroundStyle(Theme.muted.color)
						ForEach(selected.games, id: \.gameId) { game in
							NavigationLink(value: GameRoute(gameID: game.gameId)) {
								HStack {
									Circle().fill(game.outcome.themeColor).frame(width: 8, height: 8)
									Text("\(game.outcome.rawValue) vs \(game.opponent)")
										.font(.subheadline)
										.foregroundStyle(Theme.text.color)
									Spacer()
									Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.dim.color)
								}
								.padding(.vertical, 4)
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.top, 4)
				}
			}
		}
	}

	private func grid(_ year: TrendsModel.CalendarYear) -> some View {
		let byPosition = Dictionary(uniqueKeysWithValues: year.cells.map { ("\($0.week)-\($0.weekday)", $0) })
		return HStack(alignment: .top, spacing: gap) {
			ForEach(0..<year.weeks, id: \.self) { week in
				VStack(spacing: gap) {
					ForEach(0..<7, id: \.self) { weekday in
						if let day = byPosition["\(week)-\(weekday)"] {
							Button {
								selected = selected == day ? nil : day
							} label: {
								Text(day.glyph)
									.font(.system(size: 9, weight: .bold))
									.foregroundStyle(Theme.bg.color)
									.frame(width: cell, height: cell)
									.background(color(day.intensity), in: RoundedRectangle(cornerRadius: 2))
									.overlay {
										if selected == day {
											RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.text.color, lineWidth: 1.5)
										}
									}
							}
							.buttonStyle(.plain)
							.accessibilityLabel(day.accessibilityLabel)
						} else {
							RoundedRectangle(cornerRadius: 2)
								.fill(Theme.border.color.opacity(0.5))
								.frame(width: cell, height: cell)
								.accessibilityHidden(true)
						}
					}
				}
			}
		}
	}

	private func latestWeek(_ year: TrendsModel.CalendarYear) -> CGFloat {
		guard let last = year.cells.last, year.weeks > 1 else { return 1 }
		return min(1, CGFloat(last.week + 1) / CGFloat(year.weeks))
	}

	private func color(_ net: Int) -> Color {
		switch net {
		case ..<0: Theme.loss.color.opacity(0.45 + 0.55 * Double(-net) / 3)
		case 0: Theme.draw.color.opacity(0.7)
		default: Theme.win.color.opacity(0.45 + 0.55 * Double(net) / 3)
		}
	}
}

// MARK: Rating

private struct RatingChartCard: View {
	let model: TrendsModel
	@State private var selectedDate: Date?

	var body: some View {
		let chart = model.ratingChart
		DashboardCard(
			title: "Your rating over time",
			subtitle: chart.mode == .uscf ? "Official Rating steps by supplement; Live Rating per Section" : "Ratings typed in the Game headers")
		{
			if chart.isEmpty {
				CardEmptyText(chart.emptyMessage)
			} else {
				Chart {
					if chart.mode == .uscf {
						ForEach(chart.official) { p in
							LineMark(x: .value("Date", p.date), y: .value("Rating", p.rating), series: .value("Series", "Official"))
								.interpolationMethod(.stepEnd)
								.foregroundStyle(by: .value("Series", "Official Rating"))
								.lineStyle(StrokeStyle(lineWidth: chart.emphasized == .official ? 2.5 : 1.5))
								.opacity(chart.emphasized == .official ? 1 : 0.45)
						}
						ForEach(chart.live) { p in
							LineMark(x: .value("Date", p.date), y: .value("Rating", p.rating), series: .value("Series", "Live"))
								.foregroundStyle(by: .value("Series", "Live Rating"))
								.lineStyle(StrokeStyle(lineWidth: chart.emphasized == .live ? 2.5 : 1.5))
								.opacity(chart.emphasized == .live ? 1 : 0.45)
							PointMark(x: .value("Date", p.date), y: .value("Rating", p.rating))
								.foregroundStyle(by: .value("Series", "Live Rating"))
								.symbolSize(18)
								.opacity(chart.emphasized == .live ? 1 : 0.45)
						}
					} else {
						ForEach(chart.typed) { p in
							LineMark(x: .value("Date", p.date), y: .value("Rating", p.rating), series: .value("Series", "Rating"))
								.foregroundStyle(by: .value("Series", "Rating"))
							PointMark(x: .value("Date", p.date), y: .value("Rating", p.rating))
								.foregroundStyle(by: .value("Series", "Rating"))
								.symbolSize(18)
						}
						ForEach(chart.trend) { p in
							LineMark(x: .value("Date", p.date), y: .value("Rating", p.value), series: .value("Series", "Trend"))
								.foregroundStyle(by: .value("Series", "Trend"))
								.lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
						}
					}
					if let selectedDate, let readout = model.ratingReadout(at: selectedDate) {
						RuleMark(x: .value("Date", readout.date))
							.foregroundStyle(Theme.muted.color.opacity(0.6))
							.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
								ReadoutBubble(
									title: readout.date.formatted(shortDate),
									lines: readout.lines.map { ($0.value, $0.detail.isEmpty ? $0.series : "\($0.series), \($0.detail)") })
							}
					}
				}
				.chartForegroundStyleScale(
					domain: chart.mode == .uscf ? ["Official Rating", "Live Rating"] : ["Rating", "Trend"],
					range: chart.mode == .uscf
						? [Theme.text.color, Theme.primary.color] : [Theme.primary.color, Theme.muted.color])
				.chartYScale(domain: .automatic(includesZero: false))
				.chartYAxis {
					AxisMarks { value in
						AxisGridLine()
						AxisValueLabel { Text(RatingFormat.whole(value.as(Double.self))) }
					}
				}
				.chartXSelection(value: $selectedDate)
				.chartLegend(position: .bottom)
				.frame(height: 240)
				.accessibilityLabel("Your rating over time")
				.accessibilityValue(summary(chart))
			}
		}
	}

	private func summary(_ chart: TrendsModel.RatingChart) -> String {
		if chart.mode == .uscf {
			let official = chart.official.last.map { "Official Rating \(RatingFormat.whole($0.rating))" }
			let live = chart.live.last.map { "Live Rating \(RatingFormat.whole($0.rating))" }
			return [official, live].compactMap { $0 }.joined(separator: ", ")
		}
		return chart.typed.last.map { "Latest rating \(RatingFormat.whole($0.rating))" } ?? ""
	}
}

// MARK: Win rate

private struct WinRateCard: View {
	let model: TrendsModel
	@State private var selectedDate: Date?

	var body: some View {
		let points = model.winRate
		DashboardCard(title: "Cumulative win rate over time") {
			if points.isEmpty {
				CardEmptyText("No dated Games in this filter")
			} else {
				Chart {
					RuleMark(y: .value("Win rate", 50))
						.foregroundStyle(Theme.dim.color)
						.lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
					ForEach(points) { p in
						AreaMark(x: .value("Date", p.date), y: .value("Win rate", p.pct))
							.foregroundStyle(Theme.win.color.opacity(0.15))
						LineMark(x: .value("Date", p.date), y: .value("Win rate", p.pct))
							.foregroundStyle(Theme.win.color)
					}
					if let selectedDate, let readout = model.winRateReadout(at: selectedDate) {
						RuleMark(x: .value("Date", readout.date))
							.foregroundStyle(Theme.muted.color.opacity(0.6))
							.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
								ReadoutBubble(title: readout.date.formatted(shortDate), lines: [(readout.value, readout.detail)])
							}
					}
				}
				.chartYScale(domain: 0...100)
				.chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
					AxisGridLine()
					AxisValueLabel { Text(PercentFormat.whole(v.as(Double.self) ?? 0)) }
				} }
				.chartXSelection(value: $selectedDate)
				.frame(height: 200)
				.accessibilityLabel("Cumulative win rate")
				.accessibilityValue(model.winRateReadout(at: points.last!.date).map { "\($0.value), \($0.detail)" } ?? "")
			}
		}
	}
}

// MARK: Months and weekdays

private struct MonthsCard: View {
	let months: [TrendsModel.MonthBar]
	@State private var selectedDate: Date?

	private var selected: TrendsModel.MonthBar? {
		selectedDate.flatMap { d in ChartDates.nearest(months, to: d, by: \.date) }
	}

	var body: some View {
		DashboardCard(title: "Games per month") {
			if months.isEmpty {
				CardEmptyText("No dated Games in this filter")
			} else {
				Chart(months) { m in
					BarMark(x: .value("Month", m.date, unit: .month), y: .value("Games", m.games))
						.foregroundStyle(Theme.primary.color.opacity(selected == nil || selected == m ? 1 : 0.4))
						.accessibilityLabel(m.label)
						.accessibilityValue("\(m.games) Games, \(m.wins) wins, win rate \(m.winRate)")
					if selected == m {
						RuleMark(x: .value("Month", m.date, unit: .month))
							.foregroundStyle(.clear)
							.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
								ReadoutBubble(title: m.label, lines: [("\(m.games) Games", "\(m.wins) wins, \(m.winRate)")])
							}
					}
				}
				.chartXSelection(value: $selectedDate)
				.frame(height: 180)
			}
		}
	}
}

private struct WeekdayCard: View {
	let days: [TrendsModel.WeekdayBar]

	var body: some View {
		DashboardCard(title: "Win rate by day of week") {
			if days.isEmpty {
				CardEmptyText("No dated Games in this filter")
			} else {
				Chart {
					RuleMark(y: .value("Win rate", 50))
						.foregroundStyle(Theme.dim.color)
						.lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
					ForEach(days) { d in
						BarMark(x: .value("Day", d.day.rawValue), y: .value("Win rate", d.pct))
							.foregroundStyle(d.pct >= 50 ? Theme.win.color : Theme.loss.color)
							.annotation(position: .top) {
								Text(PercentFormat.whole(d.pct)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted.color)
							}
							.accessibilityLabel(d.day.rawValue)
							.accessibilityValue("\(d.wins) wins in \(d.games) Games")
					}
				}
				.chartYScale(domain: 0...110)
				.chartYAxis(.hidden)
				.frame(height: 160)
			}
		}
	}
}

// MARK: Game length

private struct LengthCard: View {
	let bins: [TrendsModel.LengthBin]
	let averages: [TrendsModel.AverageLength]
	@State private var selectedMoves: Int?

	var body: some View {
		DashboardCard(title: "Game length", subtitle: "Full moves, by outcome") {
			if bins.isEmpty {
				CardEmptyText("No data")
			} else {
				Chart(bins) { b in
					RectangleMark(
						xStart: .value("Moves", b.start), xEnd: .value("Moves", b.start + b.width),
						yStart: .value("Games", b.base), yEnd: .value("Games", b.base + b.count))
						.foregroundStyle(by: .value("Outcome", b.outcome.rawValue))
						.accessibilityLabel("\(b.outcome.rawValue)s, \(b.label)")
						.accessibilityValue("\(b.count) Games")
				}
				.chartForegroundStyleScale([
					"Win": Theme.win.color, "Draw": Theme.draw.color, "Loss": Theme.loss.color,
				])
				.chartXSelection(value: $selectedMoves)
				.frame(height: 170)
				if let readout = readout {
					Text(readout).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted.color)
				}
			}
			if !averages.isEmpty {
				HStack {
					ForEach(averages) { a in
						VStack(alignment: .leading, spacing: 2) {
							Text("Average, \(a.label.lowercased())").font(.caption).foregroundStyle(Theme.muted.color)
							Text("\(a.value) moves").font(.headline.monospacedDigit()).foregroundStyle(a.outcome.themeColor)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
						.accessibilityElement(children: .combine)
					}
				}
			}
		}
	}

	private var readout: String? {
		guard let selectedMoves, let width = bins.first?.width else { return nil }
		let start = selectedMoves / width * width
		let here = bins.filter { $0.start == start }
		guard let label = here.first?.label else { return nil }
		return label + ": " + here.map { "\($0.count) \($0.outcome.rawValue.lowercased())" }.joined(separator: ", ")
	}
}

// MARK: Playing conditions

private struct TimeControlCard: View {
	let rows: [TrendsModel.TimeControlRow]

	var body: some View {
		DashboardCard(title: "Results by time control") {
			if rows.isEmpty {
				CardEmptyText("No data")
			} else {
				VStack(spacing: 12) {
					ForEach(rows) { row in
						VStack(alignment: .leading, spacing: 4) {
							HStack(alignment: .firstTextBaseline) {
								Text(row.label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text.color)
								Text(row.speed.rawValue).font(.caption).foregroundStyle(Theme.muted.color)
								Spacer()
								Text("\(row.winRate) wins").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted.color)
							}
							ResultBar(win: row.win, draw: row.draw, loss: row.loss)
						}
						.accessibilityElement(children: .ignore)
						.accessibilityLabel("\(row.label), \(row.speed.rawValue)")
						.accessibilityValue("\(row.games) Games: \(row.win) wins, \(row.draw) draws, \(row.loss) losses")
					}
				}
			}
		}
	}
}

/// A Win / Draw / Loss split as one bar, with counts inside.
private struct ResultBar: View {
	let win: Int
	let draw: Int
	let loss: Int

	var body: some View {
		GeometryReader { geo in
			let total = max(1, win + draw + loss)
			HStack(spacing: 1) {
				segment(win, total: total, width: geo.size.width, color: Theme.win.color)
				segment(draw, total: total, width: geo.size.width, color: Theme.draw.color)
				segment(loss, total: total, width: geo.size.width, color: Theme.loss.color)
			}
		}
		.frame(height: 20)
		.clipShape(RoundedRectangle(cornerRadius: 4))
	}

	@ViewBuilder
	private func segment(_ n: Int, total: Int, width: CGFloat, color: Color) -> some View {
		if n > 0 {
			Text("\(n)")
				.font(.caption2.weight(.bold).monospacedDigit())
				.foregroundStyle(Theme.bg.color)
				.frame(width: width * CGFloat(n) / CGFloat(total), height: 20)
				.background(color)
		}
	}
}

private struct RoundCard: View {
	let rounds: [TrendsModel.RoundBar]
	@State private var selected: String?

	var body: some View {
		DashboardCard(title: "Score by round", subtitle: "The fatigue check. Dimmed rounds have too few Games to conclude.") {
			if rounds.isEmpty {
				CardEmptyText("No rounds recorded")
			} else {
				Chart {
					RuleMark(y: .value("Score", 50))
						.foregroundStyle(Theme.dim.color)
						.lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
					ForEach(rounds) { r in
						BarMark(x: .value("Round", String(r.round)), y: .value("Score", r.scorePct))
							.foregroundStyle(Theme.primary.color.opacity(r.reliable ? 1 : 0.35))
							.annotation(position: .top) {
								if rounds.count <= 8 {
									Text(PercentFormat.whole(r.scorePct)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted.color)
								}
							}
							.accessibilityLabel(r.label)
							.accessibilityValue(
								"Score \(PercentFormat.spoken(r.scorePct)) over \(RecordText.games(r.games))"
									+ (r.reliable ? "" : ", too few to conclude"))
					}
				}
				.chartYScale(domain: 0...110)
				.chartYAxis(.hidden)
				.chartXAxis {
					AxisMarks { value in
						// Every round on a short Section list; 1, 5, 10, ... on a long one.
						if let round = value.as(String.self).flatMap(Int.init),
							rounds.count <= 10 || round == 1 || round % 5 == 0
						{
							AxisValueLabel("R\(round)")
						}
					}
				}
				.chartXSelection(value: $selected)
				.frame(height: 170)
				if let selected, let r = rounds.first(where: { String($0.round) == selected }) {
					Text("\(r.label): \(r.games) Games, \(r.win) wins, \(r.draw) draws, \(r.loss) losses" + (r.reliable ? "" : ". Too few to conclude."))
						.font(.caption)
						.foregroundStyle(Theme.muted.color)
				}
			}
		}
	}
}

// MARK: Upsets

private struct UpsetCard: View {
	let title: String
	let subtitle: String
	let rows: [TrendsModel.UpsetRow]
	let empty: String
	let color: Color

	var body: some View {
		DashboardCard(title: title, subtitle: subtitle) {
			if rows.isEmpty {
				CardEmptyText(empty)
			} else {
				VStack(spacing: 0) {
					ForEach(rows) { row in
						NavigationLink(value: GameRoute(gameID: row.gameId)) {
							HStack {
								VStack(alignment: .leading, spacing: 2) {
									Text(row.opponent).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text.color)
									Text("\(row.date), \(row.ratings)").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted.color)
								}
								Spacer()
								Text(row.margin).font(.headline.monospacedDigit()).foregroundStyle(color)
								Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.dim.color)
							}
							.padding(.vertical, 6)
							.contentShape(Rectangle())
							.accessibilityElement(children: .combine)
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
	}
}
