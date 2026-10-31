import ChessDashboardKit
import SwiftUI

/// Launch arguments that open the app straight onto one screen, for agents and
/// `ios/scripts/shot.sh` (`make ios-shot`). Debug builds only: Release ignores
/// every argument, so this is never a way in on a real install.
///
///   -CDFixtures          answer from `openapi/fixtures`, no server needed
///   -CDGuest             continue as guest on launch (skips the sign-in screen)
///   -CDScreen <screen>   select a tab or push a More screen (`Screen` below)
///   -CDGame <id>         push one Game's detail on the Games tab
struct DebugLaunch {
	/// Every screen `-CDScreen` can open. `shot.sh --list` prints the same names.
	enum Screen: String, Hashable {
		case overview
		case trends
		case games
		case lessons
		case opponents
		case more
		case openings
		case events
		case analysis
		case game
	}

	/// The Game `-CDScreen game` opens without `-CDGame` (in the fixtures).
	static let fixtureGameID: API.GameId = "chap0001"

	var fixtures = false
	var guest = false
	var screen: Screen?
	var gameID: API.GameId?

	static let current = DebugLaunch(arguments: ProcessInfo.processInfo.arguments)

	init(arguments: [String]) {
		#if DEBUG
		func value(after flag: String) -> String? {
			guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
			return arguments[i + 1]
		}
		fixtures = arguments.contains("-CDFixtures")
		guest = arguments.contains("-CDGuest")
		screen = value(after: "-CDScreen").flatMap(Screen.init(rawValue:))
		gameID = value(after: "-CDGame")
		if screen == .game, gameID == nil { gameID = Self.fixtureGameID }
		if screen == nil, gameID != nil { screen = .game }
		#endif
	}

	/// The tab to open on, if a screen was asked for.
	var tab: MainTabView.TabID? {
		switch screen {
		case nil: nil
		case .overview: .overview
		case .trends: .trends
		case .games, .game: .games
		case .lessons: .lessons
		case .opponents: .opponents
		case .more, .openings, .events, .analysis: .more
		}
	}

	/// The More tab's initial navigation path. Untyped, so the stack still
	/// takes every other route its screens push (Games, Events, lines).
	var morePath: NavigationPath {
		var path = NavigationPath()
		if let screen, [.openings, .events, .analysis].contains(screen) { path.append(screen) }
		return path
	}

	/// The Games tab's initial navigation path.
	var gamesPath: NavigationPath {
		var path = NavigationPath()
		if let gameID { path.append(GameRoute(gameID: gameID)) }
		return path
	}

	/// The environment: the live app, or one over the recorded fixtures with a
	/// throwaway session, filters and cache (and a clock before the fixture
	/// session's expiry), so a screenshot never touches the real app's state.
	@MainActor func makeEnvironment(baseURL: URL, live: () -> AppEnvironment) -> AppEnvironment {
		guard fixtures else { return live() }
		// #filePath is this file on the Mac; the simulator reads the host's disk.
		let repo = URL(filePath: #filePath).deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let caches = FileManager.default.temporaryDirectory.appending(path: "debug-launch-\(UUID())")
		return AppEnvironment(
			config: AppConfig(baseURL: baseURL),
			api: FixtureAPIClient(directory: repo.appending(path: "openapi/fixtures")),
			credentials: InMemoryCredentialStore(), defaults: InMemoryKeyValueStore(),
			cache: ResponseCache(directory: caches),
			now: { Date(timeIntervalSince1970: 1_735_689_600) })  // 2025-01-01
	}
}

extension View {
	/// Where a `DebugLaunch.Screen` pushed onto the More tab goes.
	func debugLaunchDestination(_ context: ScreenContext?) -> some View {
		navigationDestination(for: DebugLaunch.Screen.self) { screen in
			if let context {
				switch screen {
				case .openings: OpeningsScreen(context: context)
				case .events: EventsScreen(context: context)
				case .analysis: AnalysisScreen(context: context)
				default: EmptyView()
				}
			}
		}
	}
}
