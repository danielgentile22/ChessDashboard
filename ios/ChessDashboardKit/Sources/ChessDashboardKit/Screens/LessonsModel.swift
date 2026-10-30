import Foundation
import Observation

/// The Lessons screen: every Lesson for the filtered Games, narrowed by Tags
/// and one opponent, plus Tag counts, recurring weaknesses, and the Coach's
/// Notes. Loading it also caches pre-game review, so review works offline.
@MainActor @Observable
public final class LessonsModel {
	public let resource = ScreenResource<API.LessonsPayload>()
	/// The Tag filter, sorted so equal selections make equal requests.
	public private(set) var selectedTags: [String] = []
	/// Narrow the list to one opponent (an opponent ID from `lessonsOpponents`).
	public var opponentID: String?
	private let context: ScreenContext

	public init(context: ScreenContext) { self.context = context }

	public func load() async {
		await resource.load(
			Endpoints.getLessons(
				tags: selectedTags.isEmpty ? nil : selectedTags, opponent: opponentID,
				filters: context.filters.state),
			in: context)
		if !resource.isOffline {
			await context.prefetch(ReviewModel.endpoint(opponentID: opponentID, lens: context.filters.state.lens))
		}
	}

	public func toggle(tag: String) {
		if let i = selectedTags.firstIndex(of: tag) {
			selectedTags.remove(at: i)
		} else {
			selectedTags = (selectedTags + [tag]).sorted()
		}
	}

	public func isSelected(_ tag: String) -> Bool { selectedTags.contains(tag) }

	public func clearTags() { selectedTags = [] }

	/// The Tag strip: the canonical taxonomy first, then freeform Tags, so
	/// fragmentation (#tactic vs #tactics) stays visible at the end.
	public var tagCounts: [API.LessonsTagCount] { Self.ordered(resource.value?.tagCounts ?? []) }

	public static func ordered(_ counts: [API.LessonsTagCount]) -> [API.LessonsTagCount] {
		counts.filter(\.canonical) + counts.filter { !$0.canonical }
	}

	/// The picked opponent's name, for the picker label and review button.
	public var opponentName: String? {
		guard let opponentID else { return nil }
		return resource.value?.lessonsOpponents.first { $0.opponentId == opponentID }?.opponent
	}
}

/// Pre-game review: a card-by-card walk through the most relevant Lessons
/// (recurring weakness, then this opponent, then recent), from the whole
/// archive. Tap to advance, back to return, then the send-off.
@MainActor @Observable
public final class ReviewModel {
	public let resource = ScreenResource<API.LessonsPayload>()
	public let opponentID: String?
	/// The card shown; `cards.count` is the send-off.
	public private(set) var index = 0
	private let context: ScreenContext

	public init(opponentID: String?, context: ScreenContext) {
		self.opponentID = opponentID
		self.context = context
	}

	/// Review reads the whole archive under the lens, so the request carries
	/// the lens alone. The cached copy then serves any filter state.
	public static func endpoint(opponentID: String?, lens: API.Lens) -> Endpoint<API.LessonsPayload> {
		var archive = FilterState.all
		archive.lens = lens
		return Endpoints.getLessons(opponent: opponentID, review: true, filters: archive)
	}

	public func load() async {
		await resource.load(Self.endpoint(opponentID: opponentID, lens: context.filters.state.lens), in: context)
		index = min(index, cards.count)
	}

	public var cards: [API.LessonsReviewCard] { resource.value?.review?.cards ?? [] }
	/// Who the review is primed for, when an opponent was given.
	public var opponent: String? { resource.value?.review?.opponent }

	public var current: API.LessonsReviewCard? { index < cards.count ? cards[index] : nil }
	public var isDone: Bool { index >= cards.count }

	/// "2 / 5"; the send-off reads "5 / 5".
	public var progress: String {
		cards.isEmpty ? "" : "\(min(index + 1, cards.count)) / \(cards.count)"
	}

	public func advance() { index = min(index + 1, cards.count) }
	public func back() { index = max(index - 1, 0) }
	public func restart() { index = 0 }
}
