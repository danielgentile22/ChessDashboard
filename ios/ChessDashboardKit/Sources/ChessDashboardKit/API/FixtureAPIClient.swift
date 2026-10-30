import Foundation
import Synchronization

/// Answers from the server's recorded fixtures (`openapi/fixtures`), for
/// tests and previews. A request for operation `getX` gets `getX.json`, or
/// `getX.<variant>.json` after `use(variant:for:)`. Every request is logged,
/// and any operation can be made to fail, so a test can drive "offline", "401"
/// or "403" through the same seam a screen uses.
public final class FixtureAPIClient: DashboardAPI {
	private struct State {
		var fixtures: [String: Data]
		var variants: [String: String] = [:]
		var failures: [String: APIError] = [:]
		var failAll: APIError?
		var requests: [APIRequest] = []
	}

	private let state: Mutex<State>

	/// Fixtures by file name without `.json` (`getMeta`, `getMeta.lichess_only`).
	public init(fixtures: [String: Data]) {
		state = Mutex(State(fixtures: fixtures))
	}

	/// Every `*.json` file in `directory`.
	public convenience init(directory: URL) {
		let files = (try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil)) ?? []
		var fixtures: [String: Data] = [:]
		for file in files where file.pathExtension == "json" {
			fixtures[file.deletingPathExtension().lastPathComponent] = try? Data(contentsOf: file)
		}
		self.init(fixtures: fixtures)
	}

	public func use(variant: String?, for operationId: String) {
		state.withLock { $0.variants[operationId] = variant }
	}

	/// Make one operation (or, with nil, every operation) throw `error`.
	/// Pass a nil error to stop failing.
	public func fail(_ operationId: String? = nil, with error: APIError?) {
		state.withLock {
			if let operationId { $0.failures[operationId] = error } else { $0.failAll = error }
		}
	}

	/// Replace one fixture body (e.g. a test's own variation of a recording).
	public func set(_ data: Data, for name: String) {
		state.withLock { $0.fixtures[name] = data }
	}

	public var requests: [APIRequest] { state.withLock { $0.requests } }

	public func data(for request: APIRequest) async throws(APIError) -> Data {
		let result: Result<Data, APIError> = state.withLock { s in
			s.requests.append(request)
			if let error = s.failures[request.operationId] ?? s.failAll { return .failure(error) }
			let name = s.variants[request.operationId].map { "\(request.operationId).\($0)" }
				?? request.operationId
			guard let data = s.fixtures[name] else {
				return .failure(.notFound("No fixture \(name).json"))
			}
			return .success(data)
		}
		return try result.get()
	}
}
