import Foundation
import Observation

/// What every screen view model is given: the API client protocol, the
/// app-wide filter state, and where its responses are cached. Built by
/// `AppEnvironment.context` once someone is signed in; tests build one over a
/// `FixtureAPIClient`.
@MainActor
public struct ScreenContext {
	public let api: any DashboardAPI
	public let filters: FilterStore
	public let cache: ResponseCache
	/// Whose cache this is (server plus user); see `Session.cacheScope`.
	public let cacheScope: String
	/// False once the session this context was built for has ended: an
	/// answer that arrives after that is dropped, never shown or cached (the
	/// cache may have been wiped meanwhile).
	public let isCurrent: @MainActor () -> Bool

	public init(
		api: any DashboardAPI, filters: FilterStore, cache: ResponseCache, cacheScope: String,
		isCurrent: @escaping @MainActor () -> Bool = { true }
	) {
		self.api = api
		self.filters = filters
		self.cache = cache
		self.cacheScope = cacheScope
		self.isCurrent = isCurrent
	}
}

/// One screen's response, loaded the way every screen loads: the cached copy
/// first (instantly, even offline), then a refresh from the server.
///
/// - A refresh that can't reach the server keeps the cached value and sets
///   `isOffline`, so the screen stays readable with an offline indicator.
/// - Any other failure keeps whatever is shown and sets `error`.
/// - Switching to a different request (new filters) shows that request's
///   cached copy, or nothing, never the previous filters' numbers. A late
///   answer for a request the screen has moved on from is dropped, and so is
///   an older fetch of the same request once a newer one started.
/// - An answer that arrives after its session ended is dropped (`reset` on
///   sign-out, `ScreenContext.isCurrent`).
@MainActor @Observable
public final class ScreenResource<Value: Decodable & Sendable> {
	public private(set) var value: Value?
	/// When the shown value was saved, while it is a cached copy; nil once a
	/// fresh response arrived.
	public private(set) var cachedAt: Date?
	public private(set) var isLoading = false
	/// The shown value is cached because the server couldn't be reached.
	public private(set) var isOffline = false
	/// The last refresh's failure, other than being offline.
	public private(set) var error: APIError?

	@ObservationIgnored private var current: APIRequest?
	/// Bumped by every fetch; only the latest one may write its answer.
	@ObservationIgnored private var generation = 0

	public init() {}

	/// Forget what is shown and drop any fetch in flight (sign-out: the next
	/// person never sees this one's data).
	public func reset() {
		current = nil
		generation += 1
		value = nil
		cachedAt = nil
		isLoading = false
		isOffline = false
		error = nil
	}

	public func load(_ endpoint: Endpoint<Value>, in context: ScreenContext) async {
		let request = endpoint.request
		if request != current {
			current = request
			let cached = context.cache.read(endpoint, scope: context.cacheScope)
			value = cached?.value
			cachedAt = cached?.savedAt
			isOffline = false
			error = nil
		}
		await fetch(request, in: context)
	}

	/// Re-fetches whatever was last loaded (after a Sync); a no-op before the
	/// first load.
	public func reload(in context: ScreenContext) async {
		guard let current else { return }
		await fetch(current, in: context)
	}

	private func fetch(_ request: APIRequest, in context: ScreenContext) async {
		generation += 1
		let mine = generation
		isLoading = true
		let result: Result<(Value, Data), APIError>
		do {
			let data = try await context.api.data(for: request)
			result = .success((try decode(Value.self, from: data), data))
		} catch {
			result = .failure(error)
		}
		guard request == current, mine == generation else { return }
		isLoading = false
		guard context.isCurrent() else { return }
		switch result {
		case .success(let (fresh, data)):
			context.cache.write(data, for: request, scope: context.cacheScope)
			value = fresh
			cachedAt = nil
			isOffline = false
			error = nil
		case .failure(.offline):
			isOffline = true
		case .failure(let failure):
			isOffline = false
			error = failure
		}
	}
}
