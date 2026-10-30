import Foundation
import Observation

/// Sign-in, guest, sign-out, and the session's lifetime. The root view shows
/// the sign-in screen whenever `state` is `.signedOut`.
///
/// One server, three ways in, all through `POST /api/v1/session`: the owner
/// password, "Continue as guest" (owner-mode servers only; a multi-user server
/// answers 403), or a username plus password (multi-user servers). There is
/// no unauthenticated way to ask a server which mode it runs, so the store
/// remembers what the server last showed (`isMultiUserServer`): until then the
/// sign-in screen offers all three and shows the server's answer.
@MainActor @Observable
public final class SessionStore {
	public enum State: Equatable, Sendable {
		/// `notice` explains an automatic sign-out ("Your session ended").
		case signedOut(notice: String?)
		case signedIn(Session)
	}

	/// Why a session ended.
	public enum EndReason: Sendable {
		/// The person tapped Sign out.
		case signedOut
		/// The token expired or the server answered 401.
		case expired
	}

	public private(set) var state: State
	/// The server has shown it runs multi-user accounts (a sign-in came back
	/// with a username, or guest sign-in was refused), so "Continue as guest"
	/// can't work there. Remembered across launches; an owner-password
	/// sign-in clears it.
	public private(set) var isMultiUserServer: Bool {
		didSet { defaults.set(isMultiUserServer, forKey: Self.multiUserKey) }
	}

	@ObservationIgnored private let credentials: any CredentialStore
	@ObservationIgnored private let api: any DashboardAPI
	@ObservationIgnored private let defaults: any KeyValueStore
	@ObservationIgnored private let now: @Sendable () -> Date
	/// Runs on every sign-out, manual or automatic. The environment forgets
	/// the shown meta either way and wipes the cache and filters only on an
	/// explicit sign-out.
	@ObservationIgnored public var onSignOut: @MainActor (EndReason) -> Void = { _ in }

	public static let expiredNotice = "Your session ended. Sign in again to keep going."
	static let multiUserKey = "server.multiUser"

	/// `api` is used only for sign-in (an unauthenticated request).
	public init(
		credentials: any CredentialStore, api: any DashboardAPI,
		defaults: any KeyValueStore = InMemoryKeyValueStore(),
		now: @escaping @Sendable () -> Date = { .now }
	) {
		self.credentials = credentials
		self.api = api
		self.defaults = defaults
		self.now = now
		isMultiUserServer = defaults.bool(forKey: Self.multiUserKey)
		if let stored = credentials.load() {
			if stored.isExpired(at: now()) {
				credentials.clear()
				state = .signedOut(notice: Self.expiredNotice)
			} else {
				state = .signedIn(stored)
			}
		} else {
			state = .signedOut(notice: nil)
		}
	}

	public var session: Session? {
		if case .signedIn(let s) = state { s } else { nil }
	}

	/// Owner password, or username plus password on a multi-user server.
	public func signIn(password: String, username: String? = nil) async throws(APIError) {
		let name = username?.trimmingCharacters(in: .whitespaces)
		try await grant(API.SessionRequest(password: password, username: name?.isEmpty == false ? name : nil))
	}

	/// Read-only access, like the web's guest login.
	public func continueAsGuest() async throws(APIError) {
		do {
			try await grant(API.SessionRequest(guest: true))
		} catch .forbidden(let message) {
			isMultiUserServer = true  // only a multi-user server refuses guests
			throw .forbidden(message)
		}
	}

	public func signOut() {
		end(.signedOut)
	}

	/// The server (or the clock) says the session is over: back to sign-in
	/// with an explanation. Idempotent, so several failing requests at once
	/// sign out once. With `token`, only the session that made the failing
	/// request ends: a late 401 for an earlier session never signs out the
	/// one that replaced it.
	public func sessionEnded(token: String? = nil) {
		guard let session, token == nil || token == session.token else { return }
		end(.expired)
	}

	/// Call when the app comes to the foreground: a session that expired
	/// while the phone slept routes to sign-in before any screen loads.
	public func checkExpiry() {
		if let session, session.isExpired(at: now()) { sessionEnded() }
	}

	private func grant(_ body: API.SessionRequest) async throws(APIError) {
		let grant = try await api.send(Endpoints.createSession(body: body))
		let session = try Session(grant: grant)
		credentials.save(session)
		state = .signedIn(session)
		// A guest grant says nothing new (an ungated server grants it as owner).
		if body.guest != true { isMultiUserServer = session.username != nil }
	}

	private func end(_ reason: EndReason) {
		credentials.clear()
		state = .signedOut(notice: reason == .expired ? Self.expiredNotice : nil)
		onSignOut(reason)
	}
}
