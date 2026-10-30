import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Lessons and pre-game review")
@MainActor
struct LessonsModelTests {
	private func context(_ api: FixtureAPIClient, cache: ResponseCache = .temporary()) -> ScreenContext {
		ScreenContext(
			api: api, filters: FilterStore(defaults: InMemoryKeyValueStore()), cache: cache, cacheScope: "owner")
	}

	private func fixtures(_ variant: String? = nil) -> FixtureAPIClient {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: variant, for: "getLessons")
		return api
	}

	@Test("Lessons, Tag counts with their sources, and recurring weaknesses")
	func lessons() async {
		let model = LessonsModel(context: context(fixtures("weakness")))
		await model.load()
		let payload = model.resource.value
		#expect(payload?.lessons.count == 3)
		#expect(payload?.lessons.first?.game.tags == [API.Tag(name: "opening", source: .mine)])
		#expect(model.tagCounts.map(\.name) == ["opening", "tactics", "endgame", "time-trouble", "blunder", "strategy"])
		#expect(payload?.recurringWeaknesses.first?.tag == "time-trouble")
	}

	@Test("canonical Tags come first, freeform Tags after, both kept")
	func tagOrder() {
		let counts = [
			API.LessonsTagCount(canonical: false, count: 4, engineCount: 0, mineCount: 4, name: "my-idea"),
			API.LessonsTagCount(canonical: true, count: 1, engineCount: 1, mineCount: 0, name: "endgame"),
			API.LessonsTagCount(canonical: false, count: 1, engineCount: 0, mineCount: 1, name: "zz"),
			API.LessonsTagCount(canonical: true, count: 2, engineCount: 0, mineCount: 2, name: "tactics"),
		]
		#expect(LessonsModel.ordered(counts).map(\.name) == ["endgame", "tactics", "my-idea", "zz"])
	}

	@Test("Tag filter: toggling Tags narrows the request, sorted, and toggles back off")
	func tagFilter() async {
		let api = fixtures()
		let model = LessonsModel(context: context(api))
		model.toggle(tag: "tactics")
		model.toggle(tag: "endgame")
		await model.load()
		let tags = api.requests.first { $0.query.contains { $0.name == "review" } == false }?
			.query.filter { $0.name == "tags" }.map(\.value)
		#expect(tags == ["endgame", "tactics"])
		#expect(model.isSelected("tactics"))

		model.toggle(tag: "tactics")
		model.toggle(tag: "endgame")
		#expect(model.selectedTags.isEmpty)
	}

	@Test("the opponent picker narrows the list by opponent ID")
	func opponentFilter() async {
		let api = fixtures()
		let model = LessonsModel(context: context(api))
		model.opponentID = "uscf-10000001"
		await model.load()
		#expect(api.requests.first?.query.contains(URLQueryItem(name: "opponent", value: "uscf-10000001")) == true)
		#expect(model.opponentName == "Opponent A")
	}

	@Test("no Lessons: an empty list, not an error")
	func empty() async {
		let model = LessonsModel(context: context(fixtures("review")))
		await model.load()
		#expect(model.resource.value?.lessons.isEmpty == true)
		#expect(model.resource.error == nil)
	}

	@Test("Coach's Notes arrive separately from the Lessons")
	func coachNotes() async {
		let model = LessonsModel(context: context(fixtures("coach_notes")))
		await model.load()
		#expect(model.resource.value?.coachNotes.count == 1)
		#expect(model.resource.value?.lessons.isEmpty == true)
	}

	@Test("the review request reads the whole archive: lens only, no filters, no Tags")
	func reviewRequest() {
		var state = FilterState()
		state.colors = [.white]
		state.lens = .live
		let request = ReviewModel.endpoint(opponentID: "uscf-10000001", lens: state.lens).request
		#expect(request.query == [
			URLQueryItem(name: "lens", value: "live"),
			URLQueryItem(name: "opponent", value: "uscf-10000001"),
			URLQueryItem(name: "review", value: "true"),
		])
	}

	@Test("review mode: tap through every card, back, then the send-off")
	func reviewFlow() async {
		let model = ReviewModel(opponentID: nil, context: context(fixtures("weakness")))
		await model.load()
		#expect(model.cards.count == 3)
		#expect(model.current?.reasonKind == .recurringWeakness)
		#expect(model.progress == "1 / 3")
		model.back()
		#expect(model.index == 0)
		model.advance()
		model.advance()
		#expect(model.progress == "3 / 3")
		model.advance()
		#expect(model.isDone && model.current == nil)
		#expect(model.progress == "3 / 3")
		model.advance()
		#expect(model.index == 3)
		model.back()
		#expect(model.current?.reasonKind == .recent)
	}

	@Test("review mode primed with an opponent")
	func reviewOpponent() async {
		let model = ReviewModel(opponentID: "uscf-10000001", context: context(fixtures("review")))
		await model.load()
		#expect(model.opponent == "Opponent A")
		#expect(model.cards.allSatisfy { $0.reasonKind == .facingOpponent })
	}

	@Test("review mode works offline after the Lessons screen loaded once")
	func reviewOffline() async {
		let api = fixtures("weakness")
		let cache = ResponseCache.temporary()
		await LessonsModel(context: context(api, cache: cache)).load()

		api.fail(with: .offline)
		let review = ReviewModel(opponentID: nil, context: context(api, cache: cache))
		await review.load()
		#expect(review.resource.isOffline)
		#expect(review.cards.count == 3)
	}

	@Test("review mode still works offline after the filters changed")
	func reviewOfflineAcrossFilters() async {
		let api = fixtures("weakness")
		let cache = ResponseCache.temporary()
		await LessonsModel(context: context(api, cache: cache)).load()

		api.fail(with: .offline)
		let ctx = context(api, cache: cache)
		ctx.filters.state.colors = [.black]
		let review = ReviewModel(opponentID: nil, context: ctx)
		await review.load()
		#expect(review.cards.count == 3)
	}

	@Test("the Lessons list is readable offline from the cache")
	func lessonsOffline() async {
		let api = fixtures("weakness")
		let cache = ResponseCache.temporary()
		await LessonsModel(context: context(api, cache: cache)).load()
		api.fail(with: .offline)
		let reopened = LessonsModel(context: context(api, cache: cache))
		await reopened.load()
		#expect(reopened.resource.isOffline)
		#expect(reopened.resource.value?.lessons.count == 3)
	}

	@Test("with nothing to review the queue is empty and already done")
	func reviewEmpty() async {
		let model = ReviewModel(opponentID: nil, context: context(fixtures()))
		await model.load()
		#expect(model.cards.isEmpty)
		#expect(model.current == nil)
	}
}
