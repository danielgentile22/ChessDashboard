import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Screen loading and the response cache")
@MainActor
struct ScreenResourceTests {
	private func context(_ api: FixtureAPIClient, cache: ResponseCache, scope: String = "owner")
		-> ScreenContext
	{
		ScreenContext(
			api: api, filters: FilterStore(defaults: InMemoryKeyValueStore()), cache: cache, cacheScope: scope)
	}

	@Test("a fresh load shows the response and caches it")
	func freshLoad() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		let r = ScreenResource<API.MetaPayload>()
		await r.load(Endpoints.getMeta(), in: context(api, cache: cache))
		#expect(r.value?.player == "Test Player")
		#expect(r.cachedAt == nil && !r.isOffline && r.error == nil && !r.isLoading)
		#expect(cache.read(Endpoints.getMeta(), scope: "owner")?.value.gamesTotal == 7)
	}

	@Test("offline: the cached copy renders with the offline flag")
	func offlineShowsCache() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		await ScreenResource<API.MetaPayload>().load(Endpoints.getMeta(), in: context(api, cache: cache))

		api.fail(with: .offline)
		let relaunched = ScreenResource<API.MetaPayload>()
		await relaunched.load(Endpoints.getMeta(), in: context(api, cache: cache))
		#expect(relaunched.value?.player == "Test Player")
		#expect(relaunched.isOffline)
		#expect(relaunched.cachedAt != nil)
	}

	@Test("offline with no cache shows nothing, flagged offline")
	func offlineNoCache() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.fail(with: .offline)
		let r = ScreenResource<API.MetaPayload>()
		await r.load(Endpoints.getMeta(), in: context(api, cache: .temporary()))
		#expect(r.value == nil && r.isOffline)
	}

	@Test("caches are per user: one scope never reads another's")
	func scoped() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		await ScreenResource<API.MetaPayload>().load(Endpoints.getMeta(), in: context(api, cache: cache, scope: "user-a"))
		#expect(cache.read(Endpoints.getMeta(), scope: "user-a") != nil)
		#expect(cache.read(Endpoints.getMeta(), scope: "user-b") == nil)
	}

	@Test("filesystem failures degrade to no cache")
	func brokenCacheDirectory() async throws {
		let file = FileManager.default.temporaryDirectory.appending(path: "cd-not-a-dir-\(UUID())")
		try Data("x".utf8).write(to: file)
		let cache = ResponseCache(directory: file)  // a file where the directory should be
		let r = ScreenResource<API.MetaPayload>()
		await r.load(Endpoints.getMeta(), in: context(FixtureAPIClient(directory: Repo.fixtures), cache: cache))
		#expect(r.value != nil)
		#expect(cache.read(Endpoints.getMeta(), scope: "owner") == nil)
	}

	@Test("a cached body the app can no longer decode is ignored")
	func undecodableCache() async {
		let cache = ResponseCache.temporary()
		cache.write(Data("{}".utf8), for: Endpoints.getMeta().request, scope: "owner")
		#expect(cache.read(Endpoints.getMeta(), scope: "owner") == nil)
	}

	@Test("a server error keeps what is shown and reports it")
	func serverError() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let ctx = context(api, cache: .temporary())
		let r = ScreenResource<API.MetaPayload>()
		await r.load(Endpoints.getMeta(), in: ctx)
		api.fail(with: .server(status: 500, code: nil, message: ""))
		await r.load(Endpoints.getMeta(), in: ctx)
		#expect(r.value != nil)
		#expect(r.error == .server(status: 500, code: nil, message: ""))
		#expect(!r.isOffline)
	}

	@Test("new filters never show the previous filters' numbers")
	func switchingRequests() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let ctx = context(api, cache: .temporary())
		let r = ScreenResource<API.MetaPayload>()
		await r.load(Endpoints.getMeta(), in: ctx)
		#expect(r.value != nil)
		api.fail(with: .offline)
		// A different request with nothing cached: nothing shown.
		var other = Endpoints.getMeta()
		other.request.query = [URLQueryItem(name: "x", value: "1")]
		await r.load(other, in: ctx)
		#expect(r.value == nil)
	}

	@Test("two fetches of one request: only the newer writes, and loading lasts until it lands")
	func overlappingFetches() async throws {
		let api = GatedAPI()
		let ctx = ScreenContext(
			api: api, filters: FilterStore(defaults: InMemoryKeyValueStore()), cache: .temporary(),
			cacheScope: "owner")
		let r = ScreenResource<API.MetaPayload>()

		// The older fetch lands first: dropped, still loading.
		let first = Task { await r.load(Endpoints.getMeta(), in: ctx) }
		await api.waitForRequests(1)
		let second = Task { await r.reload(in: ctx) }
		await api.waitForRequests(2)
		api.release(0, with: try metaFixture(player: "Older"))
		await first.value
		#expect(r.value == nil && r.isLoading)
		api.release(1, with: try metaFixture(player: "Newer"))
		await second.value
		#expect(r.value?.player == "Newer" && !r.isLoading)

		// The older fetch lands last: it never overwrites the newer answer.
		let third = Task { await r.reload(in: ctx) }
		await api.waitForRequests(3)
		let fourth = Task { await r.reload(in: ctx) }
		await api.waitForRequests(4)
		api.release(3, with: try metaFixture(player: "Newest"))
		await fourth.value
		api.release(2, with: try metaFixture(player: "Stale"))
		await third.value
		#expect(r.value?.player == "Newest" && !r.isLoading)
	}

	@Test("the lichess-only meta variant renders through the fixture client")
	func variants() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "lichess_only", for: "getMeta")
		let r = ScreenResource<API.MetaPayload>()
		await r.load(Endpoints.getMeta(), in: context(api, cache: .temporary()))
		#expect(r.value?.freshness.uscf.enabled == false)
	}
}
