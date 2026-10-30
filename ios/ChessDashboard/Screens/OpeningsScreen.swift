import ChessDashboardKit
import SwiftUI

/// Where the repertoire wins and leaks points: the repertoire tree per color
/// (tap a branch to drill down), Win rate by ECO family, and Top openings.
struct OpeningsScreen: View {
	@Environment(AppEnvironment.self) private var env
	@State private var model: OpeningsModel

	init(context: ScreenContext) { _model = State(initialValue: OpeningsModel(context: context)) }

	var body: some View {
		@Bindable var model = model
		ScreenState(resource: model.resource, retry: model.load) { payload in
			List {
				Section {
					Picker("Color", selection: $model.color) {
						Text("As White").tag(API.Color.white)
						Text("As Black").tag(API.Color.black)
					}
					.pickerStyle(.segmented)
					.listRowBackground(Color.clear)
					if let tree = model.tree {
						RepertoireRows(
							tree: tree, nodes: tree.moves, line: RepertoireLine(color: tree.color, sans: []))
					}
				} header: {
					Text("Repertoire")
				} footer: {
					if let tree = model.tree, !RepertoireDisplay.isEmpty(tree) {
						Text("\(tree.gameCount) Games · \(score(tree.scorePct)) overall score. Branches scoring below that across \(tree.minGames)+ Games are flagged.")
					}
				}
				Section("Win rate by ECO family") {
					if payload.ecoFamilies.isEmpty {
						Text("No ECO data").foregroundStyle(Theme.muted.color)
					} else {
						WDLBarChart(
							bars: payload.ecoFamilies.map {
								.init(id: $0.ecoFamily, label: $0.familyName, win: $0.win, draw: $0.draw, loss: $0.loss)
							},
							summary: "Win rate by ECO family")
					}
				}
				Section("Top openings") {
					if payload.topOpenings.isEmpty {
						Text("No openings in this filter").foregroundStyle(Theme.muted.color)
					}
					ForEach(payload.topOpenings, id: \.self) { opening in
						TopOpeningRow(opening: opening)
					}
				}
			}
		}
		.navigationDestination(for: RepertoireLine.self) { line in
			RepertoireBranchScreen(model: model, line: line)
		}
		.screenChrome(title: "Openings", page: .openings, resource: model.resource)
		.task(id: env.filters.state) { await model.load() }
		.refreshable { await model.load() }
	}
}

private func score(_ pct: Double) -> String { "\(Int(pct.rounded()))%" }

/// The rows for some repertoire moves: a branch with several Games pushes
/// its drill-down; a single-Game leaf links straight to the Game.
private struct RepertoireRows: View {
	let tree: API.OpeningsRepertoireTree
	let nodes: [API.OpeningsRepertoireNode]
	let line: RepertoireLine

	var body: some View {
		if RepertoireDisplay.isEmpty(tree) {
			ContentUnavailableView(
				"No Games as \(tree.color.rawValue) in this filter", systemImage: "checkerboard.rectangle",
				description: Text("The repertoire tree builds itself from your Games' moves."))
		}
		ForEach(nodes, id: \.san) { node in
			if node.gameCount == 1, let game = node.games.first {
				NavigationLink(value: GameRoute(gameID: game.gameId)) {
					RepertoireLeafRow(node: node, game: game)
				}
			} else {
				NavigationLink(value: line.appending(node.san)) {
					RepertoireNodeRow(node: node, baseline: tree.scorePct)
				}
			}
		}
	}
}

private struct RepertoireNodeRow: View {
	let node: API.OpeningsRepertoireNode
	let baseline: Double

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline) {
				Text(RepertoireDisplay.moveLabel(node)).font(.body.weight(.semibold).monospaced())
				Spacer()
				Text("\(node.gameCount) Games").font(.subheadline).foregroundStyle(Theme.muted.color)
				ScoreMark(node: node, baseline: baseline)
			}
			WDLStrip(win: node.win, draw: node.draw, loss: node.loss)
			if node.underperforming {
				Label("Leaking points", systemImage: "exclamationmark.triangle.fill")
					.font(.caption.weight(.semibold))
					.foregroundStyle(Theme.warning.color)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityText)
	}

	private var accessibilityText: String {
		let mark = switch RepertoireDisplay.mark(node, baseline: baseline) {
		case .above: "above"
		case .at: "at"
		case .below: "below"
		}
		return "\(RepertoireDisplay.moveLabel(node)). \(node.gameCount) Games, \(node.win) wins, \(node.draw) draws, \(node.loss) losses. Score \(score(node.scorePct)), \(mark) your \(score(baseline)) baseline."
			+ (node.underperforming ? " Leaking points." : "")
	}
}

private struct ScoreMark: View {
	let node: API.OpeningsRepertoireNode
	let baseline: Double

	var body: some View {
		let (symbol, tint): (String, Color) = switch RepertoireDisplay.mark(node, baseline: baseline) {
		case .above: ("arrowtriangle.up.fill", Theme.win.color)
		case .at: ("circle.fill", Theme.draw.color)
		case .below: ("arrowtriangle.down.fill", Theme.loss.color)
		}
		HStack(spacing: 2) {
			Image(systemName: symbol).imageScale(.small)
			Text(score(node.scorePct)).monospacedDigit()
		}
		.font(.subheadline.weight(.semibold))
		.foregroundStyle(tint)
	}
}

private struct RepertoireLeafRow: View {
	let node: API.OpeningsRepertoireNode
	let game: API.OpeningsGameRef

	var body: some View {
		HStack {
			Text(RepertoireDisplay.moveLabel(node)).font(.body.weight(.semibold).monospaced())
			Spacer()
			GameRefLabel(game: game)
		}
	}
}

/// "Win vs Opponent A", tinted by the outcome.
private struct GameRefLabel: View {
	let game: API.OpeningsGameRef

	var body: some View {
		Text("\(game.outcome.rawValue) vs \(game.opponent)")
			.font(.subheadline)
			.foregroundStyle(tint)
	}

	private var tint: Color {
		switch game.outcome {
		case .win: Theme.win.color
		case .draw: Theme.draw.color
		case .loss: Theme.loss.color
		}
	}
}

/// A proportional W/D/L mini-bar.
struct WDLStrip: View {
	let win: Int
	let draw: Int
	let loss: Int

	var body: some View {
		let total = max(win + draw + loss, 1)
		GeometryReader { geo in
			HStack(spacing: 1) {
				segment(win, total, geo.size.width, Theme.win.color)
				segment(draw, total, geo.size.width, Theme.draw.color)
				segment(loss, total, geo.size.width, Theme.loss.color)
			}
		}
		.frame(height: 6)
		.clipShape(Capsule())
		.accessibilityHidden(true)
	}

	@ViewBuilder
	private func segment(_ count: Int, _ total: Int, _ width: CGFloat, _ color: Color) -> some View {
		if count > 0 {
			Rectangle().fill(color).frame(width: width * CGFloat(count) / CGFloat(total))
		}
	}
}

private struct TopOpeningRow: View {
	let opening: API.OpeningsOpening

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(alignment: .firstTextBaseline) {
				Text(opening.eco).font(.subheadline.weight(.semibold).monospaced())
				Text(opening.opening.isEmpty ? "Unnamed opening" : opening.opening).lineLimit(2)
				Spacer()
				Text("\(Int(opening.winRatePct.rounded()))%")
					.font(.subheadline.weight(.semibold)).monospacedDigit()
			}
			HStack {
				Text("\(opening.gameCount) Games · \(opening.win)W \(opening.draw)D \(opening.loss)L")
					.font(.footnote).foregroundStyle(Theme.muted.color)
				Spacer()
			}
			WDLStrip(win: opening.win, draw: opening.draw, loss: opening.loss)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(opening.eco) \(opening.opening). \(opening.gameCount) Games, \(opening.win) wins, \(opening.draw) draws, \(opening.loss) losses, win rate \(Int(opening.winRatePct.rounded())) percent.")
	}
}

/// One branch of the repertoire tree: its next moves, then every Game that
/// reached it (the ones that ended here marked).
struct RepertoireBranchScreen: View {
	let model: OpeningsModel
	let line: RepertoireLine

	var body: some View {
		List {
			if let node = model.node(at: line), let baseline = model.baseline(for: line.color) {
				Section {
					RepertoireNodeRow(node: node, baseline: baseline)
				}
				if !node.moves.isEmpty, let tree = model.resource.value.map({ line.color == .white ? $0.repertoire.white : $0.repertoire.black }) {
					Section("Next moves") {
						RepertoireRows(tree: tree, nodes: node.moves, line: line)
					}
				}
				Section("Games that reached this position") {
					let ended = Set(node.endedHere.map(\.gameId))
					ForEach(node.games, id: \.gameId) { game in
						NavigationLink(value: GameRoute(gameID: game.gameId)) {
							HStack {
								GameRefLabel(game: game)
								Spacer()
								VStack(alignment: .trailing) {
									if let date = game.date { Text(date) }
									if ended.contains(game.gameId) { Text("ended here") }
								}
								.font(.caption)
								.foregroundStyle(Theme.muted.color)
							}
						}
					}
				}
			} else {
				ContentUnavailableView(
					"Not in this filter", systemImage: "line.3.horizontal.decrease.circle",
					description: Text("No Games reach this position with the current filters."))
			}
		}
		.navigationTitle(line.sans.isEmpty ? "Repertoire" : title)
		.navigationBarTitleDisplayMode(.inline)
	}

	private var title: String {
		// "1. d4 Nf6 2. c4": numbers on White's moves only.
		line.sans.enumerated().map { ply, san in ply % 2 == 0 ? "\(ply / 2 + 1). \(san)" : san }
			.joined(separator: " ")
	}
}
