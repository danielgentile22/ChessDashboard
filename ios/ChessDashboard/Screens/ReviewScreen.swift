import ChessDashboardKit
import SwiftUI

/// Pre-game review: full screen, one Lesson at a time, for the minutes
/// before a round. Tap the card to advance; Back sits at thumb reach. Reads
/// the cached copy when the club Wi-Fi is down.
struct ReviewScreen: View {
	@Environment(\.dismiss) private var dismiss
	@State private var model: ReviewModel

	init(opponentID: String?, context: ScreenContext) {
		_model = State(initialValue: ReviewModel(opponentID: opponentID, context: context))
	}

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				if model.resource.isOffline { OfflineBanner(cachedAt: model.resource.cachedAt) }
				ScreenState(resource: model.resource, retry: model.load) { _ in
					if model.cards.isEmpty {
						ContentUnavailableView {
							Label("Nothing to review yet", systemImage: "rectangle.stack")
						} description: {
							Text("Write a comment starting with \u{201C}Lesson:\u{201D} on any Chapter on Lichess and it will show up here.")
						}
					} else {
						deck
					}
				}
			}
			.background(Theme.bg.color)
			.navigationTitle("Pre-game review")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
				if let opponent = model.opponent {
					ToolbarItem(placement: .principal) {
						VStack(spacing: 0) {
							Text("Pre-game review").font(.headline)
							Text("vs \(opponent)").font(.caption).foregroundStyle(Theme.muted.color)
						}
					}
				}
			}
			.gameDestination()
		}
		.task { await model.load() }
	}

	private var deck: some View {
		VStack(spacing: 16) {
			Group {
				if let card = model.current {
					ReviewCard(card: card)
				} else {
					SendOff()
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.padding(20)
			.background(RoundedRectangle(cornerRadius: 16).fill(Theme.card.color))
			.contentShape(RoundedRectangle(cornerRadius: 16))
			// A tap anywhere on the card advances; the Game link inside it
			// still takes its own taps.
			.onTapGesture { withAnimation(.snappy) { model.advance() } }
			.accessibilityAction(named: "Next Lesson") { model.advance() }
			.id(model.index)
			.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))

			HStack {
				Button {
					withAnimation(.snappy) { model.back() }
				} label: {
					Label("Back", systemImage: "chevron.left")
				}
				.disabled(model.index == 0)
				Spacer()
				Text(model.progress)
					.font(.subheadline.monospacedDigit())
					.foregroundStyle(Theme.muted.color)
					.accessibilityLabel("Card \(model.progress.replacingOccurrences(of: " / ", with: " of "))")
				Spacer()
				if model.isDone {
					Button("Start over") { withAnimation(.snappy) { model.restart() } }
				} else {
					Text("Tap card to continue")
						.font(.caption)
						.foregroundStyle(Theme.dim.color)
				}
			}
		}
		.padding()
	}
}

/// One card: why it's here, the Lesson, and the Game it came from.
private struct ReviewCard: View {
	let card: API.LessonsReviewCard

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			Text(card.reason)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(card.reasonKind == .recurringWeakness ? Theme.loss.color : Theme.accent.color)
			Text(card.text)
				.font(.title2.weight(.medium))
				.frame(maxWidth: .infinity, alignment: .leading)
			Spacer(minLength: 0)
			VStack(alignment: .leading, spacing: 8) {
				NavigationLink(value: GameRoute(gameID: card.game.gameId)) {
					HStack {
						GameSummaryLine(game: card.game)
						Spacer()
						Image(systemName: "chevron.right").foregroundStyle(Theme.dim.color)
					}
				}
				.buttonStyle(.plain)
				.accessibilityHint("Opens the Game")
				if !card.game.tags.isEmpty { TagFlow(tags: card.game.tags) }
			}
		}
	}
}

private struct SendOff: View {
	var body: some View {
		VStack(spacing: 12) {
			Text("\u{265F}").font(.system(size: 56)).foregroundStyle(Theme.accent.color).accessibilityHidden(true)
			Text("That's everything.").font(.title2.weight(.semibold))
			Text("Now go play.").foregroundStyle(Theme.muted.color)
		}
		.accessibilityElement(children: .combine)
	}
}
