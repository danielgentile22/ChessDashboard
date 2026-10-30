import ChessDashboardKit
import SwiftUI

/// Series and the Rated Events inside them, the Performance per Series
/// chart, and Rated Events entered but never played. Tap a Rated Event for
/// its Sections and crosstables, or a Game to open it.
struct EventsScreen: View {
	@Environment(AppEnvironment.self) private var env
	@State private var model: EventsModel

	init(context: ScreenContext) { _model = State(initialValue: EventsModel(context: context)) }

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { payload in
			List {
				if payload.series.isEmpty {
					ContentUnavailableView(
						"No events in this filter", systemImage: "trophy",
						description: Text("Loosen the filters to see more Series."))
				} else {
					Section("Performance per Series") {
						if payload.seriesPerformance.isEmpty {
							Text("No Series in this filter").foregroundStyle(Theme.muted.color)
						} else {
							// The web lists newest on top; the payload is oldest first.
							WDLBarChart(
								bars: payload.seriesPerformance.reversed().map {
									.init(id: $0.series, label: $0.series, win: $0.win, draw: $0.draw, loss: $0.loss)
								},
								summary: "Performance per Series")
						}
					}
					ForEach(payload.series.reversed(), id: \.series) { series in
						SeriesSection(series: series)
					}
				}
				if !payload.unplayedEvents.isEmpty {
					Section {
						ForEach(payload.unplayedEvents, id: \.eventId) { event in
							VStack(alignment: .leading, spacing: 2) {
								Text(event.name)
								Text([EventText.dates(start: event.start, end: event.end),
									  event.playerCount.map { "\($0) players" } ?? ""]
									.filter { !$0.isEmpty }.joined(separator: " · "))
									.font(.footnote).foregroundStyle(Theme.muted.color)
							}
							.accessibilityElement(children: .combine)
						}
					} header: {
						Text("Entered, never played")
					} footer: {
						Text("Rated Events you entered with no Games in your Studies.")
					}
				}
			}
		}
		.navigationDestination(for: EventRoute.self) { route in
			EventScreen(context: env.context!, eventID: route.eventID)
		}
		.screenChrome(title: "Events", page: .events, resource: model.resource)
		.task(id: env.filters.state) { await model.load() }
		.refreshable { await model.load() }
	}
}

/// One Series: its headline, then a card per Rated Event, then the Games
/// that aren't part of any Rated Event.
private struct SeriesSection: View {
	let series: API.EventsSeries

	var body: some View {
		Section {
			ForEach(series.ratedEvents, id: \.eventId) { event in
				NavigationLink(value: EventRoute(eventID: event.eventId)) {
					RatedEventCard(event: event)
				}
			}
			if !series.unmatchedGames.isEmpty {
				DisclosureGroup {
					ForEach(series.unmatchedGames, id: \.game.gameId) { row in
						NavigationLink(value: GameRoute(gameID: row.game.gameId)) {
							GameSummaryRow(game: row.game, round: row.round)
						}
					}
				} label: {
					VStack(alignment: .leading, spacing: 2) {
						Text("Not part of any Rated Event")
						Text("Forfeits and Games USCF hasn't rated (yet)")
							.font(.footnote).foregroundStyle(Theme.muted.color)
					}
				}
			}
		} header: {
			VStack(alignment: .leading, spacing: 2) {
				Text(series.series.isEmpty ? "No Series" : series.series)
					.font(.headline).foregroundStyle(Theme.text.color).textCase(nil)
				Text(EventText.seriesStats(series)).font(.caption).textCase(nil)
			}
		}
	}
}

/// A Rated Event's identity, score, Live Rating change, and placement.
private struct RatedEventCard: View {
	let event: API.EventsRatedEvent

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(alignment: .firstTextBaseline) {
				Text(event.name).font(.body.weight(.semibold))
				Spacer()
				Text(EventText.ratingChange(pre: event.preRating, post: event.postRating, change: event.ratingChange))
					.font(.subheadline.weight(.semibold)).monospacedDigit()
					.foregroundStyle(changeTint)
			}
			Text(EventText.dates(start: event.start, end: event.end))
				.font(.footnote).foregroundStyle(Theme.muted.color)
			Text(metaLine).font(.footnote).foregroundStyle(Theme.muted.color)
			ForEach(event.sections, id: \.name) { section in
				if let placement = EventText.placement(placement: section.placement, playerCount: section.playerCount) {
					Label("\(section.name): \(placement)", systemImage: "list.number")
						.font(.footnote.weight(.medium)).foregroundStyle(Theme.accent.color)
				}
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityHint("Opens the Rated Event")
	}

	private var metaLine: String {
		[event.sections.map(\.name).joined(separator: " · "),
		 event.playerCount.map { "\($0) players" } ?? "",
		 EventText.scoreLine(score: event.score, games: event.gameCount, forfeits: event.forfeitCount),
		 event.performanceRating.map { "Performance \(RatingFormat.whole($0))" } ?? ""]
			.filter { !$0.isEmpty }.joined(separator: " · ")
	}

	private var changeTint: Color {
		guard let change = event.ratingChange else { return Theme.muted.color }
		return change > 0 ? Theme.win.color : change < 0 ? Theme.loss.color : Theme.draw.color
	}
}
