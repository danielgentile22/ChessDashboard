import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Opponents and the Scouting Report")
@MainActor
struct OpponentsModelTests {
	private func context(_ api: FixtureAPIClient = FixtureAPIClient(directory: Repo.fixtures),
		cache: ResponseCache = .temporary()) -> ScreenContext
	{
		ScreenContext(
			api: api, filters: FilterStore(defaults: InMemoryKeyValueStore()), cache: cache, cacheScope: "owner")
	}

	@Test("the list loads every opponent, records, and the strength buckets in bucket order")
	func list() async {
		let model = OpponentsModel(context: context())
		await model.load()
		#expect(model.resource.value?.gamesCount == 7)
		#expect(model.searchResults.map(\.opponent) == ["Opponent A", "Opponent B", "Opponent C", "Opponent D"])
		#expect(model.ratingBuckets.map(\.bucket) == [.belowMinus200, .minus100ToMinus1, .plus100ToPlus199, .atLeastPlus200])
	}

	@Test("search matches any part of the name, ignoring case and accents")
	func search() async {
		let items = [
			API.OpponentsListItem(opponent: "José Álvarez", opponentId: "a"),
			API.OpponentsListItem(opponent: "Bob Baker", opponentId: "b"),
		]
		#expect(OpponentsModel.search(items, for: "jose").map(\.opponentId) == ["a"])
		#expect(OpponentsModel.search(items, for: " BAK ").map(\.opponentId) == ["b"])
		#expect(OpponentsModel.search(items, for: "").count == 2)
		#expect(OpponentsModel.search(items, for: "zz").isEmpty)

		let model = OpponentsModel(context: context())
		await model.load()
		model.searchText = "opponent c"
		#expect(model.searchResults.map(\.opponentId) == ["uscf-10000003"])
	}

	@Test("the list request carries the filters and the lens")
	func listFollowsFilters() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let ctx = context(api)
		ctx.filters.state.lens = .live
		await OpponentsModel(context: ctx).load()
		#expect(api.requests.last?.query.contains(URLQueryItem(name: "lens", value: "live")) == true)
	}

	@Test("a Scouting Report: record, rating gap, USCF identity then vs now")
	func report() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let model = ScoutingReportModel(opponentID: "uscf-10000001", context: context(api))
		await model.load()
		#expect(api.requests.first?.path == "opponents/uscf-10000001")
		let report = model.resource.value
		#expect(report?.record.score == "2.5/3")
		#expect(report?.games.count == 3)
		#expect(model.ratingGap == RatingDelta(115))
		#expect(model.ratingGap?.text == "+115")
		#expect(model.ratingGap?.tone == .harder)
		// No current USCF rating known: no then-vs-now line.
		#expect(model.thenVsNow == nil)
		#expect(model.canReview)
	}

	@Test("then vs now: they dropped 65 points since you last played")
	func thenVsNow() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "uscf_profile", for: "getOpponent")
		let model = ScoutingReportModel(opponentID: "uscf-20000056", context: context(api))
		await model.load()
		#expect(model.thenVsNow == ThenVsNow(then: 1465, now: 1400, change: RatingDelta(-65)))
		#expect(model.thenVsNow?.change.tone == .easier)
		#expect(model.ratingGap?.text == "-5")
		// No Lessons from these Games: nothing to review.
		#expect(!model.canReview)
	}

	@Test("an opponent with no USCF identity still renders the report")
	func lichessOnly() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "lichess_only", for: "getOpponent")
		let model = ScoutingReportModel(opponentID: "name-T3Bwb25lbnQgQQ", context: context(api))
		await model.load()
		#expect(model.resource.value?.uscfIdentity == nil)
		#expect(model.thenVsNow == nil)
		#expect(model.resource.value?.record.games == 3)
	}

	@Test("rating deltas read with a sign and a tone")
	func deltas() {
		#expect(RatingDelta(0).text == "0")
		#expect(RatingDelta(0).tone == .even)
		#expect(RatingDelta(-12).text == "-12")
		#expect(RatingDelta(-12).tone == .easier)
		#expect(RatingDelta(ifKnown: nil) == nil)
	}

	@Test("a Scouting Report opened before is readable offline")
	func reportOffline() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		await ScoutingReportModel(opponentID: "uscf-10000001", context: context(api, cache: cache)).load()

		api.fail(with: .offline)
		let reopened = ScoutingReportModel(opponentID: "uscf-10000001", context: context(api, cache: cache))
		await reopened.load()
		#expect(reopened.resource.value?.opponent == "Opponent A")
		#expect(reopened.resource.isOffline)
	}

	@Test("opening a Scouting Report readies its pre-game review for offline use")
	func reportWarmsReview() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "review", for: "getLessons")
		let cache = ResponseCache.temporary()
		await ScoutingReportModel(opponentID: "uscf-10000001", context: context(api, cache: cache)).load()

		api.fail(with: .offline)
		let review = ReviewModel(opponentID: "uscf-10000001", context: context(api, cache: cache))
		await review.load()
		#expect(review.resource.isOffline)
		#expect(review.opponent == "Opponent A")
		#expect(review.cards.count == 3)
	}

	@Test("an unknown opponent is a not-found error, not a crash")
	func unknownOpponent() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.fail("getOpponent", with: .notFound("No opponent has that ID."))
		let model = ScoutingReportModel(opponentID: "nope", context: context(api))
		await model.load()
		#expect(model.resource.value == nil)
		#expect(model.resource.error == .notFound("No opponent has that ID."))
	}
}
