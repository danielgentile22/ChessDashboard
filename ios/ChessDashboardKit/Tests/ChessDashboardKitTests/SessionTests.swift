import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Session")
@MainActor
struct SessionTests {
	@Test("owner sign-in stores the token and signs in")
	func ownerSignIn() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let credentials = InMemoryCredentialStore()
		let store = SessionStore(credentials: credentials, api: api)
		try await store.signIn(password: "hunter2")
		#expect(store.session?.token == "fixture-token")
		#expect(store.session?.canWrite == true)
		#expect(credentials.load()?.token == "fixture-token")
		let sent = try #require(api.requests.first)
		#expect(sent.authenticated == false)
		let body = try JSONSerialization.jsonObject(with: try #require(sent.body)) as? [String: String]
		#expect(body == ["password": "hunter2"])
	}

	@Test("multi-user sign-in sends the username")
	func multiUser() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let store = SessionStore(credentials: InMemoryCredentialStore(), api: api)
		try await store.signIn(password: "pw", username: " coach ")
		let body = try JSONSerialization.jsonObject(with: try #require(api.requests.first?.body)) as? [String: String]
		#expect(body == ["password": "pw", "username": "coach"])
	}

	@Test("guest sign-in asks for guest; a 403 surfaces the server's reason")
	func guest() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let store = SessionStore(credentials: InMemoryCredentialStore(), api: api)
		api.fail("createSession", with: .forbidden("Guest access is off on this server."))
		await #expect(throws: APIError.forbidden("Guest access is off on this server.")) {
			try await store.continueAsGuest()
		}
		#expect(store.state == .signedOut(notice: nil))
		api.fail("createSession", with: nil)
		try await store.continueAsGuest()
		let body = try JSONSerialization.jsonObject(with: try #require(api.requests.last?.body)) as? [String: Bool]
		#expect(body == ["guest": true])
	}

	@Test("a stored session that has expired starts signed out with a notice")
	func expiredAtLaunch() {
		let credentials = InMemoryCredentialStore(.owner(expiresAt: .now.addingTimeInterval(-1)))
		let store = SessionStore(credentials: credentials, api: FixtureAPIClient(fixtures: [:]))
		#expect(store.state == .signedOut(notice: SessionStore.expiredNotice))
		#expect(credentials.load() == nil)
	}

	@Test("expiry while running routes to sign-in on foreground")
	func expiredWhileRunning() {
		let credentials = InMemoryCredentialStore(.owner(expiresAt: Date(timeIntervalSince1970: 1_000)))
		nonisolated(unsafe) var now = Date(timeIntervalSince1970: 500)
		let store = SessionStore(credentials: credentials, api: FixtureAPIClient(fixtures: [:]), now: { now })
		#expect(store.session != nil)
		now = Date(timeIntervalSince1970: 2_000)
		store.checkExpiry()
		#expect(store.state == .signedOut(notice: SessionStore.expiredNotice))
	}

	@Test("a 401 signs out and forgets meta, but keeps the cache and filters for the next sign-in")
	func unauthorizedRoutesToSignIn() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let cache = ResponseCache.temporary()
		let env = makeEnvironment(api: api, cache: cache)
		await env.refreshMeta()
		env.filters.state.toggle(API.Color.black)
		#expect(env.meta.value != nil)
		api.fail(with: .unauthenticated)
		await env.refreshMeta()
		#expect(env.session.state == .signedOut(notice: SessionStore.expiredNotice))
		#expect(env.context == nil)
		#expect(env.meta.value == nil)
		#expect(env.filters.state.colors == [.white])
		#expect(FileManager.default.fileExists(atPath: cache.directory.path()))
	}

	@Test("expiry on foreground keeps the cache and filters too")
	func expiryKeepsCache() async throws {
		let cache = ResponseCache.temporary()
		nonisolated(unsafe) var now = Date(timeIntervalSince1970: 500)
		let env = AppEnvironment(
			config: AppConfig(baseURL: URL(string: "https://chess.example/api/v1/")!),
			api: FixtureAPIClient(directory: Repo.fixtures),
			credentials: InMemoryCredentialStore(.owner(expiresAt: Date(timeIntervalSince1970: 1_000))),
			defaults: InMemoryKeyValueStore(), cache: cache, now: { now })
		await env.refreshMeta()
		env.filters.state.lens = .live
		now = Date(timeIntervalSince1970: 2_000)
		env.session.checkExpiry()
		#expect(env.session.state == .signedOut(notice: SessionStore.expiredNotice))
		#expect(env.filters.state.lens == .live)
		#expect(cache.read(Endpoints.getMeta(), scope: "https://chess.example/api/v1/ owner") != nil)
	}

	@Test("manual sign-out has no notice and wipes meta, the cache, and the filters")
	func signOut() async {
		let cache = ResponseCache.temporary()
		let env = makeEnvironment(cache: cache)
		await env.refreshMeta()
		env.filters.state.toggle(API.Color.black)
		env.session.signOut()
		#expect(env.session.state == .signedOut(notice: nil))
		#expect(env.meta.value == nil)
		#expect(env.filters.state == .all)
		#expect(!FileManager.default.fileExists(atPath: cache.directory.path()))
	}

	@Test("a late 401 for an earlier session never signs out the one that replaced it")
	func late401() async throws {
		let fixtures = FixtureAPIClient(directory: Repo.fixtures)
		let box = EnvironmentBox()
		let api = ClosureAPI { request throws(APIError) in
			guard request.operationId == "getMeta" else { return try await fixtures.data(for: request) }
			// While this request is in flight, the user signs out and back in.
			await box.env.session.signOut()
			try await box.env.session.signIn(password: "pw")
			throw .unauthenticated
		}
		let old = Session(token: "old-token", role: .owner, username: nil, canWrite: true, expiresAt: .distantFuture)
		box.env = makeEnvironment(session: old, api: api)
		await box.env.refreshMeta()
		#expect(box.env.session.session?.token == "fixture-token")
	}

	@Test("an answer that lands after sign-out is neither shown nor cached")
	func lateAnswerAfterSignOut() async throws {
		let fixtures = FixtureAPIClient(directory: Repo.fixtures)
		let box = EnvironmentBox()
		let api = ClosureAPI { request throws(APIError) in
			let data = try await fixtures.data(for: request)
			if request.operationId != "createSession" { await box.env.session.signOut() }
			return data
		}
		let cache = ResponseCache.temporary()
		let wiped = { !FileManager.default.fileExists(atPath: cache.directory.path()) }
		box.env = makeEnvironment(api: api, cache: cache)

		await box.env.refreshMeta()
		#expect(box.env.meta.value == nil && wiped())

		try await box.env.session.signIn(password: "pw")
		let screen = ScreenResource<API.MetaPayload>()
		await screen.load(Endpoints.getMeta(), in: try #require(box.env.context))
		#expect(screen.value == nil && wiped())

		try await box.env.session.signIn(password: "pw")
		await try #require(box.env.context).prefetch(Endpoints.getOverview(filters: .all))
		#expect(wiped())
	}

	@Test("the sign-in screen learns a multi-user server from its answers")
	func multiUserMode() async throws {
		let api = FixtureAPIClient(directory: Repo.fixtures)
		let defaults = InMemoryKeyValueStore()
		let store = SessionStore(credentials: InMemoryCredentialStore(), api: api, defaults: defaults)
		#expect(!store.isMultiUserServer)
		api.fail("createSession", with: .forbidden("Guest access is off on this server."))
		_ = try? await store.continueAsGuest()
		#expect(store.isMultiUserServer)
		#expect(SessionStore(credentials: InMemoryCredentialStore(), api: api, defaults: defaults).isMultiUserServer)

		api.fail("createSession", with: nil)
		try await store.signIn(password: "owner")  // the fixture grant has no username: owner mode
		#expect(!store.isMultiUserServer)

		var grant = try JSONSerialization.jsonObject(with: Repo.fixture("createSession")) as! [String: Any]
		grant["username"] = "coach"
		api.set(try JSONSerialization.data(withJSONObject: grant), for: "createSession")
		try await store.signIn(password: "pw", username: "coach")
		#expect(store.isMultiUserServer)
	}

	@Test("guests and demo servers can't Sync")
	func canSync() async {
		let guest = Session(token: "t", role: .guest, username: nil, canWrite: false, expiresAt: .distantFuture)
		#expect(!makeEnvironment(session: guest).canSync)
		let owner = makeEnvironment()
		await owner.refreshMeta()
		#expect(owner.canSync)
	}
}
