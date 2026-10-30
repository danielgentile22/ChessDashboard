import ChessDashboardKit
import SwiftUI

/// The Scouting Report: the pre-game dossier on one opponent. Their USCF
/// identity and then-vs-now rating, your record, every Game, the openings they
/// bring, how the Games ended, and what facing them taught you. Opened once,
/// it stays readable offline (with its pre-game review).
struct ScoutingReportScreen: View {
	let name: String
	@Environment(AppEnvironment.self) private var env
	@Environment(\.openURL) private var openURL
	@State private var model: ScoutingReportModel
	@State private var reviewing = false
	private let context: ScreenContext

	init(opponentID: API.OpponentId, name: String, context: ScreenContext) {
		self.name = name
		self.context = context
		_model = State(initialValue: ScoutingReportModel(opponentID: opponentID, context: context))
	}

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { report in
			List {
				if let identity = report.uscfIdentity { identitySection(identity) }
				statsSection(report)
				if report.gamesCount == 0 {
					Section { NoGamesMatch() }
				} else {
					gamesSection(report.games)
					openingsSection("When you have White", report.openingsAsWhite)
					openingsSection("When you have Black", report.openingsAsBlack)
					terminationsSection(report.terminations)
				}
				lessonsSection(report)
			}
		}
		.screenChrome(title: name, page: .opponents, resource: model.resource)
		.navigationBarTitleDisplayMode(.inline)
		.task(id: env.filters.state) { await model.load() }
		.refreshable { await model.load() }
		.fullScreenCover(isPresented: $reviewing) {
			ReviewScreen(opponentID: model.opponentID, context: context)
		}
	}

	private func identitySection(_ identity: API.OpponentUscfIdentity) -> some View {
		Section("USCF") {
			Button {
				if let url = URL(string: identity.profileUrl) { openURL(url) }
			} label: {
				HStack {
					VStack(alignment: .leading, spacing: 2) {
						Text(identity.name).font(.headline)
						Text("Member #\(identity.memberId)").font(.caption).foregroundStyle(Theme.muted.color)
					}
					Spacer()
					Image(systemName: "arrow.up.right.square").foregroundStyle(Theme.primary.color)
				}
			}
			.accessibilityHint("Opens their page on ratings.uschess.org")
			if let tvn = model.thenVsNow {
				HStack(spacing: 4) {
					Text("Rated \(RatingFormat.whole(tvn.then)) when you last played")
						.foregroundStyle(Theme.muted.color)
					Text("·").foregroundStyle(Theme.dim.color)
					Text("\(RatingFormat.whole(tvn.now)) now (\(tvn.change.text))")
						.foregroundStyle(tvn.change.tone.color)
				}
				.font(.subheadline)
				.accessibilityElement(children: .combine)
			}
		}
	}

	private func statsSection(_ report: API.OpponentPayload) -> some View {
		Section {
			Grid(horizontalSpacing: 12, verticalSpacing: 12) {
				GridRow {
					StatTile(label: "Score", value: report.record.score)
					StatTile(label: "Wins", value: "\(report.record.win)", tint: report.record.win > 0 ? Theme.win.color : Theme.text.color)
					StatTile(label: "Draws", value: "\(report.record.draw)", tint: Theme.draw.color)
				}
				GridRow {
					StatTile(label: "Losses", value: "\(report.record.loss)", tint: report.record.loss > 0 ? Theme.loss.color : Theme.text.color)
					StatTile(label: "Their rating", value: RatingFormat.whole(report.theirRating))
					StatTile(
						label: "Rating gap", value: model.ratingGap?.text ?? "None",
						tint: model.ratingGap?.tone.color ?? Theme.muted.color)
				}
			}
			.padding(.vertical, 4)
		} footer: {
			Text("Rating gap is their rating minus yours; positive means they're stronger.")
		}
	}

	private func gamesSection(_ games: [API.GameSummary]) -> some View {
		Section("Your Games") {
			ForEach(games, id: \.gameId) { game in
				NavigationLink(value: GameRoute(gameID: game.gameId)) {
					VStack(alignment: .leading, spacing: 4) {
						GameSummaryLine(game: game, showOpponent: false)
						Text(gameFacts(game))
							.font(.caption)
							.foregroundStyle(Theme.muted.color)
					}
				}
			}
		}
	}

	private func gameFacts(_ game: API.GameSummary) -> String {
		var parts = ["You \(RatingFormat.whole(game.playerRating)), them \(RatingFormat.whole(game.opponentRating))"]
		if !game.termination.isEmpty { parts.append(game.termination) }
		if let moves = game.moves { parts.append("\(moves) moves") }
		return parts.joined(separator: " · ")
	}

	private func openingsSection(_ title: String, _ openings: [API.OpponentOpening]) -> some View {
		Section(title) {
			if openings.isEmpty {
				Text("No opening data").foregroundStyle(Theme.muted.color)
			}
			ForEach(openings, id: \.self) { o in
				VStack(alignment: .leading, spacing: 4) {
					HStack(alignment: .firstTextBaseline) {
						Text(o.opening.isEmpty ? o.eco : o.opening).font(.subheadline)
						Spacer()
						Text(o.eco).font(.caption.monospaced()).foregroundStyle(Theme.muted.color)
					}
					RecordBar(win: o.win, draw: o.draw, loss: o.loss)
				}
			}
		}
	}

	private func terminationsSection(_ terminations: [API.OpponentTermination]) -> some View {
		Section("How your Games ended") {
			ForEach(terminations, id: \.termination) { t in
				LabeledContent(t.termination, value: "\(t.games)")
			}
		}
	}

	private func lessonsSection(_ report: API.OpponentPayload) -> some View {
		Section {
			if report.lessons.isEmpty {
				Text("No Lessons written from these Games yet.").foregroundStyle(Theme.muted.color)
			}
			ForEach(Array(report.lessons.enumerated()), id: \.offset) { _, lesson in
				NavigationLink(value: GameRoute(gameID: lesson.game.gameId)) {
					LessonCardBody(text: lesson.text, game: lesson.game, showOpponent: false)
				}
			}
			if model.canReview {
				Button {
					reviewing = true
				} label: {
					Label("Review before facing \(report.opponent)", systemImage: "rectangle.stack")
						.font(.headline)
				}
			}
		} header: {
			Text("What facing \(report.opponent) taught you")
		}
	}
}
