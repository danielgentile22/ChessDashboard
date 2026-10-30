import ChessDashboardKit
import SwiftUI

/// One Rated Event: its score and Live Rating change, its Games, and each
/// Section's placement and full crosstable (the player's row highlighted,
/// its rounds linked to the Games).
struct EventScreen: View {
	@Environment(AppEnvironment.self) private var env
	@State private var model: EventModel

	init(context: ScreenContext, eventID: String) {
		_model = State(initialValue: EventModel(context: context, eventID: eventID))
	}

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { event in
			List {
				Section {
					SummaryHeader(event: event)
				}
				Section("Games") {
					if event.games.isEmpty {
						Text("No Games from this Rated Event in this filter").foregroundStyle(Theme.muted.color)
					}
					ForEach(event.games, id: \.game.gameId) { row in
						NavigationLink(value: GameRoute(gameID: row.game.gameId)) {
							GameSummaryRow(game: row.game, round: row.round, showsUscfStatus: false)
						}
					}
				}
				ForEach(event.sections, id: \.name) { section in
					CrosstableSection(section: section)
				}
			}
		}
		.screenChrome(title: model.resource.value?.name ?? "Rated Event", page: .events, resource: model.resource)
		.navigationBarTitleDisplayMode(.inline)
		.task(id: env.filters.state) { await model.load() }
		.refreshable { await model.load() }
	}
}

private struct SummaryHeader: View {
	let event: API.EventPayload

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(event.name).font(.title3.weight(.semibold))
			if !event.series.isEmpty {
				Text(event.series.joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.muted.color)
			}
			Text(EventText.dates(start: event.start, end: event.end))
				.font(.footnote).foregroundStyle(Theme.muted.color)
			HStack(spacing: 16) {
				Kpi(title: "Score", value: EventText.points(event.score))
				if let performance = event.performanceRating {
					Kpi(title: "Performance", value: RatingFormat.whole(performance))
				}
			}
			.padding(.top, 4)
			Text(RecordText.record(win: event.win, draw: event.draw, loss: event.loss))
				.font(.subheadline).monospacedDigit()
				.padding(.bottom, 4)
			let change = EventText.ratingChange(pre: event.preRating, post: event.postRating, change: event.ratingChange)
			if !change.isEmpty {
				LabeledContent("Live Rating", value: change).monospacedDigit()
			}
			Text(EventText.scoreLine(score: event.score, games: event.gameCount, forfeits: event.forfeitCount)
				+ (event.playerCount.map { " · \($0) players" } ?? ""))
				.font(.footnote).foregroundStyle(Theme.muted.color)
		}
	}
}

private struct Kpi: View {
	let title: String
	let value: String

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title).font(.caption).foregroundStyle(Theme.muted.color)
			Text(value).font(.headline).monospacedDigit()
		}
		.accessibilityElement(children: .combine)
	}
}

/// A Section's placement line and its crosstable, one row per player.
private struct CrosstableSection: View {
	let section: API.EventSection

	var body: some View {
		Section {
			if !section.hasCrosstable {
				Text("No crosstable cached for this Section yet.").foregroundStyle(Theme.muted.color)
			}
			ForEach(section.crosstable, id: \.memberId) { row in
				CrosstableRow(row: row)
					.listRowBackground(row.isPlayer ? Theme.primaryWash.color : nil)
			}
		} header: {
			VStack(alignment: .leading, spacing: 2) {
				Text("Section \(section.name)")
				if let placement = EventText.placement(placement: section.placement, playerCount: section.playerCount) {
					Text(placement).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent.color)
				}
			}
		}
	}
}

private struct CrosstableRow: View {
	let row: API.EventCrosstableRow

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline) {
				Text("\(row.ordinal).").monospacedDigit().foregroundStyle(Theme.muted.color)
				Text(row.name).font(row.isPlayer ? .body.weight(.semibold) : .body).lineLimit(1)
				Spacer()
				Text(EventText.points(row.score)).font(.body.weight(.semibold)).monospacedDigit()
			}
			HStack(alignment: .center) {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 4) {
						ForEach(row.rounds, id: \.roundNumber) { round in
							RoundCell(round: round)
						}
					}
				}
				Spacer(minLength: 8)
				Text(ratingLine).font(.caption).monospacedDigit().foregroundStyle(Theme.muted.color)
			}
		}
		.accessibilityElement(children: row.isPlayer ? .contain : .combine)
	}

	private var ratingLine: String {
		EventText.ratingChange(pre: row.preRating, post: row.postRating, change: nil)
	}
}

/// One round's letter; on the player's own row a round with a Game opens it.
private struct RoundCell: View {
	let round: API.EventCrosstableRound
	@ScaledMetric(relativeTo: .caption) private var size = 24.0

	var body: some View {
		let letter = CrosstableRoundDisplay.letter(round.outcome)
		let cell = Text(letter)
			.font(.caption.weight(.bold).monospaced())
			.frame(width: size, height: size)
			.foregroundStyle(tint(letter))
			.background(RoundedRectangle(cornerRadius: 5).fill(wash(letter)))
		if let gameID = round.gameId {
			NavigationLink(value: GameRoute(gameID: gameID)) {
				cell.overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.primaryLine.color))
			}
			.buttonStyle(.plain)
			.accessibilityLabel(CrosstableRoundDisplay.accessibilityLabel(round))
			.accessibilityHint("Opens the Game")
		} else {
			cell.accessibilityLabel(CrosstableRoundDisplay.accessibilityLabel(round))
		}
	}

	private func tint(_ letter: String) -> Color {
		switch letter {
		case "W": Theme.win.color
		case "L", "F": Theme.loss.color
		case "D", "B", "b": Theme.draw.color
		default: Theme.dim.color
		}
	}

	private func wash(_ letter: String) -> Color {
		switch letter {
		case "W": Theme.winBg.color
		case "L", "F": Theme.lossBg.color
		default: Theme.drawBg.color
		}
	}
}
