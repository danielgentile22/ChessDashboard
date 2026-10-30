import Foundation

/// Walking the tree: forward and back, into and out of variations, and the
/// main line by ply (the eval chart's and judged moves' x-axis).
extension PGNTree {
	public subscript(id: ID) -> Node { nodes[id] }

	/// The next move on this line, if any.
	public func next(_ id: ID) -> ID? { nodes[id].children.first }

	/// The next move on the line through `tip`: toward `tip` while `id` comes
	/// before it on that line, then that line's own continuation. Stepping
	/// back out of a variation and forward again stays in the variation.
	public func next(_ id: ID, toward tip: ID) -> ID? {
		var node = tip
		while let parent = nodes[node].parent {
			if parent == id { return node }
			node = parent
		}
		return next(id)
	}

	/// The move before, or nil at the start position.
	public func previous(_ id: ID) -> ID? { nodes[id].parent }

	/// Whether `id` is `descendant` or one of the moves leading to it.
	public func isAncestor(_ id: ID, of descendant: ID) -> Bool {
		var node: ID? = descendant
		while let n = node {
			if n == id { return true }
			node = nodes[n].parent
		}
		return false
	}

	/// Whether another move could have been played instead of `id` (it or a
	/// sibling starts a variation): the move list marks these branch points.
	public func hasAlternatives(_ id: ID) -> Bool {
		guard let parent = nodes[id].parent else { return false }
		return nodes[parent].children.count > 1
	}

	/// The node at ply `ply` of the main line, clamped to the Game's length.
	public func mainline(ply: Int) -> ID {
		mainline[min(max(ply, 0), mainline.count - 1)]
	}

	public func isOnMainline(_ id: ID) -> Bool {
		let ply = nodes[id].ply
		return ply < mainline.count && mainline[ply] == id
	}

	/// Where the main line was left: the main-line move the outermost
	/// variation around `id` branched from, at any nesting depth. Nil when
	/// `id` is already on the main line.
	public func exitVariation(from id: ID) -> ID? {
		guard !isOnMainline(id) else { return nil }
		var node = id
		while !isOnMainline(node), let parent = nodes[node].parent { node = parent }
		return node
	}

	/// The line `id` sits on, from the first move to its end: the moves
	/// leading here, then the continuation after it.
	public func line(through id: ID) -> [ID] {
		var line: [ID] = []
		var node: ID? = id
		while let n = node, n != Self.root {
			line.append(n)
			node = nodes[n].parent
		}
		line.reverse()
		var tail = next(id)
		while let n = tail {
			line.append(n)
			tail = next(n)
		}
		return line
	}

	/// "12. Nf3", "12… Nf6", with the NAG glyphs ("12. Nf3!?").
	public func label(_ id: ID) -> String {
		let node = nodes[id]
		guard let side = node.side else { return "Start" }
		let number = side == .white ? "\(node.moveNumber). " : "\(node.moveNumber)… "
		return number + node.san + node.nags.compactMap(Self.moveGlyph).joined()
	}

	/// The move with its glyph but no number ("Nf3!?"), for a move list that numbers White's moves only.
	public func moveText(_ id: ID) -> String {
		nodes[id].san + nodes[id].nags.compactMap(Self.moveGlyph).joined()
	}

	/// The comments to show at `id`: the ones before and after the move, with
	/// every `[%...]` command (evals, clocks, arrows) stripped and empty ones dropped.
	public func displayComments(_ id: ID) -> [String] {
		(nodes[id].preComments + nodes[id].comments).compactMap { comment in
			let text = comment.replacing(/\[%[^\]]*\]/, with: "")
				.replacing(/\s+/, with: " ")
				.trimmingCharacters(in: .whitespaces)
			return text.isEmpty ? nil : text
		}
	}

	/// The engine's evaluation after the move, from its `[%eval]` comment:
	/// "+0.18", "-1.20", "#-3". Nil when the move carries none.
	public func evaluation(_ id: ID) -> String? {
		for comment in nodes[id].comments {
			guard let match = comment.firstMatch(of: /\[%eval\s+([^\]\s]+)\]/) else { continue }
			let raw = String(match.1)
			if raw.hasPrefix("#") { return raw }
			guard let pawns = Double(raw) else { return raw }
			return pawns > 0 ? String(format: "+%.2f", pawns) : String(format: "%.2f", pawns)
		}
		return nil
	}

	static func moveGlyph(_ nag: Int) -> String? {
		switch nag {
		case 1: "!"
		case 2: "?"
		case 3: "!!"
		case 4: "??"
		case 5: "!?"
		case 6: "?!"
		default: nil
		}
	}
}
