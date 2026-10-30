import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Analysis")
@MainActor
struct AnalysisModelTests {
	private func context(_ api: FixtureAPIClient, cache: ResponseCache = .temporary()) -> ScreenContext {
		ScreenContext(
			api: api, filters: FilterStore(defaults: InMemoryKeyValueStore()), cache: cache, cacheScope: "owner")
	}

	@Test("the Error Profile, trends, matrix, histogram, and the awaiting list")
	func analysis() async {
		let model = AnalysisModel(context: context(FixtureAPIClient(directory: Repo.fixtures)))
		await model.load()
		let payload = model.resource.value
		#expect(payload?.hasAnalysis == true)
		#expect(payload?.mistakeTypeDistribution == API.AnalysisMistakeTypeDistribution(positional: 1, tactical: 0))
		#expect(payload?.accuracyTrend.first?.accuracy == 94.55)
		#expect(payload?.awaitingAnalysis.count == 62)
		#expect(model.hottestCell == PhaseCell(phase: .middlegame, kind: .positional, count: 1))
	}

	@Test("the route takes no filters, like the web page")
	func noFilters() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let ctx = context(api)
		ctx.filters.state.colors = [.white]
		await AnalysisModel(context: ctx).load()
		#expect(api.requests.first?.query.isEmpty == true)
	}

	@Test("no analyzed Games: the empty state still lists what awaits analysis")
	func empty() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "empty", for: "getAnalysis")
		let model = AnalysisModel(context: context(api))
		await model.load()
		#expect(model.resource.value?.hasAnalysis == false)
		#expect(model.resource.value?.awaitingAnalysis.count == 7)
		#expect(model.hottestCell == nil)
	}

	@Test("offline: the cached Analysis shows")
	func offline() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		await AnalysisModel(context: context(api, cache: cache)).load()
		api.fail(with: .offline)
		let reopened = AnalysisModel(context: context(api, cache: cache))
		await reopened.load()
		#expect(reopened.resource.isOffline && reopened.resource.value != nil)
	}

	@Test("the hottest cell is the largest count; ties go to the earlier phase, tactical first")
	func hottest() {
		let rows = [
			API.AnalysisPhaseRow(phase: .opening, positional: 2, tactical: 3),
			API.AnalysisPhaseRow(phase: .endgame, positional: 3, tactical: 0),
		]
		#expect(AnalysisModel.hottestCell(rows) == PhaseCell(phase: .opening, kind: .tactical, count: 3))
		#expect(AnalysisModel.hottestCell([API.AnalysisPhaseRow(phase: .opening, positional: 0, tactical: 0)]) == nil)
	}

	@Test("the rating overlay maps ratings onto the chart's axis and back")
	func overlay() throws {
		let overlay = try #require(RatingOverlay(ratings: [1400, 1600], onto: 0...100))
		#expect(overlay.plotted(1400) == 0)
		#expect(overlay.plotted(1600) == 100)
		#expect(overlay.plotted(1500) == 50)
		#expect(overlay.rating(atPlotted: 25) == 1450)
		#expect(RatingOverlay(ratings: [], onto: 0...100) == nil)
		// One rating still gets a usable band around it.
		let single = try #require(RatingOverlay(ratings: [1506], onto: 0...10))
		#expect(single.plotted(1506) == 5)
	}
}
