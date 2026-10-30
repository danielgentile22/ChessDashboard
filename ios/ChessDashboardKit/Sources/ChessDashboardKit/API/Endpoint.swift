import Foundation

public enum HTTPMethod: String, Sendable, Hashable {
	case get = "GET"
	case post = "POST"
	case put = "PUT"
	case patch = "PATCH"
	case delete = "DELETE"
}

/// One request, untyped: what a client sends and what the cache keys on.
/// `path` is relative to the base URL (which ends in `/api/v1/`).
public struct APIRequest: Sendable, Hashable {
	public var operationId: String
	public var method: HTTPMethod
	public var path: String
	public var query: [URLQueryItem]
	public var body: Data?
	/// False only for `createSession`: no bearer token is sent, and a 401
	/// means wrong credentials rather than an expired session.
	public var authenticated: Bool

	/// The path plus the query string in the order it was built. Filter
	/// encoding is canonical (see `FilterState.queryItems`), so equal filter
	/// states give equal keys.
	public var routeKey: String {
		var parts = URLComponents()
		parts.queryItems = query.isEmpty ? nil : query
		return method.rawValue + " " + path + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
	}
}

/// A request that knows its response type. Build one with the generated
/// factories (`Endpoints.getOverview(filters:)`), never by hand.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
	public var request: APIRequest

	init(
		operationId: String, method: HTTPMethod, path: String, query: [URLQueryItem], body: Data?,
		authenticated: Bool
	) {
		request = APIRequest(
			operationId: operationId, method: method, path: path, query: query, body: body,
			authenticated: authenticated)
	}
}

// Helpers the generated factories call.
extension Endpoints {
	static func pathSegment(_ value: String) -> String {
		var allowed = CharacterSet.urlPathAllowed
		allowed.remove("/")
		return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
	}

	static func query(_ name: String, _ value: String?) -> [URLQueryItem] {
		value.map { [URLQueryItem(name: name, value: $0)] } ?? []
	}

	static func query(_ name: String, _ values: [String]?) -> [URLQueryItem] {
		(values ?? []).map { URLQueryItem(name: name, value: $0) }
	}

	static func query(_ name: String, _ value: Bool?) -> [URLQueryItem] {
		value.map { [URLQueryItem(name: name, value: $0 ? "true" : "false")] } ?? []
	}

	static func query(_ name: String, _ value: Int?) -> [URLQueryItem] {
		value.map { [URLQueryItem(name: name, value: String($0))] } ?? []
	}

	static func jsonBody<T: Encodable>(_ value: T) -> Data? {
		try? Wire.encoder.encode(value)
	}
}

/// The one JSON configuration both directions use. Keys are mapped by the
/// generated `CodingKeys`, dates stay ISO strings (see `ISODates`).
enum Wire {
	static let decoder = JSONDecoder()
	static let encoder: JSONEncoder = {
		let e = JSONEncoder()
		e.outputFormatting = [.sortedKeys]
		return e
	}()
}
