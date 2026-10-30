import ChessDashboardKit
import SwiftUI

/// The owner's toolbar Sync action. A spinner while the server Syncs.
struct SyncButton: View {
	@Environment(AppEnvironment.self) private var env

	var body: some View {
		if env.sync.isRunning {
			ProgressView()
				.accessibilityLabel("Syncing")
		} else {
			Button {
				Task { await env.runSync() }
			} label: {
				Label("Sync", systemImage: "arrow.triangle.2.circlepath")
			}
			.accessibilityHint("Pulls new Games from your Lichess Studies")
		}
	}
}

/// The Sync outcome, like the web toast and celebration banner: new Games,
/// personal bests and USCF achievements, or why it failed. Tapping a new
/// Game opens it. Success and warnings dismiss themselves; a failure stays
/// until dismissed.
struct SyncToast: View {
	let report: SyncReport
	let dismiss: () -> Void

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: symbol)
				.font(.title3)
				.foregroundStyle(tint)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 4) {
				Text(report.title).font(.subheadline.weight(.semibold))
				Text(report.message).font(.footnote)
				ForEach(report.newGameLinks, id: \.self) { link in
					// Pushes onto the screen's NavigationStack (every tab root
					// registers `gameDestination`); the toast goes with it.
					NavigationLink(value: link.route) {
						HStack(spacing: 4) {
							Text(link.label)
							Image(systemName: "chevron.right").imageScale(.small)
						}
						.font(.footnote.weight(.medium))
						.foregroundStyle(Theme.primary.color)
						.frame(minHeight: 28)
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.simultaneousGesture(TapGesture().onEnded { dismiss() })
					.accessibilityHint("Opens the Game")
				}
				ForEach(report.celebrations, id: \.self) { line in
					Label(line, systemImage: "trophy.fill")
						.font(.footnote.weight(.medium))
						.foregroundStyle(Theme.accent.color)
				}
				if let syncedAt = report.syncedAt {
					Text("Lichess synced \(syncedAt, format: .relative(presentation: .named))")
						.font(.caption)
						.foregroundStyle(Theme.muted.color)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			Button(action: dismiss) {
				Image(systemName: "xmark")
					.font(.footnote.weight(.semibold))
					.foregroundStyle(Theme.muted.color)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Dismiss")
		}
		.foregroundStyle(Theme.text.color)
		.padding()
		.background(Theme.card2.color, in: .rect(cornerRadius: 14))
		.overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.6)))
		.shadow(color: .black.opacity(0.35), radius: 12, y: 4)
		// Contain, not combine: each new Game stays its own button.
		.accessibilityElement(children: report.newGameLinks.isEmpty ? .combine : .contain)
		.accessibilityAddTraits(.updatesFrequently)
		.task(id: report) {
			guard report.style != .failure else { return }
			try? await Task.sleep(for: .seconds(report.celebrations.isEmpty ? 6 : 10))
			if !Task.isCancelled { dismiss() }
		}
	}

	private var symbol: String {
		switch report.style {
		case .success: "checkmark.circle.fill"
		case .warning: "clock.arrow.circlepath"
		case .failure: "exclamationmark.triangle.fill"
		}
	}

	private var tint: Color {
		switch report.style {
		case .success: Theme.win.color
		case .warning: Theme.warning.color
		case .failure: Theme.loss.color
		}
	}
}
