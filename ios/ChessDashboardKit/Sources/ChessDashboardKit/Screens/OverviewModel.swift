import Foundation
import Observation

/// The Overview screen: "how am I doing?". KPIs, the USCF profile card, the
/// top recurring weakness, last-20 form, the Win / Draw / Loss breakdown, how
/// Games ended, and the milestone timeline. Everything follows the filters
/// and lens except the USCF card, which follows Syncs.
@MainActor @Observable
public final class OverviewModel {
	public let resource = ScreenResource<API.OverviewPayload>()
	private let context: ScreenContext

	public init(context: ScreenContext) { self.context = context }

	public func load() async {
		await resource.load(Endpoints.getOverview(filters: context.filters.state), in: context)
	}

	public var payload: API.OverviewPayload? { resource.value }

	/// No Games match the filters: the screen shows the empty state (the
	/// USCF card still shows, it follows Syncs).
	public var isEmpty: Bool { payload?.gamesCount == 0 }

	public var kpis: [KPI] { payload.map(Self.kpis) ?? [] }
	public var form: FormSummary { payload.map { Self.form($0.streak) } ?? FormSummary(badges: [], stats: [], indicator: nil) }
	public var outcomeSlices: [OutcomeSlice] { payload.map { Self.outcomeSlices($0.outcomeCounts) } ?? [] }
	public var milestones: [MilestoneRow] { payload?.milestones.enumerated().map { MilestoneRow(index: $0, $1) } ?? [] }
	public var uscfCard: USCFCard { payload.map { Self.uscfCard($0.uscfCard) } ?? .hidden }

	// MARK: KPIs

	/// One KPI tile. Color only where it carries meaning (win green, loss red),
	/// like the web.
	public struct KPI: Hashable, Sendable, Identifiable {
		public enum Tone: Sendable { case neutral, win, loss }
		public let title: String
		public let value: String
		public let tone: Tone
		/// Long text (the opening name) wraps instead of shrinking.
		public let isText: Bool
		public var id: String { title }
		public var accessibilityLabel: String { "\(title): \(value)" }
	}

	static func kpis(_ p: API.OverviewPayload) -> [KPI] {
		let k = p.kpis
		return [
			KPI(title: "Games", value: String(p.gamesCount), tone: .neutral, isText: false),
			KPI(title: "Win %", value: percent(k.winPct), tone: .win, isText: false),
			KPI(title: "Draw %", value: percent(k.drawPct), tone: .neutral, isText: false),
			KPI(title: "Loss %", value: percent(k.lossPct), tone: .loss, isText: false),
			KPI(title: "Current Rating", value: RatingFormat.whole(k.rating), tone: .neutral, isText: false),
			KPI(title: "Peak Rating", value: RatingFormat.whole(k.peakRating), tone: .neutral, isText: false),
			KPI(
				title: "Performance Rating", value: k.performanceRating.map(String.init) ?? "None",
				tone: .neutral, isText: false),
			KPI(title: "Longest Win Streak", value: String(k.longestWinStreak), tone: .neutral, isText: false),
			KPI(title: "Unique Opponents", value: String(k.uniqueOpponents), tone: .neutral, isText: false),
			KPI(
				title: "Favorite Opening", value: k.favoriteOpening.isEmpty ? "None" : k.favoriteOpening,
				tone: .neutral, isText: true),
		]
	}

	/// "57.1%", "0%": the server's one decimal, without a trailing ".0".
	static func percent(_ value: Double) -> String {
		value.formatted(.number.precision(.fractionLength(0...1)).locale(Self.locale)) + "%"
	}

	static let locale = Locale(identifier: "en_US")

	// MARK: Form

	public struct FormBadge: Hashable, Sendable {
		public let outcome: API.OverviewFormOutcome
		/// The non-color channel: W, D, L, or ? for an unfinished Game.
		public var letter: String { outcome == .unknown ? "?" : String(outcome.rawValue.prefix(1)) }
	}

	public struct FormStat: Hashable, Sendable {
		public let label: String
		public let value: String
		public let outcome: API.OverviewFormOutcome?
	}

	/// The fire (win Streak of 2+) or cold (loss Streak of 3+) indicator.
	public struct Indicator: Hashable, Sendable {
		public let symbol: String
		public let count: Int
		public let blazing: Bool
		public let accessibilityLabel: String
	}

	public struct FormSummary: Hashable, Sendable {
		/// Oldest to newest.
		public let badges: [FormBadge]
		public let stats: [FormStat]
		public let indicator: Indicator?
	}

	static func form(_ s: API.OverviewStreak) -> FormSummary {
		let current = s.currentOutcome?.rawValue ?? "none"
		return FormSummary(
			badges: s.last20.map(FormBadge.init),
			stats: [
				FormStat(label: "Unbeaten streak", value: String(s.longestUnbeaten), outcome: .win),
				FormStat(label: "Win streak", value: String(s.longestWinStreak), outcome: .win),
				FormStat(label: "Current (\(current))", value: String(s.currentCount), outcome: s.currentOutcome),
			],
			indicator: indicator(s.indicator))
	}

	static func indicator(_ i: API.OverviewFormIndicator) -> Indicator? {
		switch i.kind {
		case .none:
			nil
		case .fire:
			Indicator(symbol: "🔥", count: i.count, blazing: i.blazing, accessibilityLabel: "\(i.count)-game win Streak")
		case .cold:
			Indicator(symbol: "🧊", count: i.count, blazing: false, accessibilityLabel: "\(i.count)-game losing Streak")
		}
	}

	// MARK: Win / Draw / Loss

	public struct OutcomeSlice: Hashable, Sendable, Identifiable {
		public let outcome: API.OverviewFormOutcome
		public let label: String
		public let games: Int
		/// Share of the breakdown, whole percent.
		public let percentText: String
		public var id: String { label }
	}

	static func outcomeSlices(_ c: API.OverviewOutcomeCounts) -> [OutcomeSlice] {
		let all: [(API.OverviewFormOutcome, String, Int)] = [
			(.win, "Wins", c.win), (.draw, "Draws", c.draw), (.loss, "Losses", c.loss),
			(.unknown, "Unfinished", c.unknown),
		]
		let total = all.reduce(0) { $0 + $1.2 }
		return all.filter { $0.2 > 0 }.map { outcome, label, games in
			let share = Double(games) / Double(total) * 100
			return OutcomeSlice(
				outcome: outcome, label: label, games: games,
				percentText: "\(Int(share.rounded(.toNearestOrAwayFromZero)))%")
		}
	}

	// MARK: Milestones

	public struct MilestoneRow: Hashable, Sendable, Identifiable {
		public let id: Int
		public let kind: API.OverviewMilestoneKind
		public let dateText: String
		/// "#4" for a Game milestone, "USCF" for an official achievement.
		public let badge: String
		public let description: String
		public let gameId: API.GameId?
		public var isUSCF: Bool { kind == .uscf }

		init(index: Int, _ m: API.OverviewMilestone) {
			id = index
			kind = m.kind
			dateText = m.date ?? "Undated"
			badge = m.kind == .uscf ? "USCF" : m.gameNum.map { "#\($0)" } ?? ""
			description = m.description
			gameId = m.gameId
		}
	}

	// MARK: USCF card

	public enum USCFCard: Hashable, Sendable {
		/// No USCF member ID configured: the web renders no card.
		case hidden
		/// USCF never reached and nothing cached.
		case unavailable(reason: String)
		case profile(USCFProfile)
	}

	public struct USCFTile: Hashable, Sendable {
		public let label: String
		public let value: String
		public let note: String
	}

	public struct USCFProfile: Hashable, Sendable {
		public let name: String
		public let memberId: String
		public let membership: String
		/// "Showing the last successful Sync's data" when USCF is unreachable.
		public let staleNotice: String?
		/// Lapsed or expiring membership.
		public let alert: String?
		/// The Regular (R) Official Rating, beside the Live Rating.
		public let official: String
		/// nil when there is no Live series: the Regular tile shows alone.
		public let live: String?
		public let regularNote: String
		/// Quick and Online Regular.
		public let others: [USCFTile]
		public let ranks: [USCFTile]
	}

	static func uscfCard(_ card: API.OverviewUscfCard) -> USCFCard {
		switch card.state {
		case .disabled: return .hidden
		case .unavailable: return .unavailable(reason: card.unavailableReason)
		case .ok:
			guard let p = card.profile else { return .unavailable(reason: card.unavailableReason) }
			var membership = p.membershipStatus
			if let expires = p.membershipExpires { membership += ", until \(expires)" }
			return .profile(USCFProfile(
				name: p.name,
				memberId: "#\(p.memberId)",
				membership: membership,
				staleNotice: card.unavailableSince.map { "\($0). Showing the last successful Sync's data." },
				alert: p.membershipAlert,
				official: RatingFormat.whole(p.regular?.rating ?? p.officialRating),
				live: p.liveRating.map { RatingFormat.whole($0) },
				regularNote: ratingNote(p.regular),
				others: [
					USCFTile(label: "Quick", value: RatingFormat.whole(p.quick?.rating), note: ratingNote(p.quick)),
					USCFTile(
						label: "Online Regular", value: RatingFormat.whole(p.onlineRegular?.rating),
						note: ratingNote(p.onlineRegular)),
				],
				ranks: [
					USCFTile(label: "National rank", value: rank(p.nationalRank), note: ""),
					USCFTile(label: p.state.isEmpty ? "State rank" : "\(p.state) rank", value: rank(p.stateRank), note: ""),
				]))
		}
	}

	/// The provisional or floor note under a rating, like the web.
	static func ratingNote(_ entry: API.OverviewUscfRating?) -> String {
		guard let entry, entry.rating != nil else { return "Unrated" }
		if entry.isProvisional {
			return entry.gamesPlayed.map { "Provisional, \($0) Games" } ?? "Provisional"
		}
		return entry.floor.map { "Established, floor \($0)" } ?? "Established"
	}

	static func rank(_ rank: Int?) -> String {
		rank.map { "#" + $0.formatted(.number.grouping(.automatic).locale(locale)) } ?? "None"
	}
}
