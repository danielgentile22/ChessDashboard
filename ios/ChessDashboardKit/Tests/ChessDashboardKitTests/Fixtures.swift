import Foundation
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
	session: Session? = .owner(), api: FixtureAPIClient = FixtureAPIClient(directory: Repo.fixtures),
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
