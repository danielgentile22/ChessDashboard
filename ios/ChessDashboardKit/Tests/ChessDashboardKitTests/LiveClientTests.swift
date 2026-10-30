import Foundation
import Synchronization
import Testing
@testable import ChessDashboardKit

/// Answers every request from `StubProtocol.reply`, recording what was sent.
final class StubProtocol: URLProtocol, @unchecked Sendable {
	struct Reply: Sendable {
		var status: Int
		var body: Data
		var offline = false
	}

	static let reply = Mutex(Reply(status: 200, body: Data("{}".utf8)))
	static let sent = Mutex<[URLRequest]>([])

	static func session() -> URLSession {
		let config = URLSessionConfiguration.ephemeral
		config.protocolClasses = [StubProtocol.self]
		return URLSession(configuration: config)
	}

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		var request = request
		if let stream = request.httpBodyStream {
			stream.open()
			var data = Data()
			var buffer = [UInt8](repeating: 0, count: 4096)
			while stream.hasBytesAvailable {
				let n = stream.read(&buffer, maxLength: buffer.count)
				if n <= 0 { break }
				data.append(buffer, count: n)
			}
			request.httpBody = data
		}
		Self.sent.withLock { $0.append(request) }
		let reply = Self.reply.withLock { $0 }
		if reply.offline {
			client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
			return
		}
		let response = HTTPURLResponse(
			url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: reply.body)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}

// Serialized: the stub is process-wide.
@Suite("Live client", .serialized)
struct LiveClientTests {
	private let base = URL(string: "https://chess.example/api/v1/")!

	private func client(_ session: Session? = .owner()) -> LiveAPIClient {
		StubProtocol.sent.withLock { $0 = [] }
		return LiveAPIClient(
			baseURL: base, credentials: InMemoryCredentialStore(session), session: StubProtocol.session())
	}

	private func reply(_ status: Int, _ body: String) {
		StubProtocol.reply.withLock { $0 = .init(status: status, body: Data(body.utf8)) }
	}

	@Test("sends the bearer token and the filter query to the route")
	func bearerAndQuery() async throws {
		reply(200, String(decoding: try Repo.fixture("getMeta"), as: UTF8.self))
		var filters = FilterState()
		filters.colors = [.black]
		filters.lens = .live
		let c = client()
		_ = try? await c.data(for: Endpoints.getGames(filters: filters).request)
		let meta = try await c.send(Endpoints.getMeta())
		#expect(meta.player == "Test Player")
		let sent = StubProtocol.sent.withLock { $0 }
		#expect(sent[0].url?.absoluteString == "https://chess.example/api/v1/games?colors=Black&lens=live")
		#expect(sent[1].url?.absoluteString == "https://chess.example/api/v1/meta")
		#expect(sent[1].value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
	}

	@Test("sign-in sends JSON and no token")
	func signInHasNoToken() async throws {
		reply(200, String(decoding: try Repo.fixture("createSession"), as: UTF8.self))
		let grant = try await client(nil).send(Endpoints.createSession(body: .init(password: "pw")))
		#expect(grant.role == .owner)
		let sent = try #require(StubProtocol.sent.withLock { $0.first })
		#expect(sent.httpMethod == "POST")
		#expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
		#expect(sent.httpBody == Data(#"{"password":"pw"}"#.utf8))
	}

	@Test("a 401 is an ended session, except on sign-in where it is wrong credentials")
	func unauthorized() async {
		reply(401, #"{"error":{"code":"unauthenticated","message":"Wrong password."}}"#)
		await #expect(throws: APIError.unauthenticated) {
			try await client().send(Endpoints.getMeta())
		}
		await #expect(throws: APIError.invalidCredentials("Wrong password.")) {
			try await client(nil).send(Endpoints.createSession(body: .init(password: "x")))
		}
	}

	@Test("no session or an expired one never reaches the network")
	func expiredLocally() async {
		reply(200, "{}")
		let expired = Session.owner(expiresAt: .now.addingTimeInterval(-5))
		await #expect(throws: APIError.unauthenticated) {
			try await client(expired).send(Endpoints.getMeta())
		}
		#expect(StubProtocol.sent.withLock { $0.isEmpty })
	}

	@Test("error codes map to typed errors")
	func errorMapping() async {
		reply(429, #"{"error":{"code":"throttled","message":"Too many attempts. Wait a few minutes."}}"#)
		await #expect(throws: APIError.throttled("Too many attempts. Wait a few minutes.")) {
			try await client(nil).send(Endpoints.createSession(body: .init(password: "x")))
		}
		reply(404, #"{"error":{"code":"not_found","message":"No such Game."}}"#)
		await #expect(throws: APIError.notFound("No such Game.")) {
			try await client().send(Endpoints.getGame(gameId: "abc"))
		}
		reply(502, #"{"error":{"code":"sync_failed","message":"Lichess is down."}}"#)
		await #expect(throws: APIError.server(status: 502, code: "sync_failed", message: "Lichess is down.")) {
			try await client().send(Endpoints.runSync())
		}
		reply(200, #"{"unexpected":true}"#)
		await #expect(throws: APIError.self) { try await client().send(Endpoints.getMeta()) }
	}

	@Test("no connection is offline")
	func offline() async {
		StubProtocol.reply.withLock { $0.offline = true }
		defer { StubProtocol.reply.withLock { $0.offline = false } }
		await #expect(throws: APIError.offline) { try await client().send(Endpoints.getMeta()) }
	}

	@Test("path ids are escaped as one segment")
	func pathEscaping() async {
		reply(404, "{}")
		_ = try? await client().send(Endpoints.getOpponent(opponentId: "name-a/b c", filters: .all))
		let url = StubProtocol.sent.withLock { $0.first?.url?.absoluteString }
		#expect(url == "https://chess.example/api/v1/opponents/name-a%2Fb%20c?lens=official")
	}
}
