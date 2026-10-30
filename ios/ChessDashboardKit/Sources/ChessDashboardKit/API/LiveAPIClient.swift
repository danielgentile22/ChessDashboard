import Foundation

/// The only type that speaks HTTP to the server.
///
///  - adds `Authorization: Bearer` from the stored session to every
///    authenticated request;
///  - no session, or an expired one, never reaches the network: it throws
///    `.unauthenticated` like a 401 does. `SessionGuard` (wrapped around
///    every client by `AppEnvironment`) turns that into "back to sign-in".
///    A 401 from sign-in itself is just wrong credentials;
///  - other non-2xx bodies become typed `APIError`s; a request that times
///    out becomes `.timedOut`, any other URLError `.offline`.
public struct LiveAPIClient: DashboardAPI {
	/// Ends in `/api/v1/`.
	public let baseURL: URL
	private let credentials: any CredentialStore
	private let session: URLSession
	private let now: @Sendable () -> Date

	public init(
		baseURL: URL, credentials: any CredentialStore, session: URLSession = .shared,
		now: @escaping @Sendable () -> Date = { .now }
	) {
		self.baseURL = baseURL
		self.credentials = credentials
		self.session = session
		self.now = now
	}

	public func data(for request: APIRequest) async throws(APIError) -> Data {
		// `path` is already percent-encoded (ids are escaped as one segment),
		// so it is joined as text: `appending(path:)` would encode it twice.
		guard var url = URL(string: baseURL.absoluteString + request.path) else {
			throw .badRequest("Bad path \(request.path)")
		}
		if !request.query.isEmpty { url.append(queryItems: request.query) }
		var http = URLRequest(url: url, timeoutInterval: Self.timeout(for: request))
		http.httpMethod = request.method.rawValue
		http.setValue("application/json", forHTTPHeaderField: "Accept")
		if let body = request.body {
			http.httpBody = body
			http.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		if request.authenticated {
			guard let stored = credentials.load(), !stored.isExpired(at: now()) else {
				throw .unauthenticated
			}
			http.setValue("Bearer \(stored.token)", forHTTPHeaderField: "Authorization")
		}

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await session.data(for: http)
		} catch let error as URLError where error.code == .timedOut {
			throw .timedOut
		} catch {
			throw .offline
		}
		guard let status = (response as? HTTPURLResponse)?.statusCode else {
			throw .malformedResponse("not an HTTP response")
		}
		guard (200..<300).contains(status) else {
			throw APIError.from(status: status, body: data, authenticated: request.authenticated)
		}
		return data
	}

	/// Seconds to wait for an answer. A Sync runs inside the request on the
	/// server, for up to gunicorn's 120 s worker timeout, so the app waits
	/// longer than that; everything else keeps URLSession's 60 s default.
	static func timeout(for request: APIRequest) -> TimeInterval {
		request.operationId == "runSync" ? 150 : 60
	}
}

/// Wraps any client so an `.unauthenticated` answer (401, expired, signed
/// out elsewhere) ends the session, whichever client produced it. That keeps
/// "expired session routes to sign-in" on one path, live and fixture alike.
///
/// It ends only the session whose token made the request: the token is read
/// before the request goes out and handed to `onUnauthenticated`, so a late
/// 401 for a session that has since been replaced is ignored.
public struct SessionGuard: DashboardAPI {
	public let base: any DashboardAPI
	private let credentials: any CredentialStore
	private let onUnauthenticated: @Sendable (_ token: String?) async -> Void

	public init(
		_ base: any DashboardAPI, credentials: any CredentialStore,
		onUnauthenticated: @escaping @Sendable (_ token: String?) async -> Void
	) {
		self.base = base
		self.credentials = credentials
		self.onUnauthenticated = onUnauthenticated
	}

	public func data(for request: APIRequest) async throws(APIError) -> Data {
		let token = credentials.load()?.token
		do {
			return try await base.data(for: request)
		} catch .unauthenticated {
			// nil (no stored session when it went out) ends whatever is signed in.
			await onUnauthenticated(token)
			throw .unauthenticated
		}
	}
}
