import Foundation

/// A signed rating difference seen from the player's side: the rating gap to
/// an opponent, or how far an opponent's rating moved since you played them.
/// Positive means they are (or got) stronger: the harder Game.
public struct RatingDelta: Hashable, Sendable {
	public enum Tone: Sendable { case harder, easier, even }

	public let value: Int

	public init(_ value: Int) { self.value = value }

	/// Nil when the difference is unknown (an unrated side).
	public init?(ifKnown value: Int?) {
		guard let value else { return nil }
		self.value = value
	}

	/// "+115", "-5", "0".
	public var text: String { RatingFormat.change(value) }

	public var tone: Tone { value > 0 ? .harder : value < 0 ? .easier : .even }
}

/// An opponent's USCF rating when you last played them next to today's.
public struct ThenVsNow: Hashable, Sendable {
	public let then: Int
	public let now: Int
	public let change: RatingDelta

	public init(then: Int, now: Int, change: RatingDelta) {
		self.then = then
		self.now = now
		self.change = change
	}
}

/// Puts a rating series on a chart whose axis measures something else
/// (accuracy, mistake counts): ratings map linearly onto the plotted range,
/// and axis labels map back. Swift Charts has one y scale, so the overlay
/// shares it and labels its own trailing axis in rating points.
public struct RatingOverlay: Hashable, Sendable {
	public let low: Double
	public let high: Double
	public let range: ClosedRange<Double>

	/// Nil when there is no rating to draw. A single rating gets a band of
	/// 100 points around it so it sits mid-chart.
	public init?(ratings: [Int], onto range: ClosedRange<Double>) {
		guard let min = ratings.min(), let max = ratings.max() else { return nil }
		low = Double(min == max ? min - 50 : min)
		high = Double(min == max ? max + 50 : max)
		self.range = range
	}

	public func plotted(_ rating: Int) -> Double {
		range.lowerBound + (Double(rating) - low) / (high - low) * (range.upperBound - range.lowerBound)
	}

	public func rating(atPlotted value: Double) -> Int {
		let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
		return Int((low + fraction * (high - low)).rounded(.toNearestOrAwayFromZero))
	}
}
