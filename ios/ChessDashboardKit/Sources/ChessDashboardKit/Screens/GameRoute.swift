/// Push this to open one Game's detail screen, from any list that shows a
/// Game (Games, crosstables, the opening drill-down, Lessons, Opponents).
/// Every tab's NavigationStack registers the destination once
/// (`.gameDestination()` in the app), so a list only builds the value:
/// `NavigationLink(value: GameRoute(gameID: game.gameId))`.
public struct GameRoute: Hashable, Sendable {
	public let gameID: API.GameId

	public init(gameID: API.GameId) {
		self.gameID = gameID
	}
}
