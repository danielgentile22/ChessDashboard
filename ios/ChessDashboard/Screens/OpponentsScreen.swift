import Charts
import ChessDashboardKit
import SwiftUI

/// Who you play: search an opponent to open their Scouting Report, your
/// records against regulars, and how you score against stronger and weaker
/// players.
struct OpponentsScreen: View {
	@Environment(AppEnvironment.self) private var env
	@State private var model: OpponentsModel
	@State private var showingAllRecords = false
	private let context: ScreenContext

	init(context: ScreenContext) {
		self.context = context
		_model = State(initialValue: OpponentsModel(context: context))
	}

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { payload in
			List {
				if model.searchText.isEmpty {
					if payload.gamesCount == 0 {
						Section { NoGamesMatch() }
					} else {
						strengthSection
						outcomeSection(payload.outcomeVsRating)
						recordsSection(payload.records)
					}
				}
				opponentsSection
			}
		}
		.searchable(text: $model.searchText, prompt: "Search opponents")
		.screenChrome(title: "Opponents", page: .opponents, resource: model.resource)
		.task(id: env.filters.state) { await model.load() }
		.refreshable { await model.load() }
	}

	private var opponentsSection: some View {
		Section {
			let results = model.searchResults
			if results.isEmpty {
				Text("No opponent matches \u{201C}\(model.searchText)\u{201D}.")
					.foregroundStyle(Theme.muted.color)
			}
			ForEach(results, id: \.opponentId) { item in
				NavigationLink(item.opponent) {
					ScoutingReportScreen(opponentID: item.opponentId, name: item.opponent, context: context)
				}
			}
		} header: {
			Text("Scouting Reports")
		} footer: {
			Text("Every opponent in your archive. Open one for the head-to-head, their openings against you, and your Lessons from those Games.")
		}
	}

	private func recordsSection(_ records: [API.OpponentsRecord]) -> some View {
		Section {
			let shown = showingAllRecords ? records : Array(records.prefix(5))
			ForEach(shown, id: \.opponent) { record in
				let row = VStack(alignment: .leading, spacing: 4) {
					HStack {
						Text(record.opponent).font(.subheadline.weight(.medium))
						Spacer()
						Text("\(record.games) Games").font(.caption).foregroundStyle(Theme.muted.color)
					}
					RecordBar(win: record.win, draw: record.draw, loss: record.loss)
				}
				if let id = record.opponentId {
					NavigationLink {
						ScoutingReportScreen(opponentID: id, name: record.opponent, context: context)
					} label: { row }
				} else {
					row
				}
			}
			if records.count > 5 {
				Button(showingAllRecords ? "Show fewer" : "Show all \(records.count)") {
					withAnimation { showingAllRecords.toggle() }
				}
			}
		} header: {
			Text("Opponents you've played more than once")
		} footer: {
			if records.isEmpty { Text("No opponent faced more than once in these Games.") }
		}
	}

	private var strengthSection: some View {
		Section {
			WDLBarChart(
				bars: model.ratingBuckets.map {
					.init(id: $0.bucket.rawValue, label: $0.bucket.rawValue, win: $0.win, draw: $0.draw, loss: $0.loss)
				},
				summary: "Wins, draws and losses by opponent rating difference")
		} header: {
			Text("By opponent rating difference")
		} footer: {
			Text("Their rating minus yours at the time of the Game. Touch a bar to read it.")
		}
	}

	private func outcomeSection(_ points: [API.OpponentsOutcomePoint]) -> some View {
		Section {
			OutcomeScatter(points: points)
		} header: {
			Text("Outcome vs opponent rating")
		}
	}
}

/// Every Game as a dot: when you played, how strong they were, how it went.
private struct OutcomeScatter: View {
	let points: [API.OpponentsOutcomePoint]
	@State private var selectedDate: Date?

	private struct Dot: Identifiable {
		let id: Int
		let date: Date
		let point: API.OpponentsOutcomePoint
		let rating: Int
	}

	private var dots: [Dot] {
		points.enumerated().compactMap { i, p in
			guard let date = ISODates.day(p.date), let rating = p.opponentRating else { return nil }
			return Dot(id: i, date: date, point: p, rating: rating)
		}
	}

	var body: some View {
		let dots = dots
		let selected = selectedDate.flatMap { d in dots.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }
		if dots.isEmpty {
			Text("No rated opponents in these Games.").foregroundStyle(Theme.muted.color)
		} else {
			Chart {
				ForEach(dots) { dot in
					PointMark(x: .value("Date", dot.date), y: .value("Opponent rating", dot.rating))
						.foregroundStyle(by: .value("Result", dot.point.outcome.rawValue))
						.symbolSize(dot.id == selected?.id ? 140 : 60)
						.accessibilityLabel("\(dot.point.opponent), \(dot.point.date ?? "")")
						.accessibilityValue("\(dot.point.outcome.rawValue), rated \(RatingFormat.whole(dot.rating))")
				}
				if let selected {
					RuleMark(x: .value("Date", selected.date))
						.foregroundStyle(Theme.dim.color)
						.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
							VStack(spacing: 0) {
								Text("\(selected.point.opponent) (\(RatingFormat.whole(selected.rating)))")
								Text("\(selected.point.outcome.rawValue) · \(selected.point.date ?? "")")
									.foregroundStyle(Theme.muted.color)
							}
							.font(.caption)
							.padding(6)
							.background(RoundedRectangle(cornerRadius: 6).fill(Theme.card2.color))
						}
				}
			}
			.chartForegroundStyleScale(["Win": Theme.win.color, "Draw": Theme.draw.color, "Loss": Theme.loss.color])
			.chartYScale(domain: .automatic(includesZero: false))
			.chartXSelection(value: $selectedDate)
			.frame(height: 240)
			.padding(.vertical, 6)
		}
	}
}
