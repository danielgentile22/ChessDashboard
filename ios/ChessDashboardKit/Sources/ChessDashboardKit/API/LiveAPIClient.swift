import Foundation

/// The only type that speaks HTTP to the server.
///
///  - adds `Authorization: Bearer` from the stored session to every
///    authenticated request;
///  - no session, or an expired one, never reaches the network: it throws
///    `.unauthenticated` like a 401 does. `SessionGuard` (wrapped around
///    every client by `AppEnvironment`) turns that into "back to sign-in".
///    A 401 from sign-in itself is just wrong credentials;
///  - other non-2xx bodies become typed `APIError`s, URLError becomes `.offline`.
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
		var http = URLRequest(url: url)
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
}

/// Wraps any client so an `.unauthenticated` answer (401, expired, signed
/// out elsewhere) ends the session, whichever client produced it. That keeps
/// "expired session routes to sign-in" on one path, live and fixture alike.
public struct SessionGuard: DashboardAPI {
	public let base: any DashboardAPI
	private let onUnauthenticated: @Sendable () async -> Void

	public init(_ base: any DashboardAPI, onUnauthenticated: @escaping @Sendable () async -> Void) {
		self.base = base
		self.onUnauthenticated = onUnauthenticated
	}

	public func data(for request: APIRequest) async throws(APIError) -> Data {
		do {
			return try await base.data(for: request)
		} catch .unauthenticated {
			await onUnauthenticated()
			throw .unauthenticated
		}
	}
}
