import ChessDashboardKit
import SwiftUI

/// One of your Lessons: the takeaway, the Game it came from, and that Game's
/// Tags (mine filled, engine outlined).
struct LessonCardBody: View {
	let text: String
	let game: API.GameSummary
	var showOpponent = true

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Image(systemName: "lightbulb.fill")
					.foregroundStyle(Theme.accent.color)
					.accessibilityHidden(true)
				Text(text).font(.body)
			}
			GameSummaryLine(game: game, showOpponent: showOpponent)
			if !game.tags.isEmpty { TagFlow(tags: game.tags) }
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("Lesson: \(text)")
	}
}

/// One of your coach's notes. Deliberately unlike a Lesson (the king mark,
/// blue rule, "Coach" label), so a coach's advice never reads as your own
/// takeaway.
struct CoachNoteBody: View {
	let note: API.LessonsCoachNote

	var body: some View {
		HStack(alignment: .top, spacing: 10) {
			RoundedRectangle(cornerRadius: 1.5)
				.fill(Theme.primary.color)
				.frame(width: 3)
			VStack(alignment: .leading, spacing: 6) {
				HStack(alignment: .firstTextBaseline, spacing: 6) {
					Text("\u{265A}").foregroundStyle(Theme.primary.color).accessibilityHidden(true)
					Text(note.text).font(.body.italic())
				}
				Text(meta)
					.font(.caption)
					.foregroundStyle(Theme.muted.color)
			}
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("Coach's note: \(note.text). \(meta)")
	}

	private var meta: String {
		let game = note.game
		let whereInGame = note.moveNumber > 0 ? "move \(note.moveNumber)" : "before the Game"
		return ["vs \(game.opponent)", game.outcome == .unknown ? "" : game.outcome.rawValue, game.date ?? "", whereInGame]
			.filter { !$0.isEmpty }.joined(separator: " · ")
	}
}

/// Tag chips that wrap onto as many lines as they need.
struct TagFlow: View {
	let tags: [API.Tag]

	var body: some View {
		FlowRow {
			ForEach(tags, id: \.self) { TagChip($0) }
		}
	}
}
