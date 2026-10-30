import Foundation
import Observation

/// One of the board's views. Each exists only when the Game carries its PGN:
/// Game whenever there are moves, My Analysis when the player annotated the
/// Chapter, Engine when Lichess's computer analysis is embedded, Coach when a
/// coach Chapter matched.
public enum BoardViewKind: String, CaseIterable, Sendable, Hashable, Identifiable {
	case game, myAnalysis, engine, coach

	public var id: Self { self }

	public var title: String {
		switch self {
		case .game: "Game"
		case .myAnalysis: "My Analysis"
		case .engine: "Engine"
		case .coach: "Coach"
		}
	}

	func pgn(in board: API.GameBoardPgns) -> String? {
		switch self {
		case .game: board.game
		case .myAnalysis: board.myAnalysis
		case .engine: board.engine
		case .coach: board.coach
		}
	}
}

/// A board view's parsed PGN, or why it can't be shown.
public struct BoardViewTree: Sendable {
	public let kind: BoardViewKind
	public let tree: Result<PGNTree, PGNError>
}

/// The Game detail screen: one Game in full, with a board that steps through
/// each view's moves, variations, and comments.
@MainActor @Observable
public final class GameDetailModel {
	public let resource = ScreenResource<API.GamePayload>()
	public let gameID: API.GameId
	private let context: ScreenContext

	/// The view the user picked; falls back to the first available one.
	public private(set) var selectedKind: BoardViewKind = .game
	/// Where each view's board is, so switching views keeps your place.
	private var cursors: [BoardViewKind: PGNTree.ID] = [:]
	/// Per view, the furthest move reached on the line the board follows, so
	/// stepping back out of a variation and forward again stays in it.
	private var lineTips: [BoardViewKind: PGNTree.ID] = [:]
	@ObservationIgnored private var parsed: (board: API.GameBoardPgns, views: [BoardViewTree])?

	public init(gameID: API.GameId, context: ScreenContext) {
		self.gameID = gameID
		self.context = context
	}

	public func load() async {
		await resource.load(Endpoints.getGame(gameId: gameID), in: context)
	}

	// MARK: Board

	/// The views this Game has, in tab order (parsed once per PGN set).
	public var views: [BoardViewTree] {
		guard let board = resource.value?.board else { return [] }
		if let parsed, parsed.board == board { return parsed.views }
		let views = BoardViewKind.allCases.compactMap { kind in
			kind.pgn(in: board).map { pgn in
				BoardViewTree(kind: kind, tree: Result { () throws(PGNError) in try PGNTree(pgn: pgn) })
			}
		}
		parsed = (board, views)
		return views
	}

	public var selectedView: BoardViewTree? {
		views.first { $0.kind == selectedKind } ?? views.first
	}

	/// The selected view's tree, when its PGN parsed.
	public var tree: PGNTree? {
		guard case .success(let tree)? = selectedView?.tree else { return nil }
		return tree
	}

	/// The node the board shows (the root, the start position, by default).
	public var cursor: PGNTree.ID {
		guard let tree, let kind = selectedView?.kind, let id = cursors[kind], id < tree.nodes.count
		else { return PGNTree.root }
		return id
	}

	/// The player's color at the bottom; White when unknown, as on the web.
	public var orientation: BoardSide {
		resource.value?.playerColor == .black ? .black : .white
	}

	public var diagram: BoardDiagram? {
		tree.map { BoardDiagram($0, at: cursor, bottom: orientation) }
	}

	public func select(_ kind: BoardViewKind) { selectedKind = kind }

	/// The line the board follows, from the first move to its end: the move
	/// list shows it, and forward (buttons, swipe) walks it.
	public var line: [PGNTree.ID] {
		tree?.line(through: lineTip) ?? []
	}

	private var lineTip: PGNTree.ID {
		guard let tree, let kind = selectedView?.kind, let id = lineTips[kind], id < tree.nodes.count
		else { return cursor }
		return id
	}

	/// Show `id`. A move on the line being followed (or before it) keeps the
	/// line; any other move starts following the line through it.
	public func go(to id: PGNTree.ID) {
		guard let tree, !tree.isAncestor(id, of: lineTip) else { return move(to: id) }
		move(to: id, newLine: true)
	}

	private func move(to id: PGNTree.ID, newLine: Bool = false) {
		guard let kind = selectedView?.kind, let tree, id < tree.nodes.count else { return }
		cursors[kind] = id
		if newLine || lineTips[kind] == nil { lineTips[kind] = id }
	}

	public func forward() {
		if let next = tree?.next(cursor, toward: lineTip) { go(to: next) }
	}

	public func back() {
		if let previous = tree?.previous(cursor) { go(to: previous) }
	}

	public func toStart() { go(to: PGNTree.root) }

	/// To the end of the line the board is on.
	public func toEnd() {
		guard let tree else { return }
		var id = cursor
		while let next = tree.next(id, toward: lineTip) { id = next }
		go(to: id)
	}

	public var canGoForward: Bool { tree?.next(cursor) != nil }
	public var canGoBack: Bool { cursor != PGNTree.root }

	/// The moves that can be played next when there is more than one: the
	/// line's own continuation first, then each variation's first move.
	public var nextChoices: [PGNTree.ID] {
		guard let children = tree?[cursor].children, children.count > 1 else { return [] }
		return children
	}

	public var isInVariation: Bool {
		guard let tree else { return false }
		return !tree.isOnMainline(cursor)
	}

	/// "Main line": back to where the main line was left, however deep the
	/// variation, and follow the main line from there.
	public func exitVariation() {
		guard let tree else { return }
		if let branch = tree.exitVariation(from: cursor) { move(to: branch, newLine: true) }
	}

	/// Jump to a played move (the eval chart, a judged move, the critical
	/// moment): the selected view's main line at that ply.
	public func jump(toPly ply: Int) {
		guard let tree else { return }
		move(to: tree.mainline(ply: ply), newLine: true)
	}

	/// The ply of the main-line move the board shows, for the chart's marker; nil off the main line.
	public var mainlinePly: Int? {
		guard let tree, tree.isOnMainline(cursor) else { return nil }
		return tree[cursor].ply
	}

	// MARK: Display

	/// "2nd Annual Adults Only (U1800) · Round 3 · Mar 29, 2026".
	public var subtitle: String {
		guard let game = resource.value?.game else { return "" }
		return [game.series, game.round.map { "Round \($0)" } ?? "", Self.dayText(game.date)].filter { !$0.isEmpty }
			.joined(separator: " · ")
	}

	/// The Game card's rows, hiding empty ones as the web does.
	public var metadataRows: [(label: String, value: String)] {
		guard let payload = resource.value else { return [] }
		let m = payload.metadata
		let opening = [m.eco, m.opening].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
			.joined(separator: " ")
		let rows: [(String, String)] = [
			("Date", Self.dayText(m.date)),
			("Series", m.series),
			("Round", m.round),
			("You played", m.color == .unknown ? "" : m.color.rawValue),
			("Result", m.result),
			("Termination", m.termination),
			("Your rating", m.playerRating.map(RatingFormat.whole) ?? ""),
			("Opponent rating", m.opponentRating.map(RatingFormat.whole) ?? ""),
			("Opening", opening),
			("Moves", m.moves.map(String.init) ?? ""),
			("Study", m.studyName),
		]
		return rows.filter { !$0.1.isEmpty && $0.1 != "?" }.map { (label: $0.0, value: $0.1) }
	}

	/// The USCF Game Record's rows (the opponent is shown separately, as a link).
	public var uscfRows: [(label: String, value: String)] {
		guard let record = resource.value?.uscfRecord else { return [] }
		let rows: [(String, String)] = [
			("Rated Event", record.ratedEventName),
			("Section", record.section),
			("Rating system", record.ratingSystemLabel),
			("Matched by", record.matchedBy == .id ? "Member ID" : "Name"),
		]
		return rows.filter { !$0.1.isEmpty }.map { (label: $0.0, value: $0.1) }
	}

	public var chapterURL: URL? {
		resource.value.flatMap { URL(string: $0.game.chapterUrl) }.flatMap { $0.scheme == nil ? nil : $0 }
	}

	/// "15. g5" for a White move, "15… g5" for a Black one (by ply parity).
	public static func moveLabel(ply: Int, moveNumber: Int, san: String) -> String {
		ply % 2 == 0 ? "\(moveNumber)… \(san)" : "\(moveNumber). \(san)"
	}

	/// "eval +0.54 → -4.38 · engine preferred Nh5".
	public static func criticalMomentDetail(_ moment: API.GameCriticalMoment) -> String {
		let evals = "eval " + signed(moment.evalBefore) + " → " + signed(moment.evalAfter)
		return ([evals] + (moment.bestMove.map { ["engine preferred \($0)"] } ?? [])).joined(separator: " · ")
	}

	/// "Best was h5, then c5 Bxg3 hxg3".
	public static func correction(_ move: API.GameJudgedMove) -> String? {
		guard let best = move.bestMove else { return nil }
		let line = move.refutation.joined(separator: " ")
		return line.isEmpty ? "Best was \(best)" : "Best was \(best), then \(line)"
	}

	static func signed(_ pawns: Double) -> String {
		pawns > 0 ? String(format: "+%.2f", pawns) : String(format: "%.2f", pawns)
	}

	static func dayText(_ iso: API.IsoDate?) -> String {
		guard let date = ISODates.day(iso) else { return iso ?? "" }
		var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
		style.timeZone = .gmt
		return date.formatted(style)
	}
}
