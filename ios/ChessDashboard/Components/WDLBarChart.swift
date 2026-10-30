import Charts
import ChessDashboardKit
import SwiftUI

/// A horizontal stacked Win/Draw/Loss bar chart (ECO families, Series
/// performance). Touch a bar to read its counts.
struct WDLBarChart: View {
	struct Bar: Identifiable {
		let id: String
		let label: String
		let win: Int
		let draw: Int
		let loss: Int
		var total: Int { win + draw + loss }
	}

	let bars: [Bar]
	let summary: String
	@State private var selected: String?

	private struct Segment: Identifiable {
		let bar: Bar
		let outcome: String
		let count: Int
		var id: String { bar.id + outcome }
	}

	private var segments: [Segment] {
		bars.flatMap { bar in
			[Segment(bar: bar, outcome: "Win", count: bar.win),
			 Segment(bar: bar, outcome: "Draw", count: bar.draw),
			 Segment(bar: bar, outcome: "Loss", count: bar.loss)]
		}
	}

	var body: some View {
		Chart(segments) { segment in
			BarMark(x: .value("Games", segment.count), y: .value("Group", segment.bar.label))
				.foregroundStyle(by: .value("Outcome", segment.outcome))
				.opacity(selected == nil || selected == segment.bar.label ? 1 : 0.4)
				.accessibilityLabel(segment.bar.label)
				.accessibilityValue("\(segment.count) \(segment.outcome == "Loss" ? "losses" : segment.outcome.lowercased() + (segment.count == 1 ? "" : "s"))")
		}
		.chartForegroundStyleScale([
			"Win": Theme.win.color, "Draw": Theme.draw.color, "Loss": Theme.loss.color,
		])
		.chartYSelection(value: $selected)
		.chartXAxisLabel("Games")
		.chartLegend(position: .bottom)
		.frame(height: max(CGFloat(bars.count) * 34 + 60, 160))
		.overlay(alignment: .topTrailing) {
			if let label = selected, let bar = bars.first(where: { $0.label == label }) {
				VStack(alignment: .trailing, spacing: 2) {
					Text(bar.label).font(.caption.weight(.semibold))
					Text(RecordText.recordWithGames(win: bar.win, draw: bar.draw, loss: bar.loss))
						.font(.caption).monospacedDigit()
				}
				.padding(8)
				.background(RoundedRectangle(cornerRadius: 8).fill(Theme.card2.color))
				.allowsHitTesting(false)
			}
		}
		.accessibilityLabel(summary)
	}
}
