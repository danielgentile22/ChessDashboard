import ChessDashboardKit
import SwiftUI

/// One Game as a list row, wherever Games are listed: outcome, opponent and
/// ratings first, then date, Series, round, and opening, then Tags and the
/// USCF match status. Wrap it in `NavigationLink(value: GameRoute(...))`.
struct GameSummaryRow: View {
	let game: API.GameSummary
	/// The round to show when the caller knows the real one (crosstable).
	var round: Int?
	var showsUscfStatus = true

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				OutcomeBadge(outcome: game.outcome)
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 4) {
						Text("vs \(game.opponent)").font(.body.weight(.semibold))
						if game.hasLesson {
							Image(systemName: "lightbulb.fill")
								.foregroundStyle(Theme.accent.color)
								.imageScale(.small)
								.accessibilityLabel("Has a Lesson")
						}
					}
					Text(ratingsLine).font(.subheadline).foregroundStyle(Theme.muted.color).monospacedDigit()
				}
				Spacer(minLength: 0)
			}
			Text(contextLine).font(.footnote).foregroundStyle(Theme.muted.color).lineLimit(2)
			if !game.tags.isEmpty || (showsUscfStatus && game.uscfStatus != .unmatched) {
				FlowRow {
					if showsUscfStatus { UscfStatusBadge(status: game.uscfStatus) }
					ForEach(game.tags, id: \.self) { TagChip($0) }
				}
			}
		}
		.padding(.vertical, 2)
		.accessibilityElement(children: .combine)
	}

	private var ratingsLine: String {
		let color = game.color == .unknown ? "" : "\(game.color.rawValue) · "
		return color + "\(RatingFormat.whole(game.opponentRating)) opponent · me \(RatingFormat.whole(game.playerRating))"
	}

	private var contextLine: String {
		var bits: [String] = []
		if let date = game.date { bits.append(date) }
		if !game.series.isEmpty {
			let r = round ?? game.round
			bits.append(game.series + (r.map { " R\($0)" } ?? ""))
		}
		let opening = [game.eco, game.opening].filter { !$0.isEmpty }.joined(separator: " ")
		if !opening.isEmpty { bits.append(opening) }
		if let moves = game.moves { bits.append("\(moves) moves") }
		return bits.joined(separator: " · ")
	}
}

/// W, D, or L on the outcome's color.
struct OutcomeBadge: View {
	let outcome: API.GameOutcome
	@ScaledMetric(relativeTo: .body) private var size = 26.0

	var body: some View {
		Text(letter)
			.font(.subheadline.weight(.bold))
			.foregroundStyle(tint)
			.frame(width: size, height: size)
			.background(RoundedRectangle(cornerRadius: 6).fill(wash))
			.accessibilityLabel(outcome.rawValue)
	}

	private var letter: String {
		switch outcome {
		case .win: "W"
		case .draw: "D"
		case .loss: "L"
		case .unknown: "?"
		}
	}

	private var tint: Color {
		switch outcome {
		case .win: Theme.win.color
		case .loss: Theme.loss.color
		case .draw, .unknown: Theme.draw.color
		}
	}

	private var wash: Color {
		switch outcome {
		case .win: Theme.winBg.color
		case .loss: Theme.lossBg.color
		case .draw, .unknown: Theme.drawBg.color
		}
	}
}

/// The USCF match status as a small badge; nothing when unmatched.
struct UscfStatusBadge: View {
	let display: UscfStatusDisplay

	init(status: API.UscfMatchStatus) { display = UscfStatusDisplay(status) }

	var body: some View {
		if let symbol = display.symbol {
			Label(display.label, systemImage: symbol)
				.font(.caption.weight(.medium))
				.labelStyle(.titleAndIcon)
				.padding(.horizontal, 8)
				.padding(.vertical, 3)
				.foregroundStyle(tint)
				.background(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(display.accessibilityLabel)
		}
	}

	private var tint: Color {
		switch display.tone {
		case .good: Theme.win.color
		case .caution: Theme.accent.color
		case .warning: Theme.warning.color
		case .neutral: Theme.muted.color
		}
	}
}

/// Lays chips out left to right, wrapping to new lines.
struct FlowRow: Layout {
	var spacing: CGFloat = 6

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
		let width = rows.map(\.width).max() ?? 0
		let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
		return CGSize(width: width, height: height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var y = bounds.minY
		for row in arrange(width: bounds.width, subviews: subviews) {
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

	private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
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
