/// Pushes Game detail: every Game row (Games, Lessons, Opponents, Events)
/// navigates with this value, and each tab's NavigationStack registers its
/// destination (`.gameDestination()`).
struct GameRoute: Hashable {
	let gameID: String
}
