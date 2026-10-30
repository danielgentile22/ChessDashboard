import ChessKit
import Foundation

/// What the board view draws for one node: 64 squares in screen order (top
/// left first), oriented with `bottom` at the bottom, and the last move.
public struct BoardDiagram: Hashable, Sendable {
	public struct Piece: Hashable, Sendable {
		public enum Kind: String, Sendable, CaseIterable {
			case king, queen, rook, bishop, knight, pawn
		}

		public let kind: Kind
		public let side: BoardSide

		/// Spoken name for VoiceOver, e.g. "white knight".
		public var name: String { "\(side.rawValue) \(kind.rawValue)" }
	}

	public struct Cell: Hashable, Sendable, Identifiable {
		public let square: BoardSquare
		public let piece: Piece?
		public var id: BoardSquare { square }
		public var isLight: Bool { (square.file + square.rank) % 2 == 1 }
	}

	public let bottom: BoardSide
	/// Row by row from the top of the screen.
	public let cells: [Cell]
	/// The last move's from and to squares, highlighted.
	public let lastMove: Set<BoardSquare>

	/// The position after `id`, seen from `bottom`'s side.
	public init(_ tree: PGNTree, at id: PGNTree.ID, bottom: BoardSide) {
		let node = tree[id]
		var pieces: [BoardSquare: Piece] = [:]
		for piece in node.position.pieces {
			pieces[BoardSquare(piece.square)] = Piece(
				kind: Self.kind(piece.kind), side: piece.color == .white ? .white : .black)
		}
		let ranks = bottom == .white ? Array((0..<8).reversed()) : Array(0..<8)
		let files = bottom == .white ? Array(0..<8) : Array((0..<8).reversed())
		cells = ranks.flatMap { rank in
			files.map { file in
				let square = BoardSquare(file: file, rank: rank)
				return Cell(square: square, piece: pieces[square])
			}
		}
		self.bottom = bottom
		lastMove = Set([node.from, node.to].compactMap { $0 })
	}

	private static func kind(_ kind: ChessKit.Piece.Kind) -> Piece.Kind {
		switch kind {
		case .king: .king
		case .queen: .queen
		case .rook: .rook
		case .bishop: .bishop
		case .knight: .knight
		case .pawn: .pawn
		}
	}
}
