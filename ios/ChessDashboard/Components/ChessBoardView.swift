import ChessDashboardKit
import SwiftUI

/// A chess board drawing one `BoardDiagram`: squares, pieces, the last move,
/// and file/rank coordinates on the edge. Display only; stepping is the
/// caller's (swipe left for the next move, right for the previous).
struct ChessBoardView: View {
	let diagram: BoardDiagram
	var onForward: () -> Void = {}
	var onBack: () -> Void = {}

	var body: some View {
		Grid(horizontalSpacing: 0, verticalSpacing: 0) {
			ForEach(0..<8, id: \.self) { row in
				GridRow {
					ForEach(0..<8, id: \.self) { column in
						square(diagram.cells[row * 8 + column], row: row, column: column)
					}
				}
			}
		}
		.aspectRatio(1, contentMode: .fit)
		.clipShape(RoundedRectangle(cornerRadius: 6))
		.contentShape(Rectangle())
		.gesture(
			DragGesture(minimumDistance: 24).onEnded { drag in
				guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
				if drag.translation.width < 0 { onForward() } else { onBack() }
			}
		)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Chess board, \(diagram.bottom.rawValue) at the bottom")
		.accessibilityValue(spokenPosition)
		.accessibilityAdjustableAction { direction in
			switch direction {
			case .increment: onForward()
			case .decrement: onBack()
			@unknown default: break
			}
		}
	}

	private func square(_ cell: BoardDiagram.Cell, row: Int, column: Int) -> some View {
		Rectangle()
			.fill(Theme.board.color)
			.overlay { if cell.isLight { Rectangle().fill(Theme.textGlow.color) } }
			.overlay { if diagram.lastMove.contains(cell.square) { Rectangle().fill(Theme.accentLine.color) } }
			.aspectRatio(1, contentMode: .fit)
			.overlay {
				GeometryReader { geo in
					ZStack {
						if let piece = cell.piece { PieceGlyph(piece: piece, size: geo.size.width) }
						coordinates(cell, row: row, column: column, size: geo.size.width)
					}
				}
			}
	}

	@ViewBuilder
	private func coordinates(_ cell: BoardDiagram.Cell, row: Int, column: Int, size: CGFloat) -> some View {
		let font = Font.system(size: max(7, size * 0.2), weight: .semibold)
		let style = cell.isLight ? Theme.board.color : Theme.muted.color
		ZStack(alignment: .topLeading) {
			Color.clear
			if column == 0 {
				Text(String(cell.square.rank + 1)).font(font).foregroundStyle(style).padding(2)
			}
		}
		ZStack(alignment: .bottomTrailing) {
			Color.clear
			if row == 7 {
				Text(String(cell.square.name.prefix(1))).font(font).foregroundStyle(style).padding(2)
			}
		}
	}

	/// The pieces by square, for VoiceOver: "white king e1, white pawn e4, ...".
	private var spokenPosition: String {
		diagram.cells.compactMap { cell in cell.piece.map { "\($0.name) \(cell.square.name)" } }
			.joined(separator: ", ")
	}
}

/// One piece, drawn with the Unicode chess glyphs: the solid glyph as the
/// fill, the outline glyph on top as the stroke (text presentation forced,
/// so the pawn never turns into an emoji).
private struct PieceGlyph: View {
	let piece: BoardDiagram.Piece
	let size: CGFloat

	var body: some View {
		ZStack {
			Text(glyph(solid: true))
				.foregroundStyle(piece.side == .white ? Theme.text.color : Theme.bg.color)
			Text(glyph(solid: false))
				.foregroundStyle(Theme.bg.color)
		}
		.font(.system(size: size * 0.82))
		.frame(width: size, height: size)
		.offset(y: -size * 0.02)
	}

	private func glyph(solid: Bool) -> String {
		let outline: [BoardDiagram.Piece.Kind: String] = [
			.king: "♔", .queen: "♕", .rook: "♖", .bishop: "♗", .knight: "♘", .pawn: "♙",
		]
		let filled: [BoardDiagram.Piece.Kind: String] = [
			.king: "♚", .queen: "♛", .rook: "♜", .bishop: "♝", .knight: "♞", .pawn: "♟",
		]
		return (solid ? filled : outline)[piece.kind]! + "\u{FE0E}"
	}
}
