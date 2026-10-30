import Foundation

/// The Events and Rated Event wording, matching pages/events.py.
public enum EventText {
	/// Tournament points: "1.5", "3".
	public static func points(_ score: Double) -> String {
		score.rounded() == score ? String(Int(score)) : String(score)
	}

	/// "1544 → 1571 (+27)", "1544 → 1571" with no change given, "unrated →
	/// 695", or "" when the post-rating is unknown.
	public static func ratingChange(pre: Int?, post: Int?, change: Int?) -> String {
		guard let post else { return "" }
		let to = RatingFormat.whole(post)
		guard let pre else { return "unrated → \(to)" }
		let line = "\(RatingFormat.whole(pre)) → \(to)"
		guard let change else { return line }
		return line + " (\(change >= 0 ? "+" : "")\(change))"
	}

	/// "Score 3.5 · 4 Games + 1 forfeit win": the Forfeit rule made visible.
	public static func scoreLine(score: Double, games: Int, forfeits: Int) -> String {
		var line = "Score \(points(score)) · \(RecordText.games(games))"
		if forfeits > 0 { line += " + \(RecordText.count(forfeits, "forfeit win", "forfeit wins"))" }
		return line
	}

	/// "3 Games · 1 forfeit · 1 win, 1 draw, 1 loss · 1.5 points · best win streak 3".
	public static func seriesStats(_ series: API.EventsSeries) -> String {
		var bits = [RecordText.games(series.gameCount),
					RecordText.record(win: series.win, draw: series.draw, loss: series.loss),
					"\(points(series.score)) point\(series.score == 1 ? "" : "s")"]
		if series.forfeitCount > 0 {
			bits.insert(RecordText.count(series.forfeitCount, "forfeit", "forfeits"), at: 1)
		}
		if series.longestWinStreak >= 2 { bits.append("best win streak \(series.longestWinStreak)") }
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
