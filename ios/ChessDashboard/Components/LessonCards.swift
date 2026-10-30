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
		FlowLayout(spacing: 6) {
			ForEach(tags, id: \.self) { TagChip($0) }
		}
	}
}

/// Left-to-right, wrapping to a new line when the next item doesn't fit.
struct FlowLayout: Layout {
	var spacing: CGFloat = 6

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let rows = arrange(subviews, width: proposal.width ?? .infinity)
		let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
		let width = rows.map(\.width).max() ?? 0
		return CGSize(width: proposal.width ?? width, height: height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var y = bounds.minY
		for row in arrange(subviews, width: bounds.width) {
			var x = bounds.minX
			for index in row.indices {
				let size = subviews[index].sizeThatFits(.unspecified)
				subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
				x += size.width + spacing
			}
			y += row.height + spacing
		}
	}

	private struct Row {
		var indices: [Int] = []
		var width: CGFloat = 0
		var height: CGFloat = 0
	}

	private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
		var rows: [Row] = []
		var row = Row()
		for index in subviews.indices {
			let size = subviews[index].sizeThatFits(.unspecified)
			let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
			if needed > width, !row.indices.isEmpty {
				rows.append(row)
				row = Row()
			}
			row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
			row.height = max(row.height, size.height)
			row.indices.append(index)
		}
		if !row.indices.isEmpty { rows.append(row) }
		return rows
	}
}
