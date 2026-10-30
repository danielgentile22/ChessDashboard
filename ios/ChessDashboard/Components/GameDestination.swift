import ChessDashboardKit
import SwiftUI

extension View {
	/// Registers where a `GameRoute` goes. Applied once to the root of every
	/// tab's NavigationStack, so any list can push a Game by value.
	func gameDestination() -> some View {
		navigationDestination(for: GameRoute.self) { route in
			GameDetailDestination(gameID: route.gameID)
		}
	}
}

/// Game detail for a pushed `GameRoute` (the tabs only exist while signed in).
private struct GameDetailDestination: View {
	@Environment(AppEnvironment.self) private var env
	let gameID: API.GameId

	var body: some View {
		if let context = env.context { GameDetailScreen(gameID: gameID, context: context) }
	}
}
