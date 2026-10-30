/// A Game's USCF match status, as the web Games table shows it: matched by
/// member ID, matched by name (worth an eyeball), the sources disagree (see
/// Reconciliation on the web), a Forfeit, or no USCF Game Record (blank).
public struct UscfStatusDisplay: Hashable, Sendable {
	public enum Tone: Sendable { case good, caution, warning, neutral }

	/// Short text for a badge; empty when unmatched (the web shows nothing).
	public let label: String
	/// SF Symbol for the badge, nil when unmatched.
	public let symbol: String?
	public let tone: Tone
	public let accessibilityLabel: String

	public init(_ status: API.UscfMatchStatus) {
		switch status {
		case .matchedById:
			(label, symbol, tone) = ("Matched", "checkmark.seal", .good)
			accessibilityLabel = "USCF Game Record matched by member ID"
		case .matchedByName:
			(label, symbol, tone) = ("Matched by name", "questionmark.circle", .caution)
			accessibilityLabel = "USCF Game Record matched by name"
		case .conflict:
			(label, symbol, tone) = ("Sources disagree", "exclamationmark.triangle", .warning)
			accessibilityLabel = "USCF and Lichess disagree. See Reconciliation on the web"
		case .forfeit:
			(label, symbol, tone) = ("Forfeit", "flag", .neutral)
			accessibilityLabel = "Forfeit"
		case .unmatched:
			(label, symbol, tone) = ("", nil, .neutral)
			accessibilityLabel = "No USCF Game Record"
		}
	}
}
