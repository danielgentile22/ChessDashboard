import Foundation
import Observation

/// The Opponents screen: search every opponent, then records and the
/// strength buckets for the filtered Games.
@MainActor @Observable
public final class OpponentsModel {
	public let resource = ScreenResource<API.OpponentsPayload>()
	public var searchText = ""
	private let context: ScreenContext

	public init(context: ScreenContext) { self.context = context }

	public func load() async {
		await resource.load(Endpoints.getOpponents(filters: context.filters.state), in: context)
	}

	/// The opponents whose name matches the search.
	public var searchResults: [API.OpponentsListItem] {
		Self.search(resource.value?.opponents ?? [], for: searchText)
	}

	/// The strength buckets, weakest opponents first.
	public var ratingBuckets: [API.OpponentsRatingBucket] {
		let order = API.OpponentsRatingBucketBucket.allCases
		return (resource.value?.ratingBuckets ?? []).sorted {
			order.firstIndex(of: $0.bucket)! < order.firstIndex(of: $1.bucket)!
		}
	}

	/// Any part of the name, ignoring case and accents. Blank keeps everyone.
	public static func search(_ items: [API.OpponentsListItem], for query: String) -> [API.OpponentsListItem] {
		let needle = query.trimmingCharacters(in: .whitespaces)
		guard !needle.isEmpty else { return items }
		return items.filter {
			$0.opponent.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
		}
	}
}

/// One opponent's Scouting Report, the pre-game dossier. Opening it also
/// caches the pre-game review primed with this opponent, so both work on
/// club Wi-Fi that drops.
@MainActor @Observable
public final class ScoutingReportModel {
	public let resource = ScreenResource<API.OpponentPayload>()
	public let opponentID: API.OpponentId
	private let context: ScreenContext

	public init(opponentID: API.OpponentId, context: ScreenContext) {
		self.opponentID = opponentID
		self.context = context
	}

	public func load() async {
		await resource.load(
			Endpoints.getOpponent(opponentId: opponentID, filters: context.filters.state), in: context)
		if canReview, !resource.isOffline {
			await context.prefetch(
				ReviewModel.endpoint(opponentID: opponentID, lens: context.filters.state.lens))
		}
	}

	/// Their rating minus yours; positive means they're stronger.
	public var ratingGap: RatingDelta? { RatingDelta(ifKnown: resource.value?.ratingGap) }

	/// Rated X when you last played them, Y now. Nil unless both are known.
	public var thenVsNow: ThenVsNow? {
		guard let id = resource.value?.uscfIdentity, let then = id.ratingWhenLastPlayed,
			let now = id.currentRating, let change = RatingDelta(ifKnown: id.ratingChange)
		else { return nil }
		return ThenVsNow(then: then, now: now, change: change)
	}

	/// Whether there are Lessons from these Games to review before facing them.
	public var canReview: Bool { resource.value?.lessons.isEmpty == false }
}
