import Foundation
import Security
import Synchronization

/// A signed-in session: the bearer token and what the server said about it.
public struct Session: Codable, Sendable, Hashable {
	public var token: String
	public var role: API.Role
	/// Set only in multi-user mode.
	public var username: String?
	/// Whether Sync is allowed. False for a guest.
	public var canWrite: Bool
	public var expiresAt: Date

	public init(token: String, role: API.Role, username: String?, canWrite: Bool, expiresAt: Date) {
		self.token = token
		self.role = role
		self.username = username
		self.canWrite = canWrite
		self.expiresAt = expiresAt
	}

	init(grant: API.SessionGrant) throws(APIError) {
		guard let expiresAt = ISODates.timestamp(grant.expiresAt) else {
			throw .malformedResponse("expires_at \(grant.expiresAt) is not a timestamp")
		}
		self.init(
			token: grant.token, role: grant.role, username: grant.username, canWrite: grant.canWrite,
			expiresAt: expiresAt)
	}

	public func isExpired(at now: Date) -> Bool { now >= expiresAt }

	/// Whose cached responses these are. A multi-user account, the owner, and
	/// a guest never read each other's cache.
	public var cacheScope: String { username.map { "user-\($0)" } ?? role.rawValue }
}

/// Where the session lives between launches. Synchronous on purpose: a
/// Keychain read is microseconds and every request needs the token.
public protocol CredentialStore: Sendable {
	func load() -> Session?
	func save(_ session: Session)
	func clear()
}

/// The session in the Keychain, as one JSON item. `afterFirstUnlock` and
/// never synchronised to iCloud, so it stays on this phone.
public struct KeychainCredentialStore: CredentialStore {
	public let service: String

	public init(service: String = "dev.danielgentile.chessdashboard.session") {
		self.service = service
	}

	private var query: [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: "session",
			kSecAttrSynchronizable as String: false,
		]
	}

	public func load() -> Session? {
		var q = query
		q[kSecReturnData as String] = true
		q[kSecMatchLimit as String] = kSecMatchLimitOne
		var out: CFTypeRef?
		guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data
		else { return nil }
		return try? JSONDecoder().decode(Session.self, from: data)
	}

	public func save(_ session: Session) {
		guard let data = try? JSONEncoder().encode(session) else { return }
		let update = [kSecValueData as String: data]
		if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
			var add = query
			add[kSecValueData as String] = data
			add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
			SecItemAdd(add as CFDictionary, nil)
		}
	}

	public func clear() {
		SecItemDelete(query as CFDictionary)
	}
}

/// For tests and previews.
public final class InMemoryCredentialStore: CredentialStore {
	private let box: Mutex<Session?>
	public init(_ session: Session? = nil) { box = Mutex(session) }
	public func load() -> Session? { box.withLock { $0 } }
	public func save(_ session: Session) { box.withLock { $0 = session } }
	public func clear() { box.withLock { $0 = nil } }
}
