import Foundation

/// The Events and Rated Event wording, matching pages/events.py.
public enum EventText {
	/// Tournament points: "1.5", "3".
	public static func points(_ score: Double) -> String {
		score.rounded() == score ? String(Int(score)) : String(score)
	}

	/// "1544 → 1571 (+27)", "unrated → 695", or "" when the post-rating is unknown.
	public static func ratingChange(pre: Int?, post: Int?, change: Int?) -> String {
		guard let post else { return "" }
		guard let pre, let change else { return "unrated → \(post)" }
		return "\(pre) → \(post) (\(change >= 0 ? "+" : "")\(change))"
	}

	/// "Score 3.5 · 4 games + 1 forfeit win": the Forfeit rule made visible.
	public static func scoreLine(score: Double, games: Int, forfeits: Int) -> String {
		var line = "Score \(points(score)) · \(games) game\(games == 1 ? "" : "s")"
		if forfeits > 0 { line += " + \(forfeits) forfeit win\(forfeits == 1 ? "" : "s")" }
		return line
	}

	/// "3 games · 1 forfeit · 1W 1D 1L · 1.5 pts · best streak 3W".
	public static func seriesStats(_ series: API.EventsSeries) -> String {
		var bits = ["\(series.gameCount) game\(series.gameCount == 1 ? "" : "s")", "\(series.win)W \(series.draw)D \(series.loss)L",
					"\(points(series.score)) pts"]
		if series.forfeitCount > 0 {
			bits.insert("\(series.forfeitCount) forfeit\(series.forfeitCount == 1 ? "" : "s")", at: 1)
		}
		if series.longestWinStreak >= 2 { bits.append("best streak \(series.longestWinStreak)W") }
		return bits.joined(separator: " · ")
	}

	/// "1st", "22nd", "13th".
	public static func ordinal(_ n: Int) -> String {
		let suffix = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
		return "\(n)\(suffix)"
	}

	/// "Finished 5th of 116", "40 players", or nil with no crosstable.
	public static func placement(placement: Int?, playerCount: Int?) -> String? {
		guard let playerCount else { return nil }
		guard let placement else { return "\(playerCount) players" }
		return "Finished \(ordinal(placement)) of \(playerCount)"
	}

	/// "2026-05-01 to 2026-05-29", one date for a single-day event, "" undated.
	public static func dates(start: String?, end: String?) -> String {
		guard let start else { return "" }
		guard let end, end != start else { return start }
		return "\(start) to \(end)"
	}

	/// "R3", or "R?" when the round is unknown.
	public static func round(_ round: Int?) -> String {
		round.map { "R\($0)" } ?? "R?"
	}
}

/// A crosstable round cell: the web's letter.
public enum CrosstableRoundDisplay {
	public static func letter(_ outcome: String) -> String {
		switch outcome {
		case "Win", "WinForfeit": "W"
		case "Loss": "L"
		case "Draw": "D"
		case "Forfeit": "F"
		case "ByeFull": "B"
		case "ByeHalf": "b"
		default: "·"
		}
	}

	/// "Round 3: Win vs Jane Doe".
	public static func accessibilityLabel(_ round: API.EventCrosstableRound) -> String {
		var label = "Round \(round.roundNumber): \(round.outcome)"
		if !round.opponentName.isEmpty { label += " vs \(round.opponentName)" }
		return label
	}
}
