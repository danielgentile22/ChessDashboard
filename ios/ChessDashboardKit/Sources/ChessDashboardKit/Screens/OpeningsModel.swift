import Foundation
import Observation

/// One branch of a repertoire tree, as the moves from the root: what the
/// opening drill-down pushes. Resolved against the current response, so a
/// filter change that removes the branch shows its empty state instead of
/// stale numbers.
public struct RepertoireLine: Hashable, Sendable {
	public let color: API.Color
	public let sans: [String]

	public init(color: API.Color, sans: [String]) {
		self.color = color
		self.sans = sans
	}

	public func appending(_ san: String) -> RepertoireLine {
		RepertoireLine(color: color, sans: sans + [san])
	}
}

/// The Openings screen: the repertoire tree for the picked color, the ECO
/// family chart, and the Top openings table.
@MainActor @Observable
public final class OpeningsModel {
	public let resource = ScreenResource<API.OpeningsPayload>()
	public var color: API.Color = .white
	private let context: ScreenContext

	public init(context: ScreenContext) { self.context = context }

	public func load() async {
		await resource.load(Endpoints.getOpenings(filters: context.filters.state), in: context)
	}

	/// The picked color's tree.
	public var tree: API.OpeningsRepertoireTree? { resource.value.map { Self.tree($0, color) } }

	public func node(at line: RepertoireLine) -> API.OpeningsRepertoireNode? {
		guard let payload = resource.value else { return nil }
		var moves = Self.tree(payload, line.color).moves
		var found: API.OpeningsRepertoireNode?
		for san in line.sans {
			guard let next = moves.first(where: { $0.san == san }) else { return nil }
			found = next
			moves = next.moves
		}
		return found
	}

	public func baseline(for color: API.Color) -> Double? {
		resource.value.map { Self.tree($0, color).scorePct }
	}

	private static func tree(_ payload: API.OpeningsPayload, _ color: API.Color) -> API.OpeningsRepertoireTree {
		color == .white ? payload.repertoire.white : payload.repertoire.black
	}
}

/// How the web draws a repertoire node: the move label and the score marker.
public enum RepertoireDisplay {
	public enum Mark: Sendable { case above, at, below }

	/// "1. d4" for White's moves, "1... Nf6" for Black's.
	public static func moveLabel(ply: Int, san: String) -> String {
		"\((ply + 1) / 2)\(ply % 2 == 1 ? "." : "...") \(san)"
	}

	public static func moveLabel(_ node: API.OpeningsRepertoireNode) -> String {
		moveLabel(ply: node.ply, san: node.san)
	}

	/// The branch's score against the color's overall score.
	public static func mark(_ node: API.OpeningsRepertoireNode, baseline: Double) -> Mark {
		node.scorePct > baseline ? .above : node.scorePct < baseline ? .below : .at
	}

	/// No Games as this color in the filter.
	public static func isEmpty(_ tree: API.OpeningsRepertoireTree) -> Bool { tree.gameCount == 0 }
}
