import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Game detail")
@MainActor
struct GameDetailModelTests {
	private func model(_ variant: String?, api: FixtureAPIClient = FixtureAPIClient(directory: Repo.fixtures))
		async -> GameDetailModel
	{
		api.use(variant: variant, for: "getGame")
		let model = GameDetailModel(gameID: "alic0001", context: makeEnvironment(api: api).context!)
		await model.load()
		return model
	}

	@Test("an analyzed Game with a coach review has all four views, oriented for Black")
	func analyzed() async {
		let m = await model("analyzed")
		#expect(m.views.map(\.kind) == [.game, .myAnalysis, .engine, .coach])
		#expect(m.orientation == .black)
		#expect(m.diagram?.bottom == .black && m.diagram?.cells.first?.square.name == "h1")
		#expect(m.cursor == PGNTree.root && !m.canGoBack && m.canGoForward)
		#expect(m.subtitle.hasPrefix("2nd Annual Adults Only (U1800) · Round 3 · "))
		#expect(m.subtitle.contains("2026"))
	}

	@Test("views exist only when present: no Engine or Coach on an unanalyzed Game")
	func onlyPresentViews() async {
		#expect(await model("unanalyzed").views.map(\.kind) == [.game, .myAnalysis])
		#expect(await model(nil).views.map(\.kind) == [.game])
		let coach = await model("coach")
		#expect(coach.views.map(\.kind) == [.game, .myAnalysis, .coach])
		coach.select(.engine)  // not offered: falls back to the first view
		#expect(coach.selectedView?.kind == .game)
	}

	@Test("stepping forward and back; to the end and the start")
	func stepping() async throws {
		let m = await model("analyzed")
		m.forward()
		m.forward()
		let tree = try #require(m.tree)
		#expect(tree.label(m.cursor) == "1… c6")
		m.back()
		#expect(tree.label(m.cursor) == "1. e4")
		m.toEnd()
		#expect(tree[m.cursor].ply == 48 && !m.canGoForward)
		m.toStart()
		#expect(m.cursor == PGNTree.root)
	}

	@Test("jump to a ply from the eval chart, judged moves, or the critical moment")
	func jump() async throws {
		let m = await model("analyzed")
		let moment = try #require(m.resource.value?.engine.criticalMoment)
		m.jump(toPly: moment.ply)
		#expect(m.tree?.label(m.cursor) == "16. Bd4")
		#expect(m.mainlinePly == 31)
		m.jump(toPly: 999)
		#expect(m.mainlinePly == 48)
	}

	@Test("into a variation and back out, in My Analysis")
	func variations() async throws {
		let m = await model("my_analysis")
		m.select(.myAnalysis)
		m.jump(toPly: 6)  // 3... a6, then 4. Nf3 or 4. cxd4
		#expect(m.nextChoices.map { m.tree!.moveText($0) } == ["Nf3?!", "cxd4!"])
		m.go(to: m.nextChoices[1])
		#expect(m.isInVariation)
		#expect(m.tree?.displayComments(m.cursor) == [
			"Don't try to force the game back to theory. Stick to the general principles."
		])
		m.exitVariation()
		#expect(!m.isInVariation && m.mainlinePly == 6)
	}

	@Test("each view keeps its own place on the board")
	func perViewCursor() async {
		let m = await model("analyzed")
		m.jump(toPly: 10)
		m.select(.coach)
		#expect(m.cursor == PGNTree.root)
		m.select(.game)
		#expect(m.mainlinePly == 10)
	}

	@Test("the Engine view's comments drop their eval commands")
	func engineComments() async throws {
		let m = await model("analyzed")
		m.select(.engine)
		m.jump(toPly: 5)
		let tree = try #require(m.tree)
		#expect(tree.displayComments(m.cursor) == ["Inaccuracy. d4 was best."])
		#expect(tree.evaluation(m.cursor) == "-0.17")
	}

	@Test("metadata, the USCF Game Record, Lessons, and Tags (mine vs engine)")
	func cards() async {
		let m = await model(nil)
		let p = m.resource.value!
		#expect(p.lessons == ["Keep the tension in the center instead of releasing it early. #strategy"])
		#expect(p.tags.map(TagDisplay.init).map(\.style) == [.mine])
		#expect(m.metadataRows.map(\.label) == [
			"Date", "Series", "Round", "You played", "Result", "Termination", "Your rating",
			"Opponent rating", "Opening", "Moves", "Study",
		])
		#expect(m.metadataRows.first { $0.label == "Opening" }?.value == "E04 Catalan Opening: Open Defense")
		#expect(m.metadataRows.first { $0.label == "Your rating" }?.value == "1800")
		#expect(m.uscfRows.map(\.label) == ["Rated Event", "Section", "Rating system", "Matched by"])
		#expect(m.chapterURL?.absoluteString == "https://lichess.org/study/teststudy/chap0001")

		let analyzed = await model("analyzed")
		#expect(analyzed.resource.value!.tags.map(TagDisplay.init).map(\.style) == [.engine])
	}

	@Test("an unmatched Game has no USCF rows; empty metadata rows are hidden")
	func emptyRows() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		var payload = try decode(API.GamePayload.self, from: Repo.fixture("getGame"))
		payload.uscfRecord = nil
		payload.metadata.round = nil
		payload.metadata.termination = ""
		payload.metadata.color = .unknown
		payload.playerColor = .unknown
		payload.board = API.GameBoardPgns(coach: nil, engine: nil, game: nil, myAnalysis: nil)
		api.set(try JSONEncoder().encode(payload), for: "getGame")
		let m = GameDetailModel(gameID: "chap0001", context: makeEnvironment(api: api).context!)
		await m.load()
		#expect(m.uscfRows.isEmpty)
		#expect(!m.metadataRows.contains { ["Round", "Termination", "You played"].contains($0.label) })
		#expect(m.orientation == .white)
		#expect(m.views.isEmpty && m.diagram == nil)
	}

	@Test("a PGN the board can't replay is reported, not a crash")
	func unplayable() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		var payload = try decode(API.GamePayload.self, from: Repo.fixture("getGame"))
		payload.board.coach = "1. e4 e5 2. Ke3 *"
		api.set(try JSONEncoder().encode(payload), for: "getGame")
		let m = GameDetailModel(gameID: "chap0001", context: makeEnvironment(api: api).context!)
		await m.load()
		m.select(.coach)
		#expect(m.selectedView?.kind == .coach && m.tree == nil && m.diagram == nil)
		if case .failure(.illegalMove(let san, _)) = m.selectedView?.tree {
			#expect(san == "Ke3")
		} else {
			Issue.record("expected an illegal move")
		}
	}

	@Test("display text: judged moves, the critical moment, corrections")
	func displayText() async throws {
		let m = await model("analyzed")
		let engine = m.resource.value!.engine
		let judged = try #require(engine.judgedMoves.first)
		#expect(GameDetailModel.moveLabel(ply: judged.ply, moveNumber: judged.moveNumber, san: judged.san) == "15… g5")
		#expect(GameDetailModel.correction(judged) == "Best was h5, then c5 Bxg3 hxg3 Qd7 Rfd1 Ng6 Rc4")
		#expect(GameDetailModel.criticalMomentDetail(engine.criticalMoment!)
			== "eval +0.54 → -4.38 · engine preferred Nh5")
	}

	@Test("offline: the cached Game renders with the offline flag")
	func offline() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "analyzed", for: "getGame")
		let env = makeEnvironment(api: api)
		await GameDetailModel(gameID: "alic0001", context: env.context!).load()
		api.fail(with: .offline)
		let relaunched = GameDetailModel(gameID: "alic0001", context: env.context!)
		await relaunched.load()
		#expect(relaunched.resource.isOffline)
		#expect(relaunched.views.count == 4)
	}
}
