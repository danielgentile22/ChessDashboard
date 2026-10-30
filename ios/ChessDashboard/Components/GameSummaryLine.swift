import ChessDashboardKit
import SwiftUI

/// One Game in a line: the result mark, "vs Opponent (rating)", then the
/// date, color and Series. Used under Lessons, in the Scouting Report, and in
/// review cards.
struct GameSummaryLine: View {
	let game: API.GameSummary
	var showOpponent = true

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 8) {
			OutcomeBadge(outcome: game.outcome)
			VStack(alignment: .leading, spacing: 2) {
				if showOpponent {
					Text("vs \(game.opponent) (\(RatingFormat.whole(game.opponentRating)))")
						.font(.subheadline.weight(.medium))
				}
				Text(details)
					.font(.caption)
					.foregroundStyle(Theme.muted.color)
			}
		}
		.accessibilityElement(children: .combine)
	}

	private var details: String {
		[game.date ?? "", game.color == .unknown ? "" : game.color.rawValue, game.series]
			.filter { !$0.isEmpty }.joined(separator: " · ")
	}
}

/// Wins, draws and losses as one proportional bar with the counts under it.
struct RecordBar: View {
	let win: Int
	let draw: Int
	let loss: Int

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			GeometryReader { geo in
				let total = max(win + draw + loss, 1)
				HStack(spacing: 1) {
					segment(win, of: total, width: geo.size.width, color: Theme.win.color)
					segment(draw, of: total, width: geo.size.width, color: Theme.draw.color)
					segment(loss, of: total, width: geo.size.width, color: Theme.loss.color)
				}
			}
			.frame(height: 6)
			.clipShape(Capsule())
			Text(RecordText.record(win: win, draw: draw, loss: loss))
				.font(.caption.monospacedDigit())
				.foregroundStyle(Theme.muted.color)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(RecordText.record(win: win, draw: draw, loss: loss))
	}

	private func segment(_ n: Int, of total: Int, width: CGFloat, color: Color) -> some View {
		color.frame(width: width * CGFloat(n) / CGFloat(total))
	}
}

/// A labelled number for a stat grid, read as one VoiceOver element.
struct StatTile: View {
	let label: String
	let value: String
	var tint: Color = Theme.text.color

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(label)
				.font(.caption)
				.foregroundStyle(Theme.muted.color)
			Text(value)
				.font(.title3.weight(.semibold).monospacedDigit())
				.foregroundStyle(tint)
				.minimumScaleFactor(0.7)
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(label): \(value)")
	}
}

extension RatingDelta.Tone {
	/// Harder (they're stronger, or climbed) reads red; easier reads green.
	var color: Color {
		switch self {
		case .harder: Theme.loss.color
		case .easier: Theme.win.color
		case .even: Theme.text.color
		}
	}
}

/// The filters keep no Games.
struct NoGamesMatch: View {
	var body: some View {
		ContentUnavailableView(
			"No Games match these filters", systemImage: "line.3.horizontal.decrease.circle",
			description: Text("Change or clear the filters to see more."))
	}
}
