import Foundation
import Observation

/// Where the app runs. The app target reads `baseURL` from Info.plist
/// (`CDBaseURL`, set per configuration in project.yml), so Debug talks to a
/// local server and Release to the deployed one with no code change.
public struct AppConfig: Sendable {
	/// Ends in `/api/v1/`.
	public var baseURL: URL

	public init(baseURL: URL) {
		self.baseURL = baseURL
	}

	public func webURL(_ page: WebPage) -> URL { page.url(apiBaseURL: baseURL) }
}

/// The composition root: one per app run. It wires the client, the session,
/// the filters, the cache and the shared meta response together, and hands
/// each screen a `ScreenContext`. Tests build one over a `FixtureAPIClient`.
@MainActor @Observable
public final class AppEnvironment {
	public let config: AppConfig
	public let session: SessionStore
	public let filters: FilterStore
	/// `GET /api/v1/meta`: filter options and presets for the filter sheet,
	/// per-source freshness, the role. Loaded on sign-in and every refresh.
	public let meta = ScreenResource<API.MetaPayload>()
	/// The owner's Sync action and its last outcome (the toast).
	public let sync = SyncModel()

	@ObservationIgnored public let api: any DashboardAPI
	@ObservationIgnored public let cache: ResponseCache

	/// The live app.
	public convenience init(
		config: AppConfig, defaults: any KeyValueStore, cachesDirectory: URL,
		credentials: any CredentialStore = KeychainCredentialStore()
	) {
		self.init(
			config: config,
			api: LiveAPIClient(baseURL: config.baseURL, credentials: credentials),
			credentials: credentials, defaults: defaults,
			cache: ResponseCache(directory: cachesDirectory.appending(path: "responses-v1")))
	}

	public init(
		config: AppConfig, api: any DashboardAPI, credentials: any CredentialStore,
		defaults: any KeyValueStore, cache: ResponseCache, now: @escaping @Sendable () -> Date = { .now }
	) {
		// The guard needs the session store and the store needs the guarded
		// client (to sign in), so the guard reaches the store through a box.
		let box = SessionBox()
		let guarded = SessionGuard(api, credentials: credentials) { token in
			await box.store?.sessionEnded(token: token)
		}
		self.config = config
		self.api = guarded
		self.cache = cache
		self.filters = FilterStore(defaults: defaults)
		self.session = SessionStore(credentials: credentials, api: guarded, defaults: defaults, now: now)
		// Every sign-out forgets the shown meta and Sync toast, so the next person never sees
		// it. Only an explicit sign-out wipes the cache and filters: after an
		// expiry the same person usually signs back in, and their offline
		// Scouting Report and review should still be there (the cache is keyed
		// by user, so nobody else can read it).
		session.onSignOut = { [cache, filters, meta, sync] reason in
			meta.reset()
			sync.reset()
			guard reason == .signedOut else { return }
			cache.wipe()
			filters.clear()
		}
		box.store = session
	}

	/// The context every screen model takes, or nil while signed out.
	public var context: ScreenContext? {
		guard let s = session.session else { return nil }
		return ScreenContext(
			api: api, filters: filters, cache: cache,
			cacheScope: "\(config.baseURL.absoluteString) \(s.cacheScope)",
			isCurrent: { [session] in session.session?.token == s.token })
	}

	/// Whether Sync may be offered: an owner (not a guest) on a server that
	/// isn't a read-only demo.
	public var canSync: Bool {
		guard let s = session.session, s.canWrite else { return false }
		return meta.value?.demoMode != true
	}

	/// Why Sync isn't offered, for the disabled action; nil when it is.
	public var syncUnavailableReason: String? {
		if canSync { return nil }
		if meta.value?.demoMode == true { return "Demo mode is read-only; Sync is disabled." }
		return "Guests can't Sync. Sign in as the owner to refresh the data."
	}

	public func runSync() async {
		await sync.run(in: self)
	}

	public func refreshMeta() async {
		guard let context else { return }
		await meta.load(Endpoints.getMeta(), in: context)
	}
}

@MainActor
private final class SessionBox {
	weak var store: SessionStore?
}
