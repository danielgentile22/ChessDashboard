import Foundation
import Observation

/// Sign-in, guest, sign-out, and the session's lifetime. The root view shows
/// the sign-in screen whenever `state` is `.signedOut`.
///
/// One server, three ways in, all through `POST /api/v1/session`: the owner
/// password, "Continue as guest" (owner-mode servers only; a multi-user server
/// answers 403), or a username plus password (multi-user servers). There is
/// no unauthenticated way to ask a server which mode it runs, so the sign-in
/// screen offers all three and shows the server's answer.
@MainActor @Observable
public final class SessionStore {
	public enum State: Equatable, Sendable {
		/// `notice` explains an automatic sign-out ("Your session ended").
		case signedOut(notice: String?)
		case signedIn(Session)
	}

	public private(set) var state: State

	@ObservationIgnored private let credentials: any CredentialStore
	@ObservationIgnored private let api: any DashboardAPI
	@ObservationIgnored private let now: @Sendable () -> Date
	/// Runs on every sign-out, manual or automatic (the environment wipes the
	/// response cache and the filters).
	@ObservationIgnored public var onSignOut: @MainActor () -> Void = {}

	public static let expiredNotice = "Your session ended. Sign in again to keep going."

	/// `api` is used only for sign-in (an unauthenticated request).
	public init(
		credentials: any CredentialStore, api: any DashboardAPI,
		now: @escaping @Sendable () -> Date = { .now }
	) {
		self.credentials = credentials
		self.api = api
		self.now = now
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
		try await grant(API.SessionRequest(guest: true))
	}

	public func signOut() {
		end(notice: nil)
	}

	/// The server (or the clock) says the session is over: back to sign-in
	/// with an explanation. Idempotent, so several failing requests at once
	/// sign out once.
	public func sessionEnded() {
		guard session != nil else { return }
		end(notice: Self.expiredNotice)
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
	}

	private func end(notice: String?) {
		credentials.clear()
		state = .signedOut(notice: notice)
		onSignOut()
	}
}
