import Foundation
import Observation

/// The Games screen: every filtered Game, searchable and sortable on the
/// phone (the web table's native filter and sort, applied to the server's
/// rows; nothing is computed).
@MainActor @Observable
public final class GamesModel {
	public enum Sort: String, CaseIterable, Sendable {
		/// The server's order: the archive order, as the web table opens.
		case archive
		case newest, oldest, strongestOpponent, longest

		public var label: String {
			switch self {
			case .archive: "Archive order"
			case .newest: "Newest first"
			case .oldest: "Oldest first"
			case .strongestOpponent: "Strongest opponent"
			case .longest: "Longest Game"
			}
		}
	}

	public let resource = ScreenResource<API.GamesPayload>()
	public var searchText = ""
	public var sort: Sort = .archive
	private let context: ScreenContext

	public init(context: ScreenContext) { self.context = context }

	public func load() async {
		await resource.load(Endpoints.getGames(filters: context.filters.state), in: context)
	}

	/// The loaded Games after the search and the sort.
	public var visibleGames: [API.GameSummary] {
		let games = resource.value?.games ?? []
		let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
		let found = query.isEmpty ? games : games.filter { Self.matches($0, query: query) }
		return Self.sorted(found, by: sort)
	}

	/// The query appears in the opponent, opening, ECO, Series, termination,
	/// or a Tag ("#tactics" and "tactics" both match), like the web table's filter.
	static func matches(_ game: API.GameSummary, query: String) -> Bool {
		let haystack = ([game.opponent, game.opening, game.eco, game.series, game.termination]
			+ game.tags.map { "#" + $0.name }).joined(separator: "\n").lowercased()
		return haystack.contains(query)
	}

	static func sorted(_ games: [API.GameSummary], by sort: Sort) -> [API.GameSummary] {
		// Ties keep the archive order (the index), so the list never jumps.
		let indexed = Array(games.enumerated())
		func ordered(_ key: (API.GameSummary) -> Int?, descending: Bool) -> [API.GameSummary] {
			indexed.sorted { a, b in
				switch (key(a.element), key(b.element)) {
				case let (x?, y?) where x != y: return descending ? x > y : x < y
				case (nil, _?): return false  // unknowns last
				case (_?, nil): return true
				default: return a.offset < b.offset
				}
			}.map(\.element)
		}
		func day(_ game: API.GameSummary) -> Int? {
			game.date.flatMap { Int($0.replacingOccurrences(of: "-", with: "")) }.map { $0 * 1000 + (game.round ?? 0) }
		}
		switch sort {
		case .archive: return games
		case .newest: return ordered(day, descending: true)
		case .oldest: return ordered(day, descending: false)
		case .strongestOpponent: return ordered(\.opponentRating, descending: true)
		case .longest: return ordered(\.moves, descending: true)
		}
	}
}
