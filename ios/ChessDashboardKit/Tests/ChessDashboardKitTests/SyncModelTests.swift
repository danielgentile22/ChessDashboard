import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Sync")
@MainActor
struct SyncModelTests {
	private func signedIn(_ api: FixtureAPIClient = FixtureAPIClient(directory: Repo.fixtures)) async -> AppEnvironment {
		let env = makeEnvironment(api: api)
		await env.refreshMeta()
		return env
	}

	@Test("a Sync reports new Games and personal bests like the web toast")
	func success() async throws {
		let env = await signedIn()
		await env.runSync()
		let report = try #require(env.sync.report)
		#expect(report.style == .success)
		#expect(report.title == "Sync complete")
		#expect(report.message == "2 new Games")
		#expect(report.newGameLinks.map(\.label) == ["vs Opponent E (Win)", "vs Opponent A (Draw)"])
		#expect(report.newGameLinks.map(\.route) == [GameRoute(gameID: "chap0021"), GameRoute(gameID: "chap0022")])
		#expect(report.celebrations == [
			"New peak rating: 1815 (was 1810)",
			"New longest win streak: 4 games in a row (was 3)",
		])
		#expect(report.newGames.map(\.gameId) == ["chap0021", "chap0022"])
		#expect(report.syncedAt == ISODates.timestamp("2026-01-01T00:00:00Z"))
	}

	@Test("a successful Sync bumps the revision and re-fetches meta")
	func refreshesAfterSync() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let env = await signedIn(api)
		let before = api.requests.count
		await env.runSync()
		#expect(env.sync.revision == 1)
		#expect(api.requests.dropFirst(before).map(\.operationId) == ["runSync", "getMeta"])
		#expect(api.requests[before].method == .post)
	}

	@Test("loaded screens re-fetch their last request after a Sync")
	func screenReload() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let env = await signedIn(api)
		let model = OverviewModel(context: try #require(env.context))
		let unloaded = ScreenResource<API.OverviewPayload>()
		await unloaded.reload(in: try #require(env.context))
		#expect(unloaded.value == nil)
		await model.load()
		let before = api.requests.count
		await model.resource.reload(in: try #require(env.context))
		#expect(api.requests.dropFirst(before).map(\.operationId) == ["getOverview"])
		#expect(api.requests.last == api.requests[before - 1])
	}

	@Test("nothing new: the up-to-date message, no celebration")
	func upToDate() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "up_to_date", for: "runSync")
		let env = await signedIn(api)
		await env.runSync()
		let report = try #require(env.sync.report)
		#expect(report.message == "No new Games. Everything is already up to date.")
		#expect(report.celebrations.isEmpty)
		#expect(env.sync.revision == 1)
	}

	@Test("already running: a warning, and screens are not re-fetched")
	func alreadyRunning() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "already_running", for: "runSync")
		let env = await signedIn(api)
		await env.runSync()
		let report = try #require(env.sync.report)
		#expect(report.style == .warning)
		#expect(report.title == "Sync already running")
		#expect(env.sync.revision == 0)
		#expect(api.requests.last?.operationId == "runSync")
	}

	@Test("Studies that couldn't be fetched are listed")
	func partialFailure() async throws {
		var payload = try Wire.decoder.decode(API.SyncPayload.self, from: Repo.fixture("runSync"))
		payload.failures = [API.SyncFailure(reason: "404", studyId: "abc123")]
		payload.newAchievements = [API.SyncAchievement(
			achievementId: "n1", date: "2024-09-01", detail: "", kind: .norm, ratedEventId: "e1",
			ratedEventName: "Fall Open", title: "Fourth Category norm")]
		let report = SyncReport(payload)
		#expect(report.message.hasSuffix("(couldn't fetch: abc123)"))
		#expect(report.celebrations.last == "Official USCF achievement: Fourth Category norm (Fall Open)")
	}

	@Test("a failed Sync shows the server's reason and keeps the current data")
	func failure() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let env = await signedIn(api)
		api.fail("runSync", with: .server(status: 502, code: "sync_failed", message: "Lichess is unreachable"))
		await env.runSync()
		let report = try #require(env.sync.report)
		#expect(report.style == .failure)
		#expect(report.title == "Sync failed")
		#expect(report.message == "Lichess is unreachable (still showing your current Games).")
		#expect(env.sync.revision == 0)

		api.fail("runSync", with: .offline)
		await env.runSync()
		#expect(env.sync.report?.message == APIError.offline.message)

		// A timeout may still finish on the server: a warning, worded differently.
		api.fail("runSync", with: .timedOut)
		await env.runSync()
		#expect(env.sync.report?.style == .warning)
		#expect(env.sync.report?.title == "Sync is taking a while")
		env.sync.dismiss()
		#expect(env.sync.phase == .idle)
	}

	@Test("an expired session ends the Sync quietly (sign-in takes over)")
	func expired() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let env = await signedIn(api)
		api.fail("runSync", with: .unauthenticated)
		await env.runSync()
		#expect(env.sync.phase == .idle)
		#expect(env.session.session == nil)
	}

	@Test("guests never reach the Sync route and see why")
	func guest() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let guest = Session(token: "t", role: .guest, username: nil, canWrite: false, expiresAt: .now.addingTimeInterval(3_600))
		let env = makeEnvironment(session: guest, api: api)
		await env.refreshMeta()
		#expect(env.canSync == false)
		#expect(env.syncUnavailableReason == "Guests can't Sync. Sign in as the owner to refresh the data.")
		await env.runSync()
		#expect(env.sync.phase == .idle)
		#expect(!api.requests.contains { $0.operationId == "runSync" })
	}

	@Test("demo mode disables Sync for the owner too")
	func demo() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		var meta = try JSONSerialization.jsonObject(with: Repo.fixture("getMeta")) as! [String: Any]
		meta["demo_mode"] = true
		api.set(try JSONSerialization.data(withJSONObject: meta), for: "getMeta")
		let env = await signedIn(api)
		#expect(env.canSync == false)
		#expect(env.syncUnavailableReason == "Demo mode is read-only; Sync is disabled.")
		#expect(await signedIn().syncUnavailableReason == nil)
	}

	@Test("pull-to-refresh re-fetches and never Syncs")
	func refreshNeverSyncs() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let env = await signedIn(api)
		let model = OverviewModel(context: try #require(env.context))
		await model.load()
		await model.load()
		await env.refreshMeta()
		#expect(!api.requests.contains { $0.operationId == "runSync" })
	}
}
