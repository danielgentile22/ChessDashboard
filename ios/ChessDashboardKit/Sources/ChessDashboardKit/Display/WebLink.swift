import Foundation

/// A page of the web dashboard, for the "Open on the web" action every screen
/// has and for web-only surfaces such as Reconciliation. Paths match the
/// `dash.register_page` paths in `pages/`.
public enum WebPage: Hashable, Sendable {
	case overview, trends, openings, opponents, events, games, lessons, analysis, reconciliation
	case game(API.GameId)
	/// The Lessons page in pre-game review mode, optionally primed with one opponent.
	case lessonsReview(opponent: API.OpponentId?)

	var path: String {
		switch self {
		case .overview: ""
		case .trends: "trends"
		case .openings: "openings"
		case .opponents: "opponents"
		case .events: "events"
		case .games: "games"
		case .lessons, .lessonsReview: "lessons"
		case .analysis: "analysis"
		case .reconciliation: "reconciliation"
		case .game(let id): "game/\(Endpoints.pathSegment(id))"
		}
	}

	var query: [URLQueryItem] {
		guard case .lessonsReview(let opponent) = self else { return [] }
		return [URLQueryItem(name: "review", value: "1")]
			+ (opponent.map { [URLQueryItem(name: "opponent", value: $0)] } ?? [])
	}

	/// The page's URL on the server that `apiBaseURL` (ending in `/api/v1/`) belongs to.
	public func url(apiBaseURL: URL) -> URL {
		var site = apiBaseURL.absoluteString
		if site.hasSuffix("api/v1/") { site.removeLast("api/v1/".count) }
		// `path` is already percent-encoded, so it is joined as text.
		var url = URL(string: site + path) ?? apiBaseURL
		if !query.isEmpty { url.append(queryItems: query) }
		return url
	}
}
