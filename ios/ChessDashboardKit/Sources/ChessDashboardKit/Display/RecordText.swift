import Foundation

/// A win/draw/loss record in words: "3 wins, 1 draw, 2 losses".
public enum RecordText {
	public static func record(win: Int, draw: Int, loss: Int) -> String {
		[count(win, "win", "wins"), count(draw, "draw", "draws"), count(loss, "loss", "losses")]
			.joined(separator: ", ")
	}

	/// "3 wins, 1 draw, 2 losses, 6 Games".
	public static func recordWithGames(win: Int, draw: Int, loss: Int) -> String {
		record(win: win, draw: draw, loss: loss) + ", " + games(win + draw + loss)
	}

	/// "1 Game", "6 Games" (the glossary word).
	public static func games(_ n: Int) -> String { count(n, "Game", "Games") }

	static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
}
