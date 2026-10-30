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

	@Test("a 401 from any screen request signs out, wipes the cache and filters")
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
		#expect(env.filters.state == .all)
		#expect(!FileManager.default.fileExists(atPath: cache.directory.path()))
	}

	@Test("manual sign-out has no notice")
	func signOut() {
		let env = makeEnvironment()
		env.session.signOut()
		#expect(env.session.state == .signedOut(notice: nil))
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
