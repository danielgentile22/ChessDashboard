import ChessDashboardKit
import SwiftUI

/// A Game to push: tapping any Game anywhere (a Lesson card, a Scouting
/// Report row, an awaiting-analysis row) pushes its Game detail.
struct GameRoute: Hashable {
	let gameID: String
}

extension View {
	/// Where a pushed `GameRoute` lands. Declared once per navigation stack,
	/// on its root screen.
	func gameDestination() -> some View {
		navigationDestination(for: GameRoute.self) { route in
			PlaceholderScreen(title: "Game", page: .game(route.gameID))
		}
	}
}
