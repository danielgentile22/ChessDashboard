import ChessDashboardKit
import SwiftUI

/// Every Game in the archive after filters: search, sort, and each Game's
/// USCF match status. Tap a Game to open it.
struct GamesScreen: View {
	@Environment(AppEnvironment.self) private var env
	@State private var model: GamesModel

	init(context: ScreenContext) { _model = State(initialValue: GamesModel(context: context)) }

	var body: some View {
		@Bindable var model = model
		ScreenState(resource: model.resource, retry: model.load) { payload in
			List {
				if payload.games.isEmpty {
					ContentUnavailableView(
						"No Games in this filter", systemImage: "list.bullet.rectangle",
						description: Text("Loosen the filters to see more Games."))
				} else if model.visibleGames.isEmpty {
					ContentUnavailableView.search(text: model.searchText)
				} else {
					Section {
						ForEach(model.visibleGames, id: \.gameId) { game in
							NavigationLink(value: GameRoute(gameID: game.gameId)) {
								GameSummaryRow(game: game)
							}
						}
					} header: {
						Text(countLabel(shown: model.visibleGames.count, total: payload.gamesCount))
					}
				}
			}
			.searchable(text: $model.searchText, prompt: "Opponent, opening, ECO, Series, or #Tag")
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Picker("Sort", selection: $model.sort) {
						ForEach(GamesModel.Sort.allCases, id: \.self) { Text($0.label).tag($0) }
					}
				} label: {
					Label("Sort: \(model.sort.label)", systemImage: "arrow.up.arrow.down")
				}
			}
		}
		.screenChrome(title: "Games", page: .games, resource: model.resource)
		.task(id: env.filters.state) { await model.load() }
		.refreshable { await model.load() }
	}

	private func countLabel(shown: Int, total: Int) -> String {
		shown == total ? "\(total) Games" : "\(shown) of \(total) Games"
	}
}
