import Foundation
import Testing
@testable import ChessDashboardKit

@MainActor
private func fixtureContext(
	_ api: FixtureAPIClient = FixtureAPIClient(directory: Repo.fixtures), cache: ResponseCache = .temporary()
) -> ScreenContext {
	ScreenContext(api: api, filters: FilterStore(defaults: InMemoryKeyValueStore()), cache: cache, cacheScope: "owner")
}

@Suite("Games screen")
@MainActor
struct GamesModelTests {
	@Test("loads every filtered Game in archive order")
	func loads() async {
		let model = GamesModel(context: fixtureContext())
		await model.load()
		#expect(model.resource.value?.gamesCount == 7)
		#expect(model.visibleGames.map(\.gameId) == (1...7).map { "chap000\($0)" })
	}

	@Test("search matches opponent, opening, ECO, Series, and Tags, case-insensitively")
	func search() async {
		let model = GamesModel(context: fixtureContext())
		await model.load()
		model.searchText = "opponent a"
		#expect(model.visibleGames.map(\.gameId) == ["chap0001", "chap0004", "chap0007"])
		model.searchText = "caro"
		#expect(model.visibleGames.map(\.gameId) == ["chap0002", "chap0006"])
		model.searchText = "E04"
		#expect(model.visibleGames.map(\.gameId) == ["chap0001", "chap0007"])
		model.searchText = "summer"
		#expect(model.visibleGames.count == 4)
		model.searchText = "#tactics"
		#expect(model.visibleGames.map(\.gameId) == ["chap0003", "chap0005"])
		model.searchText = "  "
		#expect(model.visibleGames.count == 7)
		model.searchText = "nobody"
		#expect(model.visibleGames.isEmpty)
	}

	@Test("sorts by date, opponent rating, and length")
	func sort() async {
		let model = GamesModel(context: fixtureContext())
		await model.load()
		model.sort = .newest
		#expect(model.visibleGames.first?.gameId == "chap0007")
		#expect(model.visibleGames.last?.gameId == "chap0001")
		model.sort = .oldest
		#expect(model.visibleGames.first?.gameId == "chap0001")
		model.sort = .strongestOpponent
		#expect(model.visibleGames.first?.opponentRating == 2050)
		#expect(model.visibleGames.last?.opponentRating == 1600)
		model.sort = .longest
		#expect(model.visibleGames.first?.moves == 6)
	}

	@Test("USCF match status reads like the web table")
	func uscfStatus() {
		#expect(UscfStatusDisplay(.matchedById).label == "Matched")
		#expect(UscfStatusDisplay(.matchedByName).label == "Matched by name")
		#expect(UscfStatusDisplay(.conflict).label == "Sources disagree")
		#expect(UscfStatusDisplay(.forfeit).label == "Forfeit")
		#expect(UscfStatusDisplay(.unmatched).symbol == nil)
		#expect(UscfStatusDisplay(.unmatched).accessibilityLabel == "No USCF Game Record")
	}

	@Test("empty filter result")
	func empty() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.set(Data(#"{"games": [], "games_count": 0}"#.utf8), for: "getGames")
		let model = GamesModel(context: fixtureContext(api))
		await model.load()
		#expect(model.resource.value?.gamesCount == 0)
		#expect(model.visibleGames.isEmpty)
	}

	@Test("offline shows the cached Games")
	func offline() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		await GamesModel(context: fixtureContext(api, cache: cache)).load()
		api.fail(with: .offline)
		let model = GamesModel(context: fixtureContext(api, cache: cache))
		await model.load()
		#expect(model.resource.isOffline)
		#expect(model.visibleGames.count == 7)
	}
}

@Suite("Openings screen")
@MainActor
struct OpeningsModelTests {
	@Test("the repertoire tree follows the color picker")
	func tree() async {
		let model = OpeningsModel(context: fixtureContext())
		await model.load()
		#expect(model.tree?.gameCount == 4)
		#expect(model.tree?.moves.map(\.san) == ["d4", "e4"])
		model.color = .black
		#expect(model.tree?.gameCount == 3)
		#expect(model.tree?.scorePct == 83.3)
	}

	@Test("move labels number White and Black moves like the web")
	func moveLabels() {
		#expect(RepertoireDisplay.moveLabel(ply: 1, san: "d4") == "1. d4")
		#expect(RepertoireDisplay.moveLabel(ply: 2, san: "Nf6") == "1... Nf6")
		#expect(RepertoireDisplay.moveLabel(ply: 5, san: "Bb5") == "3. Bb5")
	}

	@Test("a branch's score is marked against the color's baseline")
	func marks() async throws {
		let model = OpeningsModel(context: fixtureContext())
		await model.load()
		let tree = try #require(model.tree)
		let d4 = try #require(tree.moves.first)
		#expect(d4.underperforming)
		#expect(RepertoireDisplay.mark(d4, baseline: tree.scorePct) == .below)
		#expect(RepertoireDisplay.mark(tree.moves[1], baseline: tree.scorePct) == .above)
		#expect(RepertoireDisplay.mark(d4, baseline: d4.scorePct) == .at)
	}

	@Test("a drill-down line resolves to its node, and stops resolving when filters remove it")
	func lines() async throws {
		let model = OpeningsModel(context: fixtureContext())
		await model.load()
		let d4 = try #require(model.tree?.moves.first)
		let child = try #require(d4.moves.first)
		let line = RepertoireLine(color: .white, sans: ["d4", child.san])
		#expect(model.node(at: line) == child)
		#expect(model.node(at: RepertoireLine(color: .white, sans: ["d4"]))?.gameCount == 3)
		#expect(model.node(at: RepertoireLine(color: .white, sans: ["h4"])) == nil)
		#expect(model.node(at: RepertoireLine(color: .black, sans: ["e4"]))?.gameCount == 2)
		#expect(line.appending(child.moves.first?.san ?? "x").sans.count == 3)
	}

	@Test("ECO families and Top openings come straight from the server")
	func tables() async {
		let model = OpeningsModel(context: fixtureContext())
		await model.load()
		#expect(model.resource.value?.ecoFamilies.map(\.ecoFamily) == ["E", "B", "A", "C"])
		#expect(model.resource.value?.topOpenings.first?.eco == "B12")
	}

	@Test("an empty color tree is that color's empty state")
	func emptyTree() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		var payload = try decode(API.OpeningsPayload.self, from: try Repo.fixture("getOpenings"))
		payload.repertoire.black = API.OpeningsRepertoireTree(
			color: .black, gameCount: 0, minGames: 3, moves: [], scorePct: 0)
		api.set(try JSONEncoder().encode(payload), for: "getOpenings")
		let model = OpeningsModel(context: fixtureContext(api))
		await model.load()
		model.color = .black
		#expect(model.tree?.gameCount == 0)
		#expect(model.tree.map(RepertoireDisplay.isEmpty) == true)
	}

	@Test("offline shows the cached tree")
	func offline() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		await OpeningsModel(context: fixtureContext(api, cache: cache)).load()
		api.fail(with: .offline)
		let model = OpeningsModel(context: fixtureContext(api, cache: cache))
		await model.load()
		#expect(model.resource.isOffline && model.tree?.gameCount == 4)
	}
}

@Suite("Events and Rated Event screens")
@MainActor
struct EventsModelTests {
	@Test("Series headlines read like the web")
	func seriesHeadline() async throws {
		let model = EventsModel(context: fixtureContext())
		await model.load()
		let series = try #require(model.resource.value?.series)
		#expect(series.map(\.series) == ["Test Open", "Summer Cup"])
		#expect(EventText.seriesStats(series[0]) == "3 games · 1W 1D 1L · 1.5 pts")
	}

	@Test("real career: Series, the ladder's Rated Events, and the unplayed card")
	func realCareer() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "real_career", for: "getEvents")
		let model = EventsModel(context: fixtureContext(api))
		await model.load()
		let value = try #require(model.resource.value)
		#expect(value.gamesCount == 63)
		#expect(value.series.first?.ratedEvents.count == 12)
		#expect(value.unplayedEvents.count == 2)
		#expect(value.seriesPerformance.count == 11)
	}

	@Test("text helpers: points, rating change, score line, placement, dates")
	func text() {
		#expect(EventText.points(1.5) == "1.5")
		#expect(EventText.points(3) == "3")
		#expect(EventText.ratingChange(pre: 1544, post: 1571, change: 27) == "1544 → 1571 (+27)")
		#expect(EventText.ratingChange(pre: nil, post: 695, change: nil) == "unrated → 695")
		#expect(EventText.ratingChange(pre: 1500, post: nil, change: nil) == "")
		#expect(EventText.scoreLine(score: 3.5, games: 4, forfeits: 1) == "Score 3.5 · 4 games + 1 forfeit win")
		#expect(EventText.scoreLine(score: 1, games: 1, forfeits: 2) == "Score 1 · 1 game + 2 forfeit wins")
		#expect(EventText.ordinal(1) == "1st")
		#expect(EventText.ordinal(22) == "22nd")
		#expect(EventText.ordinal(13) == "13th")
		#expect(EventText.placement(placement: 5, playerCount: 116) == "Finished 5th of 116")
		#expect(EventText.placement(placement: nil, playerCount: 40) == "40 players")
		#expect(EventText.placement(placement: nil, playerCount: nil) == nil)
		#expect(EventText.dates(start: "2026-05-01", end: "2026-05-29") == "2026-05-01 to 2026-05-29")
		#expect(EventText.dates(start: "2026-05-01", end: "2026-05-01") == "2026-05-01")
		#expect(EventText.dates(start: nil, end: nil) == "")
		#expect(EventText.round(nil) == "R?")
		#expect(EventText.round(3) == "R3")
	}

	@Test("crosstable round letters match the web")
	func roundLetters() {
		let cases = ["Win": "W", "WinForfeit": "W", "Loss": "L", "Draw": "D", "Forfeit": "F",
					 "ByeFull": "B", "ByeHalf": "b", "Unpaired": "·", "Mystery": "·"]
		for (outcome, letter) in cases {
			#expect(CrosstableRoundDisplay.letter(outcome) == letter)
		}
	}

	@Test("a Rated Event loads by event ID with its crosstable and the player's rounds linked")
	func ratedEvent() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "real_career", for: "getEvent")
		let model = EventModel(context: fixtureContext(api), eventID: "202605290393")
		await model.load()
		#expect(api.requests.last?.path.hasSuffix("events/202605290393") == true)
		let event = try #require(model.resource.value)
		#expect(event.name == "ACC MAY 2026")
		#expect(EventText.ratingChange(pre: event.preRating, post: event.postRating, change: event.ratingChange)
			== "1544 → 1571 (+27)")
		let section = try #require(event.sections.first)
		#expect(EventText.placement(placement: section.placement, playerCount: section.playerCount)
			== "Finished 5th of 116")
		let me = try #require(EventModel.playerRow(in: section))
		#expect(me.isPlayer && me.ordinal == 5)
		#expect(me.rounds.contains { $0.gameId != nil })
	}

	@Test("a Rated Event with no cached crosstable has no player row")
	func noCrosstable() async throws {
		let model = EventModel(context: fixtureContext(), eventID: "202401070001")
		await model.load()
		let section = try #require(model.resource.value?.sections.first)
		#expect(!section.hasCrosstable)
		#expect(EventModel.playerRow(in: section) == nil)
	}

	@Test("offline shows the cached Events")
	func offline() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		await EventsModel(context: fixtureContext(api, cache: cache)).load()
		api.fail(with: .offline)
		let model = EventsModel(context: fixtureContext(api, cache: cache))
		await model.load()
		#expect(model.resource.isOffline && model.resource.value?.series.count == 2)
	}

	@Test("Game and Rated Event routes are plain values")
	func routes() {
		#expect(GameRoute(gameID: "chap0001") == GameRoute(gameID: "chap0001"))
		#expect(EventRoute(eventID: "1") != EventRoute(eventID: "2"))
	}
}
