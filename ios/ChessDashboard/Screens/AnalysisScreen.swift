import Charts
import ChessDashboardKit
import SwiftUI

/// Where your mistakes come from: the Error Profile read from the computer
/// analysis Lichess embedded in the Study. Like the web page it covers every
/// analyzed Game, so it has no filters or lens.
struct AnalysisScreen: View {
	@State private var model: AnalysisModel

	init(context: ScreenContext) { _model = State(initialValue: AnalysisModel(context: context)) }

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { payload in
			List {
				if payload.hasAnalysis {
					Section {
						MistakeDonut(distribution: payload.mistakeTypeDistribution)
					} header: {
						Text("Mistake types")
					} footer: {
						Text("Your non-best moves across every analyzed Game: tactical (a forcing shot missed or material dropped to a combination) versus positional (a slow eval bleed).")
					}
					Section {
						AccuracyChart(points: payload.accuracyTrend)
					} header: {
						Text("Accuracy over time")
					} footer: {
						Text("One quality number per analyzed Game (how close your moves were to the engine's best, whatever the result), with your rating dotted for context. Touch to read a Game.")
					}
					Section {
						MistakeTrendChart(points: payload.mistakeTypeTrend)
					} header: {
						Text("Mistake types over time")
					} footer: {
						Text("Tactical and positional mistakes per analyzed Game, with your rating. Do the tactical errors fall as your level rises?")
					}
					Section {
						PhaseMatrix(cells: model.cells, hottest: model.hottestCell)
					} header: {
						Text("Where mistakes happen")
					} footer: {
						Text("Your mistakes by Game phase and kind. The hottest cell is your worst specific combination to train.")
					}
					Section {
						MoveHistogram(buckets: payload.mistakeMoveHistogram)
					} header: {
						Text("When mistakes happen")
					} footer: {
						Text("Mistakes per move number. A spike late in the Game is the fingerprint of time trouble; a flat spread rules it out.")
					}
				} else {
					Section {
						ContentUnavailableView {
							Label("No Games analyzed yet", systemImage: "cpu")
						} description: {
							Text("Request computer analysis on a Chapter on Lichess (one click at the board), and the next Sync reads it in. Your mistake profile, tactical versus positional, appears here once a Game is analyzed.")
						}
					}
				}
				if !payload.awaitingAnalysis.isEmpty { awaitingSection(payload.awaitingAnalysis) }
			}
		}
		.screenChrome(title: "Analysis", page: .analysis, resource: model.resource, filtered: false)
		.gameDestination()
		.task { await model.load() }
		.refreshable { await model.load() }
	}

	private func awaitingSection(_ games: [API.AnalysisAwaitingGame]) -> some View {
		Section {
			ForEach(games, id: \.gameId) { game in
				NavigationLink(value: GameRoute(gameID: game.gameId)) {
					VStack(alignment: .leading, spacing: 2) {
						Text(game.name).font(.subheadline)
						if let date = game.date {
							Text(date).font(.caption).foregroundStyle(Theme.muted.color)
						}
					}
				}
				.swipeActions(edge: .trailing) {
					if let url = URL(string: game.chapterUrl) {
						Link(destination: url) { Label("Request on Lichess", systemImage: "safari") }
							.tint(Theme.primary.color)
					}
				}
				.contextMenu {
					if let url = URL(string: game.chapterUrl) {
						Link(destination: url) { Label("Request analysis on Lichess", systemImage: "safari") }
					}
				}
			}
		} header: {
			Text("Awaiting analysis (\(games.count))")
		} footer: {
			Text("These Games have no computer analysis yet, so they don't count above. Swipe one to open its Chapter on Lichess and request analysis; the next Sync reads it in.")
		}
	}
}

private let tacticalColor = Theme.primary.color
private let positionalColor = Theme.muted.color
private let kindScale: KeyValuePairs<String, Color> = ["Tactical": tacticalColor, "Positional": positionalColor]

/// Tactical vs positional as a donut with the counts in the middle.
private struct MistakeDonut: View {
	let distribution: API.AnalysisMistakeTypeDistribution

	var body: some View {
		let total = distribution.tactical + distribution.positional
		HStack(spacing: 20) {
			Chart {
				SectorMark(angle: .value("Mistakes", distribution.tactical), innerRadius: .ratio(0.62), angularInset: 1.5)
					.foregroundStyle(by: .value("Kind", "Tactical"))
				SectorMark(angle: .value("Mistakes", distribution.positional), innerRadius: .ratio(0.62), angularInset: 1.5)
					.foregroundStyle(by: .value("Kind", "Positional"))
			}
			.chartForegroundStyleScale(kindScale)
			.chartLegend(.hidden)
			.chartBackground { _ in
				VStack(spacing: 0) {
					Text("\(total)").font(.title2.weight(.semibold).monospacedDigit())
					Text("mistakes").font(.caption2).foregroundStyle(Theme.muted.color)
				}
			}
			.frame(width: 140, height: 140)
			VStack(alignment: .leading, spacing: 10) {
				legend("Tactical", distribution.tactical, total, tacticalColor)
				legend("Positional", distribution.positional, total, positionalColor)
			}
		}
		.padding(.vertical, 8)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Mistake types")
		.accessibilityValue("\(distribution.tactical) tactical, \(distribution.positional) positional")
	}

	private func legend(_ name: String, _ count: Int, _ total: Int, _ color: Color) -> some View {
		HStack(spacing: 8) {
			Circle().fill(color).frame(width: 10, height: 10)
			VStack(alignment: .leading, spacing: 0) {
				Text(name).font(.subheadline)
				Text(total > 0 ? "\(count) (\(Int((Double(count) / Double(total) * 100).rounded()))%)" : "\(count)")
					.font(.caption.monospacedDigit())
					.foregroundStyle(Theme.muted.color)
			}
		}
	}
}

/// A point on a date axis, with the nearest-to-touch lookup the charts share.
private protocol Dated {
	var day: Date { get }
}

private func nearest<T: Dated>(_ items: [T], to date: Date?) -> T? {
	guard let date else { return nil }
	return items.min { abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date)) }
}

/// The rating overlay's trailing axis, labelled in rating points.
private func ratingAxis(_ overlay: RatingOverlay) -> some AxisContent {
	AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
		AxisValueLabel {
			if let v = value.as(Double.self) {
				Text(RatingFormat.whole(overlay.rating(atPlotted: v)))
			}
		}
	}
}

private struct AccuracyChart: View {
	let points: [API.AnalysisAccuracyPoint]
	@State private var selectedDate: Date?

	struct Point: Dated, Identifiable {
		let id: String
		let day: Date
		let source: API.AnalysisAccuracyPoint
	}

	var body: some View {
		let items = points.compactMap { p in ISODates.day(p.date).map { Point(id: p.gameId, day: $0, source: p) } }
		let overlay = RatingOverlay(ratings: items.compactMap(\.source.rating), onto: 0...100)
		let selected = nearest(items, to: selectedDate)
		VStack(alignment: .leading, spacing: 8) {
			Chart {
				ForEach(items) { item in
					LineMark(x: .value("Date", item.day), y: .value("Accuracy", item.source.accuracy), series: .value("Series", "Accuracy"))
						.foregroundStyle(tacticalColor)
					PointMark(x: .value("Date", item.day), y: .value("Accuracy", item.source.accuracy))
						.foregroundStyle(tacticalColor)
						.accessibilityLabel("\(item.source.opponent), \(item.source.date ?? "")")
						.accessibilityValue("Accuracy \(item.source.accuracy.formatted(.number.precision(.fractionLength(0...1)))) percent")
					if let overlay, let rating = item.source.rating {
						LineMark(x: .value("Date", item.day), y: .value("Rating", overlay.plotted(rating)), series: .value("Series", "Rating"))
							.foregroundStyle(Theme.text.color.opacity(0.6))
							.lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
							.accessibilityHidden(true)
					}
				}
				if let selected {
					RuleMark(x: .value("Date", selected.day)).foregroundStyle(Theme.dim.color)
				}
			}
			.chartYScale(domain: 0...100)
			.chartYAxis {
				AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
				if let overlay { ratingAxis(overlay) }
			}
			.chartXSelection(value: $selectedDate)
			.frame(height: 220)
			if let selected {
				NavigationLink(value: GameRoute(gameID: selected.id)) {
					VStack(alignment: .leading, spacing: 2) {
						Text("vs \(selected.source.opponent) · \(selected.source.date ?? "")").font(.subheadline)
						Text("Accuracy \(selected.source.accuracy.formatted(.number.precision(.fractionLength(0...1))))%"
							+ (selected.source.rating.map { " · rating \(RatingFormat.whole($0))" } ?? ""))
							.font(.caption.monospacedDigit())
							.foregroundStyle(Theme.muted.color)
					}
				}
			}
		}
		.padding(.vertical, 6)
	}
}

private struct MistakeTrendChart: View {
	let points: [API.AnalysisMistakeTypePoint]
	@State private var selectedDate: Date?

	struct Point: Dated, Identifiable {
		let id: String
		let day: Date
		let source: API.AnalysisMistakeTypePoint
	}

	var body: some View {
		let items = points.compactMap { p in ISODates.day(p.date).map { Point(id: p.gameId, day: $0, source: p) } }
		let top = Double(max(items.map { max($0.source.tactical, $0.source.positional) }.max() ?? 0, 1))
		let overlay = RatingOverlay(ratings: items.compactMap(\.source.rating), onto: 0...top)
		let selected = nearest(items, to: selectedDate)
		Chart {
			ForEach(items) { item in
				ForEach(MistakeKind.allCases, id: \.self) { kind in
					let count = kind == .tactical ? item.source.tactical : item.source.positional
					LineMark(x: .value("Date", item.day), y: .value("Mistakes", count), series: .value("Kind", kind.rawValue))
						.foregroundStyle(by: .value("Kind", kind.rawValue))
					PointMark(x: .value("Date", item.day), y: .value("Mistakes", count))
						.foregroundStyle(by: .value("Kind", kind.rawValue))
						.accessibilityLabel("\(item.source.opponent), \(item.source.date ?? "")")
						.accessibilityValue("\(count) \(kind.rawValue.lowercased())")
				}
				if let overlay, let rating = item.source.rating {
					LineMark(x: .value("Date", item.day), y: .value("Mistakes", overlay.plotted(rating)), series: .value("Kind", "Rating"))
						.foregroundStyle(Theme.text.color.opacity(0.6))
						.lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
						.accessibilityHidden(true)
				}
			}
			if let selected {
				RuleMark(x: .value("Date", selected.day))
					.foregroundStyle(Theme.dim.color)
					.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
						VStack(alignment: .leading, spacing: 0) {
							Text("vs \(selected.source.opponent)")
							Text("\(selected.source.tactical) tactical, \(selected.source.positional) positional")
								.foregroundStyle(Theme.muted.color)
						}
						.font(.caption)
						.padding(6)
						.background(RoundedRectangle(cornerRadius: 6).fill(Theme.card2.color))
					}
			}
		}
		.chartForegroundStyleScale(kindScale)
		.chartYScale(domain: 0...top)
		.chartYAxis {
			AxisMarks(position: .leading)
			if let overlay { ratingAxis(overlay) }
		}
		.chartXSelection(value: $selectedDate)
		.frame(height: 220)
		.padding(.vertical, 6)
	}
}

/// Phase by Mistake Type: a heat grid, the hottest cell outlined.
private struct PhaseMatrix: View {
	let cells: [PhaseCell]
	let hottest: PhaseCell?

	var body: some View {
		let top = Double(max(cells.map(\.count).max() ?? 0, 1))
		Chart(cells, id: \.self) { cell in
			RectangleMark(x: .value("Kind", cell.kind.rawValue), y: .value("Phase", label(cell.phase)))
				.foregroundStyle(Theme.primary.color.opacity(0.12 + 0.88 * Double(cell.count) / top))
				.annotation(position: .overlay) {
					Text("\(cell.count)")
						.font(.headline.monospacedDigit())
						.foregroundStyle(Theme.text.color)
				}
				.accessibilityLabel("\(label(cell.phase)), \(cell.kind.rawValue.lowercased())")
				.accessibilityValue("\(cell.count) mistakes" + (cell == hottest ? ", the most" : ""))
		}
		.chartXAxis { AxisMarks(position: .top) }
		.frame(height: 180)
		.padding(.vertical, 6)
		if let hottest {
			Label(
				"Most mistakes: \(hottest.kind.rawValue.lowercased()) in the \(label(hottest.phase).lowercased()) (\(hottest.count))",
				systemImage: "flame")
				.font(.subheadline)
				.foregroundStyle(Theme.accent.color)
		}
	}

	private func label(_ phase: API.AnalysisPhaseRowPhase) -> String {
		switch phase {
		case .opening: "Opening"
		case .middlegame: "Middlegame"
		case .endgame: "Endgame"
		}
	}
}

private struct MoveHistogram: View {
	let buckets: [API.AnalysisMoveBucket]
	@State private var selectedMove: Int?

	var body: some View {
		let selected = selectedMove.flatMap { m in buckets.min { abs($0.moveNumber - m) < abs($1.moveNumber - m) } }
		Chart {
			ForEach(buckets, id: \.moveNumber) { b in
				BarMark(x: .value("Move", b.moveNumber), y: .value("Mistakes", b.count), width: .ratio(0.8))
					.foregroundStyle(b.moveNumber == selected?.moveNumber ? Theme.accent.color : Theme.primary.color)
					.accessibilityLabel("Move \(b.moveNumber)")
					.accessibilityValue("\(b.count) mistakes")
			}
			if let selected {
				RuleMark(x: .value("Move", selected.moveNumber))
					.foregroundStyle(.clear)
					.annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
						Text("Move \(selected.moveNumber): \(selected.count)")
							.font(.caption.monospacedDigit())
							.padding(4)
							.background(RoundedRectangle(cornerRadius: 4).fill(Theme.card2.color))
					}
			}
		}
		.chartXAxisLabel("Move number")
		.chartXSelection(value: $selectedMove)
		.frame(height: 180)
		.padding(.vertical, 6)
	}
}
