import Charts
import ChessDashboardKit
import SwiftUI

/// One Game in full: the board with its views (Game, My Analysis, Engine,
/// Coach), the critical moment, the Engine panel, Lessons and Tags, the Game
/// card, the USCF Game Record, and the link to the Chapter on Lichess.
/// Takes no filters or lens: the server reads the unfiltered store here.
struct GameDetailScreen: View {
	@Environment(AppEnvironment.self) private var env
	@Environment(\.openURL) private var openURL
	@State private var model: GameDetailModel

	init(gameID: String, context: ScreenContext) {
		_model = State(initialValue: GameDetailModel(gameID: gameID, context: context))
	}

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { payload in
			ScrollViewReader { scroll in
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						header(payload)
						if payload.forfeit { ForfeitBanner() }
						criticalMoment(payload.engine) { jump(to: $0, scroll: scroll) }
						BoardCard(model: model).id(boardAnchor)
						EngineCard(engine: payload.engine, currentPly: model.mainlinePly) { jump(to: $0, scroll: scroll) }
						LessonsCard(lessons: payload.lessons, tags: payload.tags)
						RowsCard(title: "Game", rows: model.metadataRows)
						if let record = payload.uscfRecord { UscfRecordCard(record: record, rows: model.uscfRows) }
						if let url = model.chapterURL {
							Button {
								openURL(url)
							} label: {
								Label("Open on Lichess", systemImage: "arrow.up.right.square")
									.frame(maxWidth: .infinity)
							}
							.buttonStyle(.bordered)
						}
					}
					.padding()
				}
			}
		}
		.background(Theme.bg.color)
		.navigationTitle(model.resource.value.map { "vs \($0.game.opponent)" } ?? "Game")
		.navigationBarTitleDisplayMode(.large)
		.safeAreaInset(edge: .top, spacing: 0) {
			if model.resource.isOffline { OfflineBanner(cachedAt: model.resource.cachedAt) }
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					if let url = model.chapterURL {
						Button { openURL(url) } label: { Label("Open on Lichess", systemImage: "arrow.up.right.square") }
					}
					Button {
						openURL(env.config.webURL(.game(model.gameID)))
					} label: {
						Label("Open on the Web", systemImage: "safari")
					}
				} label: {
					Label("More Actions", systemImage: "ellipsis.circle")
				}
			}
		}
		.task { await model.load() }
		.refreshable { await model.load() }
	}

	private let boardAnchor = "board"

	private func jump(to ply: Int, scroll: ScrollViewProxy) {
		model.jump(toPly: ply)
		withAnimation { scroll.scrollTo(boardAnchor, anchor: .top) }
	}

	private func header(_ payload: API.GamePayload) -> some View {
		HStack(alignment: .center) {
			Text(model.subtitle).font(.subheadline).foregroundStyle(Theme.muted.color)
			Spacer()
			OutcomePill(outcome: payload.game.outcome)
		}
		.accessibilityElement(children: .combine)
	}

	@ViewBuilder
	private func criticalMoment(_ engine: API.GameEngineView, jump: @escaping (Int) -> Void) -> some View {
		if let moment = engine.criticalMoment {
			Button { jump(moment.ply) } label: {
				VStack(alignment: .leading, spacing: 4) {
					Text("Critical moment").font(.caption.weight(.semibold)).textCase(.uppercase)
						.foregroundStyle(moment.byPlayer ? Theme.loss.color : Theme.win.color)
					Text(moment.headline).font(.headline).foregroundStyle(Theme.text.color)
					Text(GameDetailModel.criticalMomentDetail(moment)).font(.footnote)
						.foregroundStyle(Theme.muted.color)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(12)
				.background(Theme.card.color, in: RoundedRectangle(cornerRadius: ThemeMetrics.radius))
				.overlay(alignment: .leading) {
					UnevenRoundedRectangle(topLeadingRadius: ThemeMetrics.radius, bottomLeadingRadius: ThemeMetrics.radius)
						.fill(moment.byPlayer ? Theme.loss.color : Theme.win.color).frame(width: 4)
				}
			}
			.buttonStyle(.plain)
			.accessibilityHint("Shows this move on the board")
		} else if engine.state == .awaitingAnalysis {
			AwaitingAnalysisHint(tail: "the critical-moment verdict appears here after the next Sync.")
		}
	}
}

// MARK: - Board

private struct BoardCard: View {
	let model: GameDetailModel

	var body: some View {
		Card {
			VStack(alignment: .leading, spacing: 12) {
				if model.views.count > 1 {
					Picker("Board view", selection: Binding(get: { model.selectedView?.kind ?? .game }, set: model.select)) {
						ForEach(model.views.map(\.kind)) { Text($0.title).tag($0) }
					}
					.pickerStyle(.segmented)
				}
				switch model.selectedView?.tree {
				case nil:
					ContentUnavailableView(
						"No board for this game", systemImage: "checkerboard.rectangle",
						description: Text("This Game has no recorded moves to replay."))
				case .failure:
					ContentUnavailableView(
						"Can't show this view", systemImage: "exclamationmark.triangle",
						description: Text("Its PGN has a move the board can't replay. Open it on Lichess instead."))
				case .success(let tree):
					board(tree)
				}
			}
		}
	}

	@ViewBuilder
	private func board(_ tree: PGNTree) -> some View {
		if let diagram = model.diagram {
			ChessBoardView(diagram: diagram, onForward: model.forward, onBack: model.back)
				.animation(.snappy(duration: 0.15), value: diagram)
		}
		HStack {
			Text(tree.label(model.cursor)).font(.headline.monospacedDigit())
			if let eval = tree.evaluation(model.cursor) {
				Text(eval).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.muted.color)
					.accessibilityLabel("Evaluation \(eval)")
			}
			Spacer()
			if model.isInVariation {
				Button("Main line", systemImage: "arrow.uturn.up", action: model.exitVariation)
					.font(.subheadline).buttonStyle(.bordered).accessibilityHint("Steps out of this variation")
			}
		}
		controls
		if !model.nextChoices.isEmpty {
			VStack(alignment: .leading, spacing: 6) {
				Text("Next move").font(.caption).foregroundStyle(Theme.muted.color)
				ScrollView(.horizontal, showsIndicators: false) {
					HStack {
						ForEach(Array(model.nextChoices.enumerated()), id: \.element) { index, id in
							Button(tree.label(id)) { model.go(to: id) }
								.buttonStyle(.bordered)
								.tint(index == 0 ? Theme.primary.color : Theme.accent.color)
								.accessibilityLabel(index == 0 ? "\(tree.label(id)), continues the line" : "\(tree.label(id)), variation")
						}
					}
				}
			}
		}
		let comments = tree.displayComments(model.cursor)
		if !comments.isEmpty {
			VStack(alignment: .leading, spacing: 6) {
				ForEach(comments, id: \.self) { Text($0).font(.callout) }
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(10)
			.background(Theme.card2.color, in: RoundedRectangle(cornerRadius: 8))
		}
		MoveLine(tree: tree, cursor: model.cursor, go: model.go)
	}

	private var controls: some View {
		HStack {
			control("Start", "backward.end.fill", model.toStart, enabled: model.canGoBack)
			control("Previous move", "chevron.backward", model.back, enabled: model.canGoBack)
			control("Next move", "chevron.forward", model.forward, enabled: model.canGoForward)
			control("End of line", "forward.end.fill", model.toEnd, enabled: model.canGoForward)
		}
		.buttonStyle(.bordered)
	}

	private func control(_ label: String, _ symbol: String, _ action: @escaping () -> Void, enabled: Bool) -> some View {
		Button(action: action) {
			Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 28)
		}
		.disabled(!enabled)
		.accessibilityLabel(label)
	}
}

/// The line the board is on, move by move; tap a move to go there.
private struct MoveLine: View {
	let tree: PGNTree
	let cursor: PGNTree.ID
	let go: (PGNTree.ID) -> Void

	var body: some View {
		let line = tree.line(through: cursor)
		if !line.isEmpty {
			ScrollViewReader { proxy in
				ScrollView(.horizontal, showsIndicators: false) {
					LazyHStack(spacing: 4) {
						ForEach(Array(line.enumerated()), id: \.element) { index, id in
							let node = tree[id]
							let numbered = node.side == .white || index == 0
							Button {
								go(id)
							} label: {
								Text(numbered ? tree.label(id) : tree.moveText(id))
									.font(.subheadline.monospacedDigit())
									.padding(.horizontal, 6)
									.padding(.vertical, 4)
									.background(id == cursor ? Theme.primaryWash.color : .clear, in: RoundedRectangle(cornerRadius: 6))
									.foregroundStyle(id == cursor ? Theme.primary.color : Theme.text.color)
							}
							.buttonStyle(.plain)
							.accessibilityLabel(tree.label(id))
							.accessibilityAddTraits(id == cursor ? .isSelected : [])
							.id(id)
						}
					}
				}
				.frame(height: 32)
				.onAppear { proxy.scrollTo(cursor, anchor: .center) }
				.onChange(of: cursor) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
			}
		}
	}
}

// MARK: - Engine

private struct EngineCard: View {
	let engine: API.GameEngineView
	let currentPly: Int?
	let jump: (Int) -> Void

	var body: some View {
		Card(title: "Engine") {
			if engine.state == .awaitingAnalysis {
				AwaitingAnalysisHint(
					tail: "the engine's evals, judgments, and corrections appear here after the next Sync.")
			} else {
				VStack(alignment: .leading, spacing: 12) {
					if !engine.aiSummary.isEmpty {
						Text(engine.aiSummary).font(.callout)
					}
					if !engine.winProbability.isEmpty {
						EvalChart(points: engine.winProbability, currentPly: currentPly, jump: jump)
					}
					ForEach(engine.judgedMoves, id: \.ply) { move in
						Button { jump(move.ply) } label: { JudgedMoveRow(move: move) }
							.buttonStyle(.plain)
							.accessibilityHint("Shows this move on the board")
					}
				}
			}
		}
	}
}

/// White's win % per move; drag to read a move's value, lift to show it on the board.
private struct EvalChart: View {
	let points: [API.GameWinProbabilityPoint]
	let currentPly: Int?
	let jump: (Int) -> Void
	@State private var selectedMove: Double?

	private var selected: API.GameWinProbabilityPoint? {
		guard let selectedMove else { return nil }
		return points.min { abs(Double($0.ply) / 2 - selectedMove) < abs(Double($1.ply) / 2 - selectedMove) }
	}

	var body: some View {
		Chart {
			RuleMark(y: .value("Level", 50)).foregroundStyle(Theme.dim.color)
				.lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
			ForEach(points, id: \.ply) { point in
				AreaMark(x: .value("Move", Double(point.ply) / 2), yStart: .value("Level", 50),
					yEnd: .value("White win %", point.whiteWinPct))
					.foregroundStyle(Theme.textWash2.color)
				LineMark(x: .value("Move", Double(point.ply) / 2), y: .value("White win %", point.whiteWinPct))
					.foregroundStyle(Theme.text.color)
			}
			if let ply = selected?.ply ?? currentPly {
				RuleMark(x: .value("Move", Double(ply) / 2))
					.foregroundStyle(Theme.primary.color)
					.annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
						if let point = selected ?? points.first(where: { $0.ply == ply }) {
							Text("\(GameDetailModel.moveLabel(ply: point.ply, moveNumber: point.moveNumber, san: point.san))  \(Int(point.whiteWinPct.rounded()))%")
								.font(.caption.monospacedDigit())
								.padding(4)
								.background(Theme.card2.color, in: RoundedRectangle(cornerRadius: 4))
						}
					}
			}
		}
		.chartYScale(domain: 0...100)
		.chartYAxis { AxisMarks(values: [0, 50, 100]) }
		.chartYAxisLabel("White win %")
		.chartXAxisLabel("Move")
		.chartXSelection(value: $selectedMove)
		.onChange(of: selectedMove) { old, new in
			if new == nil, let old, let point = points.min(by: { abs(Double($0.ply) / 2 - old) < abs(Double($1.ply) / 2 - old) }) {
				jump(point.ply)
			}
		}
		.frame(height: 190)
		.padding(.top, 18)
		.accessibilityLabel("Evaluation chart, White's win percentage by move")
		.accessibilityValue(accessibilitySummary)
	}

	private var accessibilitySummary: String {
		guard let last = points.last else { return "" }
		return "After \(GameDetailModel.moveLabel(ply: last.ply, moveNumber: last.moveNumber, san: last.san)), White \(Int(last.whiteWinPct.rounded())) percent"
	}
}

private struct JudgedMoveRow: View {
	let move: API.GameJudgedMove

	var body: some View {
		HStack(alignment: .firstTextBaseline) {
			VStack(alignment: .leading, spacing: 2) {
				Text(GameDetailModel.moveLabel(ply: move.ply, moveNumber: move.moveNumber, san: move.san))
					.font(.body.monospacedDigit().weight(.semibold))
				if let correction = GameDetailModel.correction(move) {
					Text(correction).font(.footnote).foregroundStyle(Theme.muted.color)
				}
			}
			Spacer()
			Text(move.severity.rawValue.capitalized)
				.font(.caption.weight(.semibold))
				.padding(.horizontal, 8)
				.padding(.vertical, 3)
				.foregroundStyle(color)
				.background(color.opacity(0.15), in: Capsule())
		}
		.padding(10)
		.background(Theme.card2.color, in: RoundedRectangle(cornerRadius: 8))
		.accessibilityElement(children: .combine)
	}

	private var color: Color {
		switch move.severity {
		case .inaccuracy: Theme.accent.color
		case .mistake: Theme.warning.color
		case .blunder: Theme.loss.color
		}
	}
}

/// The quiet degrade for an un-analysed Game: teaches the one click on Lichess.
private struct AwaitingAnalysisHint: View {
	let tail: String

	var body: some View {
		(Text("Awaiting analysis").bold() + Text(". Request computer analysis on this Chapter on Lichess and " + tail))
			.font(.footnote)
			.foregroundStyle(Theme.muted.color)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(12)
			.background(Theme.card.color, in: RoundedRectangle(cornerRadius: ThemeMetrics.radius))
	}
}

// MARK: - Side cards

private struct LessonsCard: View {
	let lessons: [String]
	let tags: [API.Tag]

	var body: some View {
		Card(title: lessons.count > 1 ? "Lessons (\(lessons.count))" : "Lesson") {
			VStack(alignment: .leading, spacing: 10) {
				if lessons.isEmpty {
					Text("No Lesson written for this game yet.").font(.subheadline.weight(.semibold))
					Text("Add a comment starting with `Lesson:` to the Chapter on Lichess and it will appear here after the next Sync.")
						.font(.footnote).foregroundStyle(Theme.muted.color)
				}
				ForEach(lessons, id: \.self) { lesson in
					Label { Text(lesson) } icon: { Image(systemName: "lightbulb.fill").foregroundStyle(Theme.accent.color) }
						.font(.callout)
				}
				if !tags.isEmpty {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack { ForEach(tags, id: \.self) { TagChip($0) } }
					}
				}
			}
		}
	}
}

private struct RowsCard: View {
	let title: String
	let rows: [(label: String, value: String)]

	var body: some View {
		Card(title: title) {
			VStack(spacing: 8) {
				ForEach(rows, id: \.label) { row in
					LabeledContent(row.label) { Text(row.value).multilineTextAlignment(.trailing) }
						.font(.subheadline)
				}
			}
		}
	}
}

private struct UscfRecordCard: View {
	@Environment(AppEnvironment.self) private var env
	@Environment(\.openURL) private var openURL
	let record: API.GameUscfRecord
	let rows: [(label: String, value: String)]

	var body: some View {
		Card(title: "USCF Game Record") {
			VStack(spacing: 8) {
				ForEach(rows, id: \.label) { row in
					LabeledContent(row.label) { Text(row.value).multilineTextAlignment(.trailing) }
						.font(.subheadline)
				}
				LabeledContent("Opponent") {
					if let url = URL(string: record.opponentUrl), !record.opponentUrl.isEmpty {
						Button("\(record.opponentName) (\(record.opponentId))") { openURL(url) }
					} else {
						Text(record.opponentName)
					}
				}
				.font(.subheadline)
				if record.colorConflict {
					Button {
						openURL(env.config.webURL(.reconciliation))
					} label: {
						Label("USCF disagrees about this game. Review it in Reconciliation on the web.",
							systemImage: "exclamationmark.triangle")
							.font(.footnote)
							.foregroundStyle(Theme.warning.color)
							.frame(maxWidth: .infinity, alignment: .leading)
					}
					.buttonStyle(.plain)
				}
			}
		}
	}
}

private struct ForfeitBanner: View {
	var body: some View {
		Label("Forfeit: no game was played, so USCF never rated it.", systemImage: "flag.slash")
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(Theme.warning.color)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(12)
			.background(Theme.warningWash.color, in: RoundedRectangle(cornerRadius: ThemeMetrics.radius))
	}
}

private struct OutcomePill: View {
	let outcome: API.GameOutcome

	var body: some View {
		Text(outcome.rawValue)
			.font(.subheadline.weight(.semibold))
			.padding(.horizontal, 10)
			.padding(.vertical, 4)
			.foregroundStyle(color)
			.background(color.opacity(0.15), in: Capsule())
	}

	private var color: Color {
		switch outcome {
		case .win: Theme.win.color
		case .loss: Theme.loss.color
		default: Theme.draw.color
		}
	}
}

private struct Card<Content: View>: View {
	var title: String?
	@ViewBuilder let content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let title { Text(title).font(.headline) }
			content
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.background(Theme.card.color, in: RoundedRectangle(cornerRadius: ThemeMetrics.radius))
	}
}
