import ChessDashboardKit
import SwiftUI

/// Sign in with the web login's credentials: the owner password, a username
/// and password on a multi-user server, or read-only guest access.
struct SignInView: View {
	let notice: String?

	@Environment(AppEnvironment.self) private var env
	@State private var password = ""
	@State private var username = ""
	@AppStorage("signIn.usesUsername") private var usesUsername = false
	@State private var error: String?
	@State private var busy = false
	@FocusState private var focus: Field?

	enum Field { case username, password }

	var body: some View {
		NavigationStack {
			Form {
				Section {
					VStack(alignment: .leading, spacing: 6) {
						Text("Chess Dashboard").font(.largeTitle.bold())
						Text("Your over-the-board Games, from your Lichess Studies.")
							.foregroundStyle(Theme.muted.color)
					}
					.listRowBackground(Color.clear)
				}
				if let notice {
					Section {
						Label(notice, systemImage: "clock.badge.exclamationmark")
							.foregroundStyle(Theme.warning.color)
					}
				}
				Section {
					if usesUsername {
						TextField("Username", text: $username)
							.textContentType(.username)
							.textInputAutocapitalization(.never)
							.autocorrectionDisabled()
							.focused($focus, equals: .username)
							.submitLabel(.next)
							.onSubmit { focus = .password }
					}
					SecureField("Password", text: $password)
						.textContentType(.password)
						.focused($focus, equals: .password)
						.submitLabel(.go)
						.onSubmit { Task { await signIn() } }
					Toggle("Sign in with a username", isOn: $usesUsername.animation())
				} footer: {
					Text(usesUsername
						? "For accounts on a multi-user server, such as a coach or a student."
						: "The owner password, same as on the web.")
				}
				if let error {
					Section { Text(error).foregroundStyle(Theme.loss.color) }
				}
				Section {
					Button {
						Task { await signIn() }
					} label: {
						HStack {
							Text("Sign In").bold()
							if busy { Spacer(); ProgressView() }
						}
					}
					.disabled(busy || password.isEmpty || (usesUsername && username.isEmpty))
					// A multi-user server refuses guests; the store remembers once it has shown that.
					if !env.session.isMultiUserServer {
						Button("Continue as Guest") { Task { await guest() } }
							.disabled(busy)
					}
				} footer: {
					if !env.session.isMultiUserServer {
						Text("Guests can read everything but can't Sync.")
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
		}
	}

	private func signIn() async {
		await run { () async throws(APIError) in try await env.session.signIn(password: password, username: usesUsername ? username : nil) }
	}

	private func guest() async {
		await run { () async throws(APIError) in try await env.session.continueAsGuest() }
	}

	private func run(_ action: () async throws(APIError) -> Void) async {
		busy = true
		error = nil
		defer { busy = false }
		do {
			try await action()
			password = ""
		} catch {
			self.error = Self.copy(for: error)
		}
	}

	private static func copy(for error: APIError) -> String {
		switch error {
		case .invalidCredentials(let m), .throttled(let m), .forbidden(let m):
			m.isEmpty ? error.message : m
		default:
			error.message
		}
	}
}
