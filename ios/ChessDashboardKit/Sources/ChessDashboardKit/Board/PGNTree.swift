import ChessKit
import Foundation

/// One board view's PGN as a move tree: every move replayed through ChessKit,
/// so each node carries the position after it.
///
/// Nodes live in a flat array addressed by `ID`. `nodes[0]` is the root (the
/// start position, no move); its comments are the ones before move 1. A
/// node's `children[0]` continues its line and `children[1...]` are the
/// variations that replace that continuation.
///
/// Why not ChessKit's own `PGNParser`: it rejects a comment before move 1
/// (both coach PGNs), drops NAGs followed by a comment, and its index-keyed
/// `MoveTree` returns the wrong move in nested variations.
public struct PGNTree: Sendable {
	public typealias ID = Int

	public struct Node: Sendable, Identifiable {
		public let id: ID
		public let parent: ID?
		public internal(set) var children: [ID] = []
		/// The move as written (check suffixes kept, `!?` glyphs moved to `nags`); "" on the root.
		public let san: String
		/// Full move number of this move ("12" in "12. Nf3" and "12… Nf6").
		public let moveNumber: Int
		/// Who played it; nil on the root.
		public let side: BoardSide?
		/// Half-moves from the start position along this node's line.
		public let ply: Int
		public internal(set) var nags: [Int] = []
		/// Comments after the move, raw (`[%eval]` and other commands included).
		public internal(set) var comments: [String] = []
		/// Comments written before the move, e.g. `( { idea } 3. d4 ...)`.
		public internal(set) var preComments: [String] = []
		/// Where the move went from and to, for the last-move highlight.
		public let from: BoardSquare?
		public let to: BoardSquare?
		let position: Position
	}

	public static let root: ID = 0

	public let tags: [String: String]
	public private(set) var nodes: [Node]
	/// The main line, `mainline[0]` being the root: `mainline[p]` is ply `p`.
	public private(set) var mainline: [ID] = []

	public init(pgn: String) throws(PGNError) {
		var tags: [String: String] = [:]
		var movetext = ""
		for line in pgn.split(separator: "\n", omittingEmptySubsequences: false) {
			if line.hasPrefix("["), let tag = line.firstMatch(of: /^\[(\w+)\s+"(.*)"\]/) {
				tags[String(tag.1)] = String(tag.2)
			} else {
				movetext += line + "\n"
			}
		}
		self.tags = tags

		var start = Position.standard
		if let fen = tags["FEN"] {
			guard let custom = Position(fen: fen) else { throw .badFEN(fen) }
			start = custom
		}
		nodes = [Node(
			id: Self.root, parent: nil, san: "", moveNumber: start.clock.fullmoves, side: nil, ply: 0,
			from: nil, to: nil, position: start)]
		try parseMovetext(Substring(movetext))

		var line = [Self.root]
		while let next = nodes[line[line.count - 1]].children.first { line.append(next) }
		mainline = line
	}

	private mutating func parseMovetext(_ text: Substring) throws(PGNError) {
		// `last` is the node the next move follows. `(` opens a variation that
		// replaces `last`, so play resumes from its parent; `)` returns to `last`.
		var last = Self.root
		var returns: [ID] = []
		var justOpened = false
		var pending: [String] = []  // comments right after `(`: they precede the variation's first move
		var rest = text
		while let c = rest.first {
			if c.isWhitespace {
				rest.removeFirst()
			} else if c == "{" {
				guard let end = rest.firstIndex(of: "}") else { throw .unbalanced }
				let comment = rest[rest.index(after: rest.startIndex)..<end]
					.trimmingCharacters(in: .whitespacesAndNewlines)
				rest = rest[rest.index(after: end)...]
				if justOpened { pending.append(comment) } else { nodes[last].comments.append(comment) }
			} else if c == ";" {
				rest = rest.drop { $0 != "\n" }
			} else if c == "(" {
				rest.removeFirst()
				guard let parent = nodes[last].parent else { throw .unbalanced }
				returns.append(last)
				last = parent
				justOpened = true
			} else if c == ")" {
				rest.removeFirst()
				guard let resume = returns.popLast() else { throw .unbalanced }
				last = resume
				justOpened = false
				pending = []
			} else {
				let token = String(rest.prefix { !$0.isWhitespace && !"{}()".contains($0) })
				rest = rest.dropFirst(token.count)
				if token.hasPrefix("$") {
					guard let nag = Int(token.dropFirst()) else { throw .badToken(token) }
					nodes[last].nags.append(nag)
					continue
				}
				if ["1-0", "0-1", "1/2-1/2", "*"].contains(token) { continue }
				var san = token.replacing(/^\d+\.+/, with: "")  // "12." "12..." "2.Be3"
				if san.isEmpty { continue }
				var nag: Int?
				if let suffix = san.firstMatch(of: /[!?]+$/) {
					nag = Self.suffixNAGs[String(suffix.0)]
					san.removeLast(suffix.0.count)
				}
				last = try play(san, after: last)
				if let nag { nodes[last].nags.append(nag) }
				nodes[last].preComments = pending
				pending = []
				justOpened = false
			}
		}
		if !returns.isEmpty { throw .unbalanced }
	}

	/// Replays `san` from `parent`'s position and appends the new node.
	private mutating func play(_ san: String, after parent: ID) throws(PGNError) -> ID {
		let before = nodes[parent].position
		let notation = san.replacing("0-0-0", with: "O-O-O").replacing("0-0", with: "O-O")
		guard let move = SANParser.parse(move: notation, in: before) else {
			throw .illegalMove(san, fen: before.fen)
		}
		var board = Board(position: before)
		guard let made = board.move(pieceAt: move.start, to: move.end) else {
			throw .illegalMove(san, fen: before.fen)
		}
		if let promoted = move.promotedPiece { _ = board.completePromotion(of: made, to: promoted.kind) }
		let id = nodes.count
		nodes.append(Node(
			id: id, parent: parent, san: san, moveNumber: before.clock.fullmoves,
			side: before.sideToMove == .white ? .white : .black, ply: nodes[parent].ply + 1,
			from: BoardSquare(move.start), to: BoardSquare(move.end), position: board.position))
		nodes[parent].children.append(id)
		return id
	}

	static let suffixNAGs = ["!": 1, "?": 2, "!!": 3, "??": 4, "!?": 5, "?!": 6]
}

/// Why a board view's PGN can't be displayed. The screen shows the view as
/// unavailable instead of crashing (hand-typed coach PGNs may be wrong).
public enum PGNError: Error, Equatable, Sendable {
	case illegalMove(String, fen: String)
	case badFEN(String)
	case badToken(String)
	case unbalanced
}

/// White or Black, for the board (ChessKit stays an implementation detail of the kit).
public enum BoardSide: String, Sendable, Hashable {
	case white, black
}

/// A square, 0-based: file 0 is a, rank 0 is the first rank.
public struct BoardSquare: Hashable, Sendable {
	public let file: Int
	public let rank: Int

	public init(file: Int, rank: Int) {
		self.file = file
		self.rank = rank
	}

	init(_ square: Square) {
		self.init(file: square.file.number - 1, rank: square.rank.value - 1)
	}

	/// "e4".
	public var name: String {
		String(UnicodeScalar(UInt8(97 + file))) + String(rank + 1)
	}
}
