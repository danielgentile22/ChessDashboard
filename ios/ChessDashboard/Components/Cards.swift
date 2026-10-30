import ChessDashboardKit
import SwiftUI

/// A titled card on the dark theme, like the web's chart and content cards.
struct DashboardCard<Content: View>: View {
	let title: String
	var subtitle: String?
	@ViewBuilder let content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.headline)
					.foregroundStyle(Theme.text.color)
					.accessibilityAddTraits(.isHeader)
				if let subtitle {
					Text(subtitle).font(.caption).foregroundStyle(Theme.muted.color)
				}
			}
			content
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Theme.card.color, in: RoundedRectangle(cornerRadius: 12))
		.overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border.color, lineWidth: 1))
	}
}

/// "No data" inside a card: an empty chart must never look like a bug.
struct CardEmptyText: View {
	let text: String

	init(_ text: String) { self.text = text }

	var body: some View {
		Text(text)
			.font(.subheadline)
			.foregroundStyle(Theme.dim.color)
			.frame(maxWidth: .infinity, minHeight: 60)
	}
}

/// The screen-wide empty state when the filters match no Games.
struct NoGamesView: View {
	var body: some View {
		ContentUnavailableView(
			"No Games match these filters", systemImage: "line.3.horizontal.decrease.circle",
			description: Text("Change or reset the filters to see your Games."))
	}
}

extension API.OverviewFormOutcome {
	var themeColor: Color {
		switch self {
		case .win: Theme.win.color
		case .draw: Theme.draw.color
		case .loss: Theme.loss.color
		case .unknown: Theme.dim.color
		}
	}
}

extension API.Outcome {
	var themeColor: Color {
		switch self {
		case .win: Theme.win.color
		case .draw: Theme.draw.color
		case .loss: Theme.loss.color
		}
	}
}
