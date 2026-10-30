import Foundation

/// Ratings display as whole numbers everywhere (the owner's rule, same as the
/// web). The API already sends integers; the `Double` overloads exist for any
/// value a screen derives itself.
public enum RatingFormat {
	/// "1523", or "Unrated" when unknown.
	public static func whole(_ rating: Int?) -> String {
		rating.map(String.init) ?? "Unrated"
	}

	public static func whole(_ rating: Double?) -> String {
		whole(rating.map(rounded))
	}

	/// A rating change with its sign: "+12", "-8", "0".
	public static func change(_ delta: Int?) -> String {
		guard let delta else { return "" }
		return delta > 0 ? "+\(delta)" : String(delta)
	}

	public static func change(_ delta: Double?) -> String {
		change(delta.map(rounded))
	}

	private static func rounded(_ value: Double) -> Int {
		Int(value.rounded(.toNearestOrAwayFromZero))
	}
}

/// How a Tag chip reads: hand-written Tags (mine) and engine-emitted ones
/// must always look different (they come from different authors).
public struct TagDisplay: Hashable, Sendable {
	public enum Style: Sendable { case mine, engine }

	public let text: String
	public let style: Style
	/// SF Symbol shown before an engine Tag; mine has none.
	public let symbol: String?
	public let accessibilityLabel: String

	public init(_ tag: API.Tag) {
		text = "#" + tag.name
		switch tag.source {
		case .mine:
			style = .mine
			symbol = nil
			accessibilityLabel = "Tag \(tag.name)"
		case .engine:
			style = .engine
			symbol = "cpu"
			accessibilityLabel = "Engine Tag \(tag.name)"
		}
	}
}

/// The per-source freshness lines (meta's `freshness`), like the web header:
/// when Lichess and USCF were last synced, and the "USCF unavailable since"
/// warning when it applies.
public struct FreshnessSummary: Hashable, Sendable {
	public struct Line: Hashable, Sendable {
		public let source: String
		public let text: String
		/// Show as a warning (cached fallback, USCF unavailable).
		public let isWarning: Bool
	}

	public let lines: [Line]

	public init(_ freshness: API.MetaFreshness, now: Date = .now) {
		var lines: [Line] = []
		let lichess = freshness.lichess
		switch lichess.source {
		case .lichess:
			lines.append(Line(
				source: "Lichess", text: "Synced " + Self.ago(lichess.syncedAt, now: now),
				isWarning: false))
		case .cache:
			lines.append(Line(
				source: "Lichess",
				text: "Couldn't reach Lichess. Showing Games cached " + Self.ago(lichess.cachedAt, now: now),
				isWarning: true))
		}
		let uscf = freshness.uscf
		if uscf.enabled {
			if let since = uscf.unavailableSince {
				lines.append(Line(source: "USCF", text: "USCF unavailable since \(since)", isWarning: true))
			} else if uscf.available {
				lines.append(Line(
					source: "USCF", text: "Synced " + Self.ago(uscf.syncedAt, now: now), isWarning: false))
			} else {
				lines.append(Line(source: "USCF", text: "No USCF data yet", isWarning: true))
			}
		}
		self.lines = lines
	}

	/// "just now", "5 minutes ago", "never".
	static func ago(_ timestamp: String?, now: Date) -> String {
		guard let date = ISODates.timestamp(timestamp) else { return "never" }
		let seconds = now.timeIntervalSince(date)
		if seconds < 60 { return "just now" }
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter.localizedString(for: date, relativeTo: now)
	}
}
