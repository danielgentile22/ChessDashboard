import ChessDashboardKit
import SwiftUI

/// A Tag. Hand-written Tags (mine) are filled; engine-emitted Tags are
/// outlined with a chip icon, so the two can never be mistaken.
struct TagChip: View {
	let display: TagDisplay

	init(_ tag: API.Tag) { display = TagDisplay(tag) }

	var body: some View {
		HStack(spacing: 3) {
			if let symbol = display.symbol { Image(systemName: symbol).imageScale(.small) }
			Text(display.text)
		}
		.font(.caption.weight(.medium))
		.padding(.horizontal, 8)
		.padding(.vertical, 3)
		.foregroundStyle(display.style == .mine ? Theme.primary.color : Theme.muted.color)
		.background {
			switch display.style {
			case .mine: Capsule().fill(Theme.primaryWash.color)
			case .engine: Capsule().strokeBorder(Theme.border.color, lineWidth: 1)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(display.accessibilityLabel)
	}
}

/// When Lichess and USCF were last synced, and the warnings when a source
/// fell back or is unavailable.
struct FreshnessView: View {
	let freshness: API.MetaFreshness

	// One TimelineView per line, not around the ForEach: in a List that
	// would fold every source into a single row.
	var body: some View {
		ForEach(FreshnessSummary(freshness).lines, id: \.source) { first in
			TimelineView(.periodic(from: .now, by: 60)) { context in
				let line = FreshnessSummary(freshness, now: context.date).lines.first { $0.source == first.source } ?? first
				LabeledContent {
					Text(line.text)
						.foregroundStyle(line.isWarning ? Theme.warning.color : Theme.muted.color)
						.multilineTextAlignment(.trailing)
				} label: {
					Label(line.source, systemImage: line.isWarning ? "exclamationmark.triangle" : "clock")
				}
			}
		}
	}
}

/// What every screen shows before (or instead of) its data: a spinner on the
/// first load, an offline or error state when there is nothing cached to show.
struct ScreenState<Value: Decodable & Sendable, Content: View>: View {
	let resource: ScreenResource<Value>
	let retry: () async -> Void
	@ViewBuilder let content: (Value) -> Content

	var body: some View {
		if let value = resource.value {
			content(value)
		} else if resource.isOffline {
			ContentUnavailableView {
				Label("You're offline", systemImage: "wifi.slash")
			} description: {
				Text("This screen hasn't been loaded on this phone yet.")
			} actions: {
				Button("Try Again") { Task { await retry() } }
			}
		} else if let error = resource.error {
			ContentUnavailableView {
				Label("Couldn't load", systemImage: "exclamationmark.triangle")
			} description: {
				Text(error.message)
			} actions: {
				Button("Try Again") { Task { await retry() } }
			}
		} else {
			ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}
