import Foundation

/// Every failure a screen can see, keyed off the contract's error codes.
public enum APIError: Error, Sendable, Hashable {
	/// The session is gone (no token, expired, revoked). The session store has
	/// already routed to sign-in by the time a screen sees this.
	case unauthenticated
	/// Sign-in only: wrong username or password.
	case invalidCredentials(String)
	/// Too many wrong passwords from this address (shared with the web login).
	case throttled(String)
	/// Signed in, but this role may not do it (a guest calling Sync, guest
	/// sign-in on a multi-user server).
	case forbidden(String)
	case notFound(String)
	case badRequest(String)
	/// Any other non-2xx, with the contract's code when the body carried one.
	case server(status: Int, code: String?, message: String)
	/// No connection, timeout, DNS: the network never answered.
	case offline
	/// A 2xx body the generated types could not decode: the app is older than
	/// the server's contract.
	case malformedResponse(String)

	/// Copy for a banner or the sign-in form.
	public var message: String {
		switch self {
		case .unauthenticated: "Your session ended. Sign in again."
		case .invalidCredentials: "That password didn't work."
		case .throttled: "Too many wrong passwords. Wait a few minutes and try again."
		case .forbidden(let m), .notFound(let m), .badRequest(let m): m
		case .server: "Something went wrong on the server. Try again in a minute."
		case .offline: "Can't reach the server. Check the connection and try again."
		case .malformedResponse: "The server sent something this version of the app can't read. Update the app."
		}
	}

	/// From a non-2xx status and its body.
	static func from(status: Int, body: Data, authenticated: Bool) -> APIError {
		let error = (try? Wire.decoder.decode(API.ErrorResponse.self, from: body))?.error
		let message = error?.message ?? ""
		switch (status, error?.code) {
		case (401, _): return authenticated ? .unauthenticated : .invalidCredentials(message)
		case (429, _), (_, .throttled): return .throttled(message)
		case (403, _), (_, .forbidden): return .forbidden(message)
		case (404, _), (_, .notFound): return .notFound(message)
		case (400, _), (_, .badRequest): return .badRequest(message)
		default: return .server(status: status, code: error?.code.rawValue, message: message)
		}
	}
}

/// The one seam between the app and the server: "send this request, give me
/// the 2xx body". `LiveAPIClient` speaks HTTP; `FixtureAPIClient` answers from
/// the recorded fixtures for tests and previews. Screens only ever see this
/// protocol (through `ScreenContext`), so every view model runs against
/// fixtures unchanged.
public protocol DashboardAPI: Sendable {
	/// The raw 2xx body. Throws `APIError` for everything else.
	func data(for request: APIRequest) async throws(APIError) -> Data
}

extension DashboardAPI {
	/// Send and decode. Decoding happens here, in one place, for every client.
	public func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
		try decode(Response.self, from: await data(for: endpoint.request))
	}
}

func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws(APIError) -> Response {
	do {
		return try Wire.decoder.decode(type, from: data)
	} catch {
		throw .malformedResponse(String(describing: error))
	}
}
