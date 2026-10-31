import ChessDashboardKit
import SwiftUI

@main
struct ChessDashboardApp: App {
	@State private var env: AppEnvironment
	@Environment(\.scenePhase) private var scenePhase

	init() {
		let raw = Bundle.main.object(forInfoDictionaryKey: "CDBaseURL") as? String ?? ""
		guard let baseURL = URL(string: raw) else { fatalError("CDBaseURL is not a URL: \(raw)") }
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		_env = State(initialValue: DebugLaunch.current.makeEnvironment(baseURL: baseURL) {
			AppEnvironment(
				config: AppConfig(baseURL: baseURL), defaults: UserDefaults.standard,
				cachesDirectory: caches)
		})
	}

	var body: some Scene {
		WindowGroup {
			RootView()
				.environment(env)
				.preferredColorScheme(.dark)
				.tint(Theme.primary.color)
				.task {
					guard DebugLaunch.current.guest, env.session.session == nil else { return }
					try? await env.session.continueAsGuest()
				}
		}
		.onChange(of: scenePhase) { _, phase in
			guard phase == .active else { return }
			env.session.checkExpiry()
			Task { await env.refreshMeta() }
		}
	}
}

/// Sign-in while signed out, the tabs once signed in.
struct RootView: View {
	@Environment(AppEnvironment.self) private var env

	var body: some View {
		switch env.session.state {
		case .signedOut(let notice):
			SignInView(notice: notice)
		case .signedIn(let session):
			MainTabView()
				.id(session.cacheScope)  // a different user starts with fresh screens
				.task { await env.refreshMeta() }
		}
	}
}
