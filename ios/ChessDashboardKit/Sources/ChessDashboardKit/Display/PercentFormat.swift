import Foundation

/// Percentages as the screens show them. The server sends percents as
/// 0...100 doubles; charts and rows read them rounded.
public enum PercentFormat {
	/// "57%".
	public static func whole(_ percent: Double) -> String {
		"\(rounded(percent))%"
	}

	/// "57.1%", "50%": one decimal at most, no trailing ".0".
	public static func upToOneDecimal(_ percent: Double) -> String {
		percent.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US"))) + "%"
	}

	/// "57 percent", for VoiceOver.
	public static func spoken(_ percent: Double) -> String {
		"\(rounded(percent)) percent"
	}

	/// `count` as a whole percent of `total`: "43%"; "0%" when `total` is 0.
	public static func share(_ count: Int, of total: Int) -> String {
		whole(total > 0 ? Double(count) / Double(total) * 100 : 0)
	}

	private static func rounded(_ percent: Double) -> Int {
		Int(percent.rounded(.toNearestOrAwayFromZero))
	}
}
