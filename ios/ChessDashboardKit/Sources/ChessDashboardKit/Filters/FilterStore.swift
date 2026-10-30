import Foundation
import Observation

/// Small persisted values (the filter state, the server's sign-in mode).
/// `UserDefaults` in the app, a dictionary in tests.
public protocol KeyValueStore: AnyObject {
	func data(forKey key: String) -> Data?
	func bool(forKey key: String) -> Bool
	func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}

public final class InMemoryKeyValueStore: KeyValueStore {
	private var values: [String: Any] = [:]
	public init() {}
	public func data(forKey key: String) -> Data? { values[key] as? Data }
	public func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
	public func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// The one app-wide filter state every screen reads. Persisted across
/// launches; a stored value this build can't read falls back to "all".
@MainActor @Observable
public final class FilterStore {
	public var state: FilterState {
		didSet { if state != oldValue { persist() } }
	}

	@ObservationIgnored private let defaults: any KeyValueStore
	static let key = "filters.v1"

	public init(defaults: any KeyValueStore) {
		self.defaults = defaults
		state = defaults.data(forKey: Self.key)
			.flatMap { try? JSONDecoder().decode(FilterState.self, from: $0) } ?? .all
	}

	public func apply(_ preset: API.MetaPreset, options: API.MetaFilterOptions?) {
		state = FilterState(preset: preset, options: options, lens: state.lens)
	}

	/// Back to "all" with the Official lens (sign-out: the next person starts clean).
	public func clear() { state = .all }

	private func persist() {
		defaults.set(try? JSONEncoder().encode(state), forKey: Self.key)
	}
}
