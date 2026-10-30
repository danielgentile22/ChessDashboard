import Foundation

/// The contract's date strings, parsed. Timestamps are UTC ISO 8601 with a
/// `Z`, with or without fractional seconds (Python's `isoformat` adds
/// microseconds when there are any); dates are `YYYY-MM-DD`.
public enum ISODates {
	public static func timestamp(_ text: String?) -> Date? {
		guard let text else { return nil }
		if let date = try? Date(text, strategy: .iso8601) { return date }
		return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
	}

	public static func day(_ text: String?) -> Date? {
		guard let text else { return nil }
		return try? Date(text, strategy: Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
	}

	/// `YYYY-MM-DD` for a calendar day in the given calendar's time zone.
	public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
		let c = calendar.dateComponents([.year, .month, .day], from: date)
		return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
	}
}
