import ChessDashboardKit
import SwiftUI

/// Every Lesson you wrote on Lichess, newest first: pre-game review on top,
/// recurring weaknesses, the Tag strip (counts and the Tag filter in one), an
/// opponent picker, then the Lessons and, kept apart, the Coach's Notes.
struct LessonsScreen: View {
	@Environment(AppEnvironment.self) private var env
	@State private var model: LessonsModel
	@State private var reviewing = false
	@State private var weaknessGame: GameRoute?
	private let context: ScreenContext

	init(context: ScreenContext) {
		self.context = context
		_model = State(initialValue: LessonsModel(context: context))
	}

	/// Everything that changes the request: reload when any of it does.
	private struct Query: Hashable {
		let filters: FilterState
		let tags: [String]
		let opponent: String?
	}

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { payload in
			List {
				reviewSection
				if !payload.recurringWeaknesses.isEmpty { weaknessSection(payload.recurringWeaknesses) }
				tagSection
				lessonsSection(payload)
				if !payload.coachNotes.isEmpty { coachSection(payload.coachNotes) }
			}
		}
		.screenChrome(title: "Lessons", page: .lessons, resource: model.resource)
		.task(id: Query(filters: env.filters.state, tags: model.selectedTags, opponent: model.opponentID)) {
			await model.load()
		}
		.refreshable { await model.load() }
		.navigationDestination(item: $weaknessGame) { route in
			GameDetailScreen(gameID: route.gameID, context: context)
		}
		.fullScreenCover(isPresented: $reviewing) {
			ReviewScreen(opponentID: model.opponentID, context: context)
		}
	}

	private var reviewSection: some View {
		Section {
			Button {
				reviewing = true
			} label: {
				HStack(spacing: 12) {
					Image(systemName: "rectangle.stack.fill")
						.font(.title2)
						.foregroundStyle(Theme.accent.color)
					VStack(alignment: .leading, spacing: 2) {
						Text(model.opponentName.map { "Review before facing \($0)" } ?? "Review before playing")
							.font(.headline)
						Text("Your most relevant Lessons, one card at a time. Works offline.")
							.font(.caption)
							.foregroundStyle(Theme.muted.color)
					}
				}
				.padding(.vertical, 4)
			}
			.buttonStyle(.plain)
		}
	}

	private func weaknessSection(_ weaknesses: [API.LessonsWeakness]) -> some View {
		Section {
			ForEach(weaknesses, id: \.tag) { w in
				VStack(alignment: .leading, spacing: 8) {
					Button {
						if !model.isSelected(w.tag) { model.toggle(tag: w.tag) }
					} label: {
						HStack(alignment: .top, spacing: 10) {
							Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.loss.color)
							VStack(alignment: .leading, spacing: 2) {
								Text(w.stat).font(.subheadline.weight(.semibold))
								Text(w.window).font(.caption).foregroundStyle(Theme.muted.color)
							}
							Spacer(minLength: 0)
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.accessibilityHint("Shows the Lessons tagged \(w.tag)")
					if !w.games.isEmpty { weaknessGames(w) }
				}
				.listRowBackground(Theme.lossWash2.color)
			}
		} header: {
			Text("Recurring weaknesses")
		}
	}

	/// The Games behind a weakness, numbered like the web's callout.
	private func weaknessGames(_ w: API.LessonsWeakness) -> some View {
		FlowRow {
			ForEach(Array(w.games.enumerated()), id: \.element.gameId) { index, game in
				// A Button, not a NavigationLink: in a List row a link grows a
				// disclosure chevron per chip.
				Button { weaknessGame = GameRoute(gameID: game.gameId) } label: {
					HStack(spacing: 2) {
						Text("Game \(index + 1)")
						Image(systemName: "chevron.right").imageScale(.small)
					}
					.font(.caption.weight(.medium))
					.foregroundStyle(Theme.text.color)
					.padding(.horizontal, 10)
					.padding(.vertical, 5)
					.background(Capsule().fill(Theme.lossWash3.color))
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Game \(index + 1) of \(w.games.count) behind #\(w.tag)")
				.accessibilityHint("Opens the Game")
			}
		}
		.padding(.leading, 30)
	}

	private var tagSection: some View {
		Section {
			let counts = model.tagCounts
			if counts.isEmpty {
				Text("No Tags in these Games yet").foregroundStyle(Theme.muted.color)
			} else {
				FlowRow {
					ForEach(counts, id: \.name) { count in
						TagCountChip(count: count, selected: model.isSelected(count.name)) {
							model.toggle(tag: count.name)
						}
					}
				}
				.padding(.vertical, 4)
			}
			opponentPicker
		} header: {
			HStack {
				Text("Tags")
				Spacer()
				if !model.selectedTags.isEmpty {
					Button("Clear") { model.clearTags() }.font(.caption)
				}
			}
		} footer: {
			Text("Tap Tags to filter. Freeform Tags (outside the usual set) are dashed; the chip icon marks engine Tags.")
		}
	}

	private var opponentPicker: some View {
		Picker("Opponent", selection: $model.opponentID) {
			Text("All opponents").tag(String?.none)
			ForEach(model.resource.value?.lessonsOpponents ?? [], id: \.opponentId) { o in
				Text(o.opponent).tag(Optional(o.opponentId))
			}
		}
	}

	private func lessonsSection(_ payload: API.LessonsPayload) -> some View {
		Section {
			if payload.lessons.isEmpty {
				LessonConvention()
			}
			ForEach(Array(payload.lessons.enumerated()), id: \.offset) { _, lesson in
				NavigationLink(value: GameRoute(gameID: lesson.game.gameId)) {
					LessonCardBody(text: lesson.text, game: lesson.game)
				}
			}
		} header: {
			Text(payload.lessons.count == 1 ? "1 Lesson" : "\(payload.lessons.count) Lessons")
		}
	}

	private func coachSection(_ notes: [API.LessonsCoachNote]) -> some View {
		Section {
			ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
				NavigationLink(value: GameRoute(gameID: note.game.gameId)) {
					CoachNoteBody(note: note)
				}
				.listRowBackground(Theme.primaryWash2.color)
			}
		} header: {
			Label("Coach's Notes", systemImage: "person.crop.circle.badge.checkmark")
				.foregroundStyle(Theme.primary.color)
		} footer: {
			Text("What your coach has told you, newest first. Your own Lessons are above.")
		}
	}
}

/// A Tag in the strip: its count, how many came from the engine, selected
/// or not. Freeform Tags get a dashed outline so fragmentation shows.
private struct TagCountChip: View {
	let count: API.LessonsTagCount
	let selected: Bool
	let toggle: () -> Void

	var body: some View {
		Button(action: toggle) {
			HStack(spacing: 4) {
				Text("#\(count.name)")
				Text("\(count.count)").monospacedDigit().foregroundStyle(Theme.muted.color)
				if count.engineCount > 0 {
					// All from the engine: the icon alone; a mix: the engine's share.
					Image(systemName: "cpu").imageScale(.small)
					if count.mineCount > 0 { Text("\(count.engineCount)").monospacedDigit() }
				}
			}
			.font(.caption.weight(.medium))
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.foregroundStyle(Theme.text.color)
			// Neutral fills, so the strip never borrows TagChip's looks (a
			// blue wash means a hand-written Tag, an outline an engine one).
			.background {
				if selected {
					Capsule().fill(Theme.primary.color)
				} else {
					Capsule().fill(Theme.card2.color)
				}
			}
			.overlay {
				if !selected && !count.canonical {
					Capsule().strokeBorder(Theme.dim.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
				}
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel(accessibilityText)
		.accessibilityAddTraits(selected ? .isSelected : [])
	}

	private var accessibilityText: String {
		var text = "Tag \(count.name), \(count.count) Games"
		if count.engineCount > 0 { text += ", \(count.engineCount) from the engine" }
		if !count.canonical { text += ", freeform" }
		return text
	}
}

/// The empty state: how Lessons and Tags are written on Lichess (ADR 0002).
private struct LessonConvention: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("No Lessons here yet").font(.headline)
			Text("On Lichess, write a comment on any Chapter starting with \u{201C}Lesson:\u{201D}. It becomes that Game's Lesson here after the next Sync.")
			Text("Add Tags like #endgame or #time-trouble anywhere in your comments to group what each Game taught you.")
		}
		.font(.subheadline)
		.foregroundStyle(Theme.muted.color)
		.padding(.vertical, 6)
	}
}
