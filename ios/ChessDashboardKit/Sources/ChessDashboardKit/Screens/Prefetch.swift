import Foundation

extension ScreenContext {
	/// Fetch a response only to cache it, so a screen the user hasn't opened
	/// yet still opens offline (pre-game review, warmed by the Lessons screen
	/// and the Scouting Report). Any failure is ignored: the cache is
	/// disposable and this is only a head start.
	public func prefetch<Value>(_ endpoint: Endpoint<Value>) async {
		let request = endpoint.request
		guard let data = try? await api.data(for: request),
			(try? decode(Value.self, from: data)) != nil
		else { return }
		cache.write(data, for: request, scope: cacheScope)
	}
}
