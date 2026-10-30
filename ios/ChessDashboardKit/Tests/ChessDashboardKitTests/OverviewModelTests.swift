import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Overview screen")
@MainActor
struct OverviewModelTests {
	private func loaded(variant: String? = nil, api: FixtureAPIClient = FixtureAPIClient(directory: Repo.fixtures))
		async -> OverviewModel
	{
		api.use(variant: variant, for: "getOverview")
		let model = OverviewModel(context: makeEnvironment(api: api).context!)
		await model.load()
		return model
	}

	@Test("the KPI bar: whole-number ratings, percentages, the favorite opening")
	func kpis() async throws {
		let model = await loaded()
		#expect(!model.isEmpty)
		let kpis = Dictionary(uniqueKeysWithValues: model.kpis.map { ($0.title, $0) })
		#expect(kpis["Games"]?.value == "7")
		#expect(kpis["Win %"]?.value == "57.1%" && kpis["Win %"]?.tone == .win)
		#expect(kpis["Draw %"]?.value == "28.6%" && kpis["Draw %"]?.tone == .neutral)
		#expect(kpis["Loss %"]?.value == "14.3%" && kpis["Loss %"]?.tone == .loss)
		#expect(kpis["Current Rating"]?.value == "1810")
		#expect(kpis["Peak Rating"]?.value == "1810")
		#expect(kpis["Performance Rating"]?.value == "2007")
		#expect(kpis["Longest Win Streak"]?.value == "3")
		#expect(kpis["Unique Opponents"]?.value == "4")
		#expect(kpis["Favorite Opening"]?.value == "Caro-Kann Defense")
		#expect(kpis["Current Rating"]?.accessibilityLabel == "Current Rating: 1810")
	}

	@Test("the request carries the filters and the lens")
	func filtered() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let env = makeEnvironment(api: api)
		env.filters.state.lens = .live
		let model = OverviewModel(context: env.context!)
		await model.load()
		let request = try #require(api.requests.last)
		#expect(request.operationId == "getOverview")
		#expect(request.query.contains(URLQueryItem(name: "lens", value: "live")))
	}

	@Test("last-20 form, Streak stats, and no fire on a Draw")
	func form() async {
		let form = await loaded().form
		#expect(form.badges.map(\.letter) == ["W", "D", "L", "W", "W", "W", "D"])
		#expect(form.badges.last?.outcome == .draw)
		#expect(form.stats.map(\.label) == ["Unbeaten streak", "Win streak", "Current (Draw)"])
		#expect(form.stats.map(\.value) == ["4", "3", "1"])
		#expect(form.indicator == nil)
	}

	@Test("a win Streak shows the fire, blazing at five")
	func fire() {
		let fire = OverviewModel.indicator(API.OverviewFormIndicator(blazing: true, count: 6, kind: .fire))
		#expect(fire?.symbol == "🔥" && fire?.blazing == true && fire?.count == 6)
		#expect(fire?.accessibilityLabel == "6-game win Streak")
		let cold = OverviewModel.indicator(API.OverviewFormIndicator(blazing: false, count: 3, kind: .cold))
		#expect(cold?.symbol == "🧊" && cold?.accessibilityLabel == "3-game losing Streak")
		#expect(OverviewModel.indicator(API.OverviewFormIndicator(blazing: false, count: 0, kind: .none)) == nil)
	}

	@Test("the Win / Draw / Loss breakdown hides zero wedges")
	func outcomes() async {
		let slices = await loaded().outcomeSlices
		#expect(slices.map(\.label) == ["Wins", "Draws", "Losses"])
		#expect(slices.map(\.games) == [4, 2, 1])
		#expect(slices.map(\.percentText) == ["57%", "29%", "14%"])
	}

	@Test("milestones: Game milestones number the Game, USCF achievements are badged")
	func milestones() async {
		let rows = await loaded().milestones
		#expect(rows.count == 9)
		#expect(rows[0].badge == "#1" && rows[0].gameId == "chap0001" && !rows[0].isUSCF)
		#expect(rows[0].dateText == "2024-01-06")
		let uscf = rows[7]
		#expect(uscf.badge == "USCF" && uscf.isUSCF && uscf.gameId == nil)
		#expect(uscf.description.hasPrefix("Fourth Category norm"))
	}

	@Test("the USCF card: Official and Live side by side, rating notes, ranks, membership")
	func uscfCard() async throws {
		guard case .profile(let card) = await loaded().uscfCard else {
			Issue.record("expected a profile card")
			return
		}
		#expect(card.name == "Daniel Gentile" && card.memberId == "#12345678")
		#expect(card.membership == "Active, until 2028-07-31")
		#expect(card.official == "1545" && card.live == "1571")
		#expect(card.regularNote == "Established, floor 1300")
		#expect(card.others.map(\.label) == ["Quick", "Online Regular"])
		#expect(card.others.map(\.value) == ["1092", "1336"])
		#expect(card.others.map(\.note) == ["Provisional, 17 Games", "Provisional, 11 Games"])
		#expect(card.ranks.map(\.label) == ["National rank", "VA rank"])
		#expect(card.ranks.map(\.value) == ["#11,719", "#356"])
		#expect(card.staleNotice == nil && card.alert == nil)
	}

	@Test("no USCF member ID: no card at all; USCF unreachable: the unavailable notice")
	func uscfDegrades() async throws {
		#expect(await loaded(variant: "lichess_only").uscfCard == .hidden)
		let card = API.OverviewUscfCard(
			profile: nil, state: .unavailable, unavailableReason: "timed out", unavailableSince: nil)
		#expect(OverviewModel.uscfCard(card) == .unavailable(reason: "timed out"))
	}

	@Test("the empty state: no Games in the filter, the USCF card still shows")
	func empty() async {
		let model = await loaded(variant: "empty")
		#expect(model.isEmpty)
		#expect(model.outcomeSlices.isEmpty && model.milestones.isEmpty && model.form.badges.isEmpty)
		let kpis = Dictionary(uniqueKeysWithValues: model.kpis.map { ($0.title, $0.value) })
		#expect(kpis["Current Rating"] == "Unrated" && kpis["Performance Rating"] == "None")
		#expect(kpis["Favorite Opening"] == "None")
		if case .profile = model.uscfCard {} else { Issue.record("the USCF card follows Syncs, not filters") }
	}

	@Test("offline: the cached Overview stays readable")
	func offline() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let env = makeEnvironment(api: api)
		await OverviewModel(context: env.context!).load()
		api.fail(with: .offline)
		let relaunched = OverviewModel(context: env.context!)
		await relaunched.load()
		#expect(relaunched.resource.isOffline)
		#expect(relaunched.kpis.first?.value == "7")
	}

	@Test("the top recurring weakness, when the server sends one")
	func weakness() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		var json = try #require(JSONSerialization.jsonObject(with: Repo.fixture("getOverview")) as? [String: Any])
		json["top_weakness"] = [
			"game_ids": ["chap0003"], "loss_count": 1, "severity": 0.5,
			"stat": "#time-trouble appears in 1 of your last 1 losses",
			"tag": ["name": "time-trouble", "source": "mine"], "window": "Jan 2024", "window_losses": 1,
		]
		api.set(try JSONSerialization.data(withJSONObject: json), for: "getOverview")
		let model = await loaded(api: api)
		#expect(model.payload?.topWeakness?.tag.name == "time-trouble")
	}
}
