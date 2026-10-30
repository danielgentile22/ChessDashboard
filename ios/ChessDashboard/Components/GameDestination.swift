import ChessDashboardKit
import SwiftUI

extension View {
	/// Registers where a `GameRoute` goes. Applied once to the root of every
	/// tab's NavigationStack, so any list can push a Game by value.
	func gameDestination() -> some View {
		navigationDestination(for: GameRoute.self) { route in
			GameDetailPlaceholder(gameID: route.gameID)
		}
	}
}

/// Stands in for the Game detail screen until it lands (#120 swaps
/// `gameDestination()` to the real screen and deletes this).
private struct GameDetailPlaceholder: View {
	let gameID: API.GameId

	var body: some View {
		PlaceholderScreen(title: "Game", page: .game(gameID))
	}
}
