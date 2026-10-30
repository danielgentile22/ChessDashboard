import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("PGN move tree")
struct PGNTreeTests {
	struct Counts: Equatable, CustomStringConvertible {
		var mainline = 0, variations = 0, comments = 0, nags = 0, evals = 0, nodes = 0
		var description: String {
			"main=\(mainline) var=\(variations) com=\(comments) nag=\(nags) eval=\(evals) nodes=\(nodes)"
		}
	}

	/// python-chess 1.11.2 on the same PGNs (the server's parser), per
	/// `<fixture variant>__<view>`; "base" is getGame.json.
	static let reference: [String: Counts] = [
		"analyzed__game": Counts(mainline: 48, nodes: 48),
		"analyzed__my_analysis": Counts(mainline: 48, variations: 3, comments: 48, nags: 3, evals: 48, nodes: 82),
		"analyzed__engine": Counts(mainline: 48, variations: 3, comments: 48, nags: 3, evals: 48, nodes: 82),
		"analyzed__coach": Counts(mainline: 48, variations: 10, comments: 9, evals: 4, nodes: 64),
		"coach__game": Counts(mainline: 77, nodes: 77),
		"coach__my_analysis": Counts(mainline: 77, variations: 1, comments: 1, nodes: 84),
		"coach__coach": Counts(mainline: 77, variations: 1, comments: 2, evals: 1, nodes: 80),
		"base__game": Counts(mainline: 12, nodes: 12),
		"my_analysis__game": Counts(mainline: 59, nodes: 59),
		"my_analysis__my_analysis": Counts(mainline: 59, variations: 20, comments: 6, nags: 21, nodes: 135),
		"unanalyzed__game": Counts(mainline: 58, nodes: 58),
		"unanalyzed__my_analysis": Counts(mainline: 58, comments: 1, nodes: 58),
	]

	/// Every board PGN in every recorded getGame fixture, keyed like `reference`.
	static func fixturePGNs() throws -> [String: String] {
		var pgns: [String: String] = [:]
		for url in try Repo.fixtureFiles() where url.lastPathComponent.hasPrefix("getGame.") {
			let parts = url.deletingPathExtension().lastPathComponent.split(separator: ".")
			let variant = parts.count > 1 ? String(parts[1]) : "base"
			let payload = try decode(API.GamePayload.self, from: Data(contentsOf: url))
			for kind in BoardViewKind.allCases {
				if let pgn = kind.pgn(in: payload.board) {
					pgns["\(variant)__\(Self.key(kind))"] = pgn
				}
			}
		}
		return pgns
	}

	static func key(_ kind: BoardViewKind) -> String {
		kind == .myAnalysis ? "my_analysis" : kind.rawValue
	}

	static func counts(_ tree: PGNTree) -> Counts {
		var c = Counts(mainline: tree.mainline.count - 1, nodes: tree.nodes.count - 1)
		for node in tree.nodes {
			c.variations += max(0, node.children.count - 1)
			c.comments += node.comments.count + node.preComments.count
			c.nags += node.nags.count
			c.evals += node.comments.filter { $0.contains("[%eval") }.count
		}
		return c
	}

	@Test("every getGame fixture PGN parses, with python-chess's counts")
	func everyFixtureParses() throws {
		let pgns = try Self.fixturePGNs()
		#expect(Set(pgns.keys) == Set(Self.reference.keys), "a getGame fixture changed; update the reference")
		for (name, pgn) in pgns.sorted(by: { $0.key < $1.key }) {
			let tree = try PGNTree(pgn: pgn)
			#expect(Self.counts(tree) == Self.reference[name], "\(name)")
		}
	}

	@Test("every fixture view plays the same main line as its Game view")
	func viewsShareTheMainLine() throws {
		let pgns = try Self.fixturePGNs()
		for (name, pgn) in pgns where !name.hasSuffix("__game") && !name.hasSuffix("__coach") {
			let game = try PGNTree(pgn: pgns[name.components(separatedBy: "__")[0] + "__game"]!)
			let view = try PGNTree(pgn: pgn)
			#expect(view.mainline.map { view[$0].san } == game.mainline.map { game[$0].san }, "\(name)")
		}
	}

	@Test("a comment before move 1 belongs to the start position")
	func rootComment() throws {
		let tree = try PGNTree(pgn: "{ Caro-Kann again. } 1. e4 c6 *")
		#expect(tree.displayComments(PGNTree.root) == ["Caro-Kann again."])
		#expect(tree.mainline.count == 3)
	}

	@Test("variations branch from the move they replace; nested ones too")
	func variations() throws {
		let tree = try PGNTree(pgn: "1. e4 e5 (1... c5 2. Nf3 (2. c3 d5) 2... d6) 2. Nf3 *")
		let e5 = tree.mainline[2]
		let e4 = tree.mainline[1]
		#expect(tree[e4].children.count == 2)
		let c5 = tree[e4].children[1]
		#expect(tree[c5].san == "c5" && tree.label(c5) == "1… c5")
		#expect(tree.line(through: c5).map { tree[$0].san } == ["e4", "c5", "Nf3", "d6"])
		let nf3 = tree.next(c5)!
		let c3 = tree[c5].children[1]
		let d5 = tree.next(c3)!
		#expect(tree[c3].san == "c3" && tree[d5].san == "d5")
		#expect(!tree.isOnMainline(d5) && tree.isOnMainline(e5))
		// Out of any depth lands on the main line, where it was left.
		#expect(tree.exitVariation(from: d5) == e4)
		#expect(tree.exitVariation(from: tree.next(nf3)!) == e4)
		#expect(tree.exitVariation(from: e5) == nil)
		#expect(tree[tree.mainline[3]].san == "Nf3")

		// Forward toward a move deep in a variation follows that line.
		#expect(tree.next(e4, toward: d5) == c5)
		#expect(tree.next(c5, toward: d5) == c3)
		#expect(tree.next(d5, toward: d5) == nil)
		#expect(tree.next(e4, toward: e5) == e5)
		#expect(tree.isAncestor(e4, of: d5) && tree.isAncestor(d5, of: d5) && !tree.isAncestor(e5, of: d5))
		// Branch points: a move with an alternative beside it.
		#expect(tree.hasAlternatives(e5) && tree.hasAlternatives(c5) && tree.hasAlternatives(c3))
		#expect(!tree.hasAlternatives(e4) && !tree.hasAlternatives(d5) && !tree.hasAlternatives(PGNTree.root))
	}

	@Test("a comment right after ( comes before the variation's first move")
	func preComment() throws {
		let tree = try PGNTree(pgn: "1. e4 { good } e5 ( { or } 1... c5 { Sicilian } ) *")
		let c5 = tree[tree.mainline[1]].children[1]
		#expect(tree[c5].preComments == ["or"])
		#expect(tree.displayComments(c5) == ["or", "Sicilian"])
		#expect(tree.displayComments(tree.mainline[1]) == ["good"])
	}

	@Test("commands are stripped from comments; eval-only comments disappear")
	func commandsStripped() throws {
		let tree = try PGNTree(pgn: "1. e4 { [%eval 0.18] } 1... c6 { [%eval -1.5] [%clk 0:10:00] Solid. } 2. d4 { [%eval #-3] } *")
		let (e4, c6, d4) = (tree.mainline[1], tree.mainline[2], tree.mainline[3])
		#expect(tree.displayComments(e4).isEmpty)
		#expect(tree.displayComments(c6) == ["Solid."])
		#expect(tree.evaluation(e4) == "+0.18")
		#expect(tree.evaluation(c6) == "-1.50")
		#expect(tree.evaluation(d4) == "#-3")
	}

	@Test("move numbers, suffix glyphs, NAGs, glued numbers, results, 0-0")
	func tokens() throws {
		let tree = try PGNTree(pgn: """
			1.e4 e5 2.Nf3?! Nc6 $1 3. Bc4 Bc5 4. 0-0 Nf6!? 1-0
			""")
		let ids = tree.mainline
		#expect(ids.count == 9)
		#expect(tree.label(ids[3]) == "2. Nf3?!")
		#expect(tree.label(ids[4]) == "2… Nc6!")
		#expect(tree[ids[7]].san == "0-0")
		#expect(tree.moveText(ids[8]) == "Nf6!?")
		#expect(tree[ids[7]].from == BoardSquare(file: 4, rank: 0) && tree[ids[7]].to?.name == "g1")
	}

	@Test("a FEN start position numbers moves from it")
	func fenStart() throws {
		let tree = try PGNTree(pgn: """
			[SetUp "1"]
			[FEN "4k3/8/8/8/8/8/4P3/4K3 b - - 0 40"]

			40... Kd7 41. e4 *
			""")
		#expect(tree.label(tree.mainline[1]) == "40… Kd7")
		#expect(tree.label(tree.mainline[2]) == "41. e4")
	}

	@Test("an illegal move or broken PGN is an error, never a crash")
	func errors() {
		#expect(throws: PGNError.self) { try PGNTree(pgn: "1. e4 e5 2. Ke3 *") }
		#expect(throws: PGNError.unbalanced) { try PGNTree(pgn: "1. e4 (1. d4 *") }
		#expect(throws: PGNError.unbalanced) { try PGNTree(pgn: "1. e4 { open *") }
		#expect(throws: PGNError.self) { try PGNTree(pgn: "[FEN \"nonsense\"]\n1. e4 *") }
	}

	@Test("the diagram is oriented from the bottom side")
	func diagram() throws {
		let tree = try PGNTree(pgn: "1. e4 *")
		let white = BoardDiagram(tree, at: tree.mainline[1], bottom: .white)
		#expect(white.cells.first?.square.name == "a8")
		#expect(white.cells.last?.square.name == "h1")
		#expect(white.cells.first?.piece == .init(kind: .rook, side: .black))
		#expect(white.lastMove == [BoardSquare(file: 4, rank: 1), BoardSquare(file: 4, rank: 3)])
		let black = BoardDiagram(tree, at: PGNTree.root, bottom: .black)
		#expect(black.cells.first?.square.name == "h1")
		#expect(black.cells.last?.square.name == "a8")
		#expect(black.lastMove.isEmpty)
		#expect(white.cells.count == 64 && white.cells.filter { $0.piece != nil }.count == 32)
	}
}
