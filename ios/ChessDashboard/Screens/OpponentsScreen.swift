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
		.gameDestination()
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
			StrengthChart(buckets: model.ratingBuckets)
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

/// W/D/L per rating-difference bucket, stacked, with a touch readout.
private struct StrengthChart: View {
	let buckets: [API.OpponentsRatingBucket]
	@State private var selected: String?

	var body: some View {
		Chart {
			ForEach(buckets, id: \.bucket) { b in
				ForEach(Self.parts(b), id: \.0) { part, count in
					BarMark(x: .value("Games", count), y: .value("Rating difference", b.bucket.rawValue))
						.foregroundStyle(by: .value("Result", part))
						.accessibilityLabel(b.bucket.rawValue)
						.accessibilityValue("\(count) \(part == "Win" ? "wins" : part == "Draw" ? "draws" : "losses")")
				}
			}
			if let selected, let b = buckets.first(where: { $0.bucket.rawValue == selected }) {
				RuleMark(y: .value("Rating difference", selected))
					.foregroundStyle(Theme.dim.color)
					.annotation(position: .overlay, alignment: .trailing) {
						Text("\(b.win)W \(b.draw)D \(b.loss)L")
							.font(.caption.monospacedDigit().weight(.semibold))
							.padding(.horizontal, 6).padding(.vertical, 2)
							.background(RoundedRectangle(cornerRadius: 4).fill(Theme.card2.color))
					}
			}
		}
		.chartForegroundStyleScale(["Win": Theme.win.color, "Draw": Theme.draw.color, "Loss": Theme.loss.color])
		.chartYSelection(value: $selected)
		.frame(height: CGFloat(max(buckets.count, 2)) * 44)
		.padding(.vertical, 6)
	}

	static func parts(_ b: API.OpponentsRatingBucket) -> [(String, Int)] {
		[("Win", b.win), ("Draw", b.draw), ("Loss", b.loss)].filter { $0.1 > 0 }
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
