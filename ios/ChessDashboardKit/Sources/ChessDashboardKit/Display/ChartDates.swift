import Foundation

/// Contract dates turned into chart x values. A `YYYY-MM-DD` day becomes
/// noon of that day in the chart's calendar, so Swift Charts (which labels
/// axes in the device's time zone) never shows a Game on the day before.
public enum ChartDates {
	public static func day(_ text: String?, calendar: Calendar = .current) -> Date? {
		guard let text else { return nil }
		let parts = text.split(separator: "-").compactMap { Int($0) }
		guard parts.count == 3 || parts.count == 2 else { return nil }
		let components = DateComponents(
			year: parts[0], month: parts[1], day: parts.count == 3 ? parts[2] : 15, hour: 12)
		return calendar.date(from: components)
	}

	/// The point nearest to `date` (ties go to the earlier point).
	public static func nearest<Point>(_ points: [Point], to date: Date, by key: (Point) -> Date) -> Point? {
		points.min { abs(key($0).timeIntervalSince(date)) < abs(key($1).timeIntervalSince(date)) }
	}
}
