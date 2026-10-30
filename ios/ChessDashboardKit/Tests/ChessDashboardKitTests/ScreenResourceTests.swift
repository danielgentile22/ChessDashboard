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

	@Test("the lichess-only meta variant renders through the fixture client")
	func variants() async {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		api.use(variant: "lichess_only", for: "getMeta")
		let r = ScreenResource<API.MetaPayload>()
		await r.load(Endpoints.getMeta(), in: context(api, cache: .temporary()))
		#expect(r.value?.freshness.uscf.enabled == false)
	}
}
