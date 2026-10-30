import Foundation
import Synchronization
@testable import ChessDashboardKit

/// The repository's shared contract files, read in place. The server's
/// contract tests record `openapi/fixtures/*.json`; these tests decode the
/// same files, so a server change that breaks a Swift decoder fails here.
/// Paths come from this file's location, which works for `swift test` on the
/// Mac and for `xcodebuild test` on a simulator (it reads the host's disk).
enum Repo {
	static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()  // ChessDashboardKitTests
		.deletingLastPathComponent()  // Tests
		.deletingLastPathComponent()  // ChessDashboardKit
		.deletingLastPathComponent()  // ios
		.deletingLastPathComponent()

	static let spec = root.appending(path: "openapi/v1.json")
	static let fixtures = root.appending(path: "openapi/fixtures")

	static func fixtureFiles() throws -> [URL] {
		try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
			.filter { $0.pathExtension == "json" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
	}

	static func fixture(_ name: String) throws -> Data {
		try Data(contentsOf: fixtures.appending(path: "\(name).json"))
	}
}

extension Session {
	static func owner(expiresAt: Date = .now.addingTimeInterval(86_400)) -> Session {
		Session(token: "fixture-token", role: .owner, username: nil, canWrite: true, expiresAt: expiresAt)
	}
}

/// A signed-in environment over the recorded fixtures, with a throwaway cache.
@MainActor
func makeEnvironment(
	session: Session? = .owner(), api: any DashboardAPI = FixtureAPIClient(directory: Repo.fixtures),
	defaults: InMemoryKeyValueStore = InMemoryKeyValueStore(), cache: ResponseCache = .temporary()
) -> AppEnvironment {
	AppEnvironment(
		config: AppConfig(baseURL: URL(string: "https://chess.example/api/v1/")!), api: api,
		credentials: InMemoryCredentialStore(session), defaults: defaults, cache: cache)
}

extension ResponseCache {
	static func temporary() -> ResponseCache {
		ResponseCache(directory: FileManager.default.temporaryDirectory
			.appending(path: "cd-cache-\(UUID().uuidString)"))
	}
}

/// A client a test answers inline, so it can act (sign out, sign in) while
/// a request is in flight.
struct ClosureAPI: DashboardAPI {
	let handler: @Sendable (APIRequest) async throws(APIError) -> Data
	func data(for request: APIRequest) async throws(APIError) -> Data { try await handler(request) }
}

/// Holds every request until the test releases it, in any order.
final class GatedAPI: DashboardAPI {
	private let pending = Mutex<[CheckedContinuation<Data, Never>]>([])

	func data(for request: APIRequest) async throws(APIError) -> Data {
		await withCheckedContinuation { c in pending.withLock { $0.append(c) } }
	}

	func waitForRequests(_ count: Int) async {
		while pending.withLock({ $0.count }) < count { await Task.yield() }
	}

	/// Answer the `index`th request (0 is the first sent).
	func release(_ index: Int, with data: Data) {
		pending.withLock { $0[index] }.resume(returning: data)
	}
}

/// The recorded meta with another player name, to tell two answers apart.
func metaFixture(player: String) throws -> Data {
	var json = try JSONSerialization.jsonObject(with: Repo.fixture("getMeta")) as! [String: Any]
	json["player"] = player
	return try JSONSerialization.data(withJSONObject: json)
}

/// Lets a `@Sendable` test client reach an environment built after it.
@MainActor
final class EnvironmentBox {
	var env: AppEnvironment!
}
