import CryptoKit
import Foundation

/// The last successful response per (route, filter state, user), as JSON
/// files in the app's Caches directory, so a screen opens instantly and stays
/// readable offline.
///
/// Disposable, like the server's caches: never a source of truth, and every
/// filesystem or decoding failure degrades to "no cache" rather than an error.
/// The OS may purge Caches at any time; that is fine.
public struct ResponseCache: Sendable {
	public let directory: URL

	public init(directory: URL) {
		self.directory = directory
	}

	/// A cache that never holds anything (tests that don't care, previews).
	public static let disabled = ResponseCache(directory: URL(filePath: "/dev/null/none"))

	public struct Entry<Value: Sendable>: Sendable {
		public var value: Value
		public var savedAt: Date
	}

	/// The stored response for this request and scope, if one decodes.
	public func read<Response>(_ endpoint: Endpoint<Response>, scope: String) -> Entry<Response>? {
		let file = url(for: endpoint.request, scope: scope)
		guard let data = try? Data(contentsOf: file),
			let value = try? Wire.decoder.decode(Response.self, from: data)
		else { return nil }
		let savedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
			.contentModificationDate ?? .distantPast
		return Entry(value: value, savedAt: savedAt)
	}

	/// Store a raw 2xx body. Failures are ignored.
	public func write(_ data: Data, for request: APIRequest, scope: String) {
		let file = url(for: request, scope: scope)
		try? FileManager.default.createDirectory(
			at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		try? data.write(to: file, options: .atomic)
	}

	/// Forget everything (sign-out).
	public func wipe() {
		try? FileManager.default.removeItem(at: directory)
	}

	/// `<scope>/<sha256 of the route key>.json`. Hashing keeps any filter
	/// value (slashes, unicode Series names) a legal file name.
	func url(for request: APIRequest, scope: String) -> URL {
		let digest = SHA256.hash(data: Data(request.routeKey.utf8))
			.map { String(format: "%02x", $0) }.joined()
		let folder = SHA256.hash(data: Data(scope.utf8)).prefix(8)
			.map { String(format: "%02x", $0) }.joined()
		return directory.appending(path: folder).appending(path: "\(digest).json")
	}
}
