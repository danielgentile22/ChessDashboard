import Foundation

/// The app-wide filter selection plus the Official/Live lens: the phone's
/// version of the web filter drawer and lens toggle (`FILTER_INPUTS`).
///
/// Canonical form: an empty set or a nil bound means "no restriction", and a
/// selection that covers every choice is stored as empty. Two states that
/// select the same Games are therefore equal, which is what makes them safe
/// cache keys. The mutating helpers keep that form; set fields directly only
/// through them.
public struct FilterState: Codable, Sendable, Hashable {
	/// Empty means both colors.
	public var colors: Set<API.Color> = []
	/// Empty means all three outcomes.
	public var outcomes: Set<API.Outcome> = []
	/// Empty means every termination.
	public var terminations: Set<String> = []
	/// First day kept, `YYYY-MM-DD`. Any date bound drops undated Games, as on the web.
	public var start: String?
	/// Last day kept, `YYYY-MM-DD`.
	public var end: String?
	/// Empty means every Series.
	public var series: Set<String> = []
	public var minMoves: Int?
	public var maxMoves: Int?
	/// A lens, not a filter: it changes which rating series every
	/// rating-derived number uses, and never hides Games.
	public var lens: API.Lens = .official

	public init() {}

	/// No filters, Official lens.
	public static let all = FilterState()

	/// True when any filter (not the lens) restricts the Games.
	public var isFiltered: Bool {
		var bare = self
		bare.lens = .official
		return bare != .all
	}

	// MARK: The one encoder

	/// The query parameters every filtered route takes, in a fixed order.
	/// This is the only place a filter state becomes a request, mirroring
	/// `filters.get_filtered()` being the only place the server applies one.
	public var queryItems: [URLQueryItem] {
		var items: [URLQueryItem] = []
		func add(_ name: String, _ values: [String]) {
			items += values.map { URLQueryItem(name: name, value: $0) }
		}
		add("colors", API.Color.allCases.filter(colors.contains).map(\.rawValue))
		add("outcomes", API.Outcome.allCases.filter(outcomes.contains).map(\.rawValue))
		add("terminations", terminations.sorted())
		add("start", start.map { [$0] } ?? [])
		add("end", end.map { [$0] } ?? [])
		add("series", series.sorted())
		add("min_moves", minMoves.map { [String($0)] } ?? [])
		add("max_moves", maxMoves.map { [String($0)] } ?? [])
		add("lens", [lens.rawValue])
		return items
	}

	// MARK: Presets

	/// A server preset (from meta) as a filter state, keeping `lens`. Move
	/// bounds equal to the archive's bounds are dropped, so a later Sync that
	/// adds a longer Game doesn't leave it filtered out.
	public init(preset: API.MetaFilterState, options: API.MetaFilterOptions?, lens: API.Lens) {
		colors = Self.canonical(Set(preset.colors))
		outcomes = Self.canonical(Set(preset.outcomes))
		terminations = Set(preset.terminations)
		start = preset.start
		end = preset.end
		series = Set(preset.series)
		minMoves = preset.minMoves == options?.minMoves ? nil : preset.minMoves
		maxMoves = preset.maxMoves == options?.maxMoves ? nil : preset.maxMoves
		self.lens = lens
	}

	/// Whether this state is exactly that preset (the sheet marks it).
	public func matches(_ preset: API.MetaPreset, options: API.MetaFilterOptions?) -> Bool {
		self == FilterState(preset: preset.filters, options: options, lens: lens)
	}

	// MARK: Editing

	public func isOn(_ color: API.Color) -> Bool { colors.isEmpty || colors.contains(color) }
	public func isOn(_ outcome: API.Outcome) -> Bool { outcomes.isEmpty || outcomes.contains(outcome) }

	/// Flip one color. Turning off the last one is ignored: "no colors" can't
	/// be asked for (the API reads an empty list as "both").
	public mutating func toggle(_ color: API.Color) {
		colors = Self.toggled(color, in: colors)
	}

	public mutating func toggle(_ outcome: API.Outcome) {
		outcomes = Self.toggled(outcome, in: outcomes)
	}

	/// Clear every filter, keep the lens.
	public mutating func reset() {
		let lens = lens
		self = .all
		self.lens = lens
	}

	private static func toggled<T: CaseIterable & Hashable>(_ value: T, in set: Set<T>) -> Set<T> {
		var on = set.isEmpty ? Set(T.allCases) : set
		if on.contains(value) {
			guard on.count > 1 else { return set }
			on.remove(value)
		} else {
			on.insert(value)
		}
		return canonical(on)
	}

	private static func canonical<T: CaseIterable & Hashable>(_ set: Set<T>) -> Set<T> {
		set.count == T.allCases.count ? [] : set
	}
}

// MARK: Summary

extension FilterState {
	/// A compact line naming what the filters keep, for the top of each
	/// screen: "All Games", or e.g. "White · Wins · From 2024-01-06 · Summer Cup".
	public var summary: String {
		var parts: [String] = []
		if !colors.isEmpty {
			parts.append(API.Color.allCases.filter(colors.contains).map(\.rawValue).joined(separator: ", "))
		}
		if !outcomes.isEmpty {
			let names: [API.Outcome: String] = [.win: "Wins", .draw: "Draws", .loss: "Losses"]
			parts.append(API.Outcome.allCases.filter(outcomes.contains).compactMap { names[$0] }
				.joined(separator: ", "))
		}
		switch (start, end) {
		case let (s?, e?): parts.append("\(s) to \(e)")
		case let (s?, nil): parts.append("From \(s)")
		case let (nil, e?): parts.append("Until \(e)")
		case (nil, nil): break
		}
		if !series.isEmpty {
			parts.append(series.count == 1 ? series.first! : "\(series.count) Series")
		}
		if !terminations.isEmpty {
			parts.append(terminations.count == 1 ? terminations.first! : "\(terminations.count) terminations")
		}
		switch (minMoves, maxMoves) {
		case let (lo?, hi?): parts.append("\(lo) to \(hi) moves")
		case let (lo?, nil): parts.append("\(lo)+ moves")
		case let (nil, hi?): parts.append("Up to \(hi) moves")
		case (nil, nil): break
		}
		return parts.isEmpty ? "All Games" : parts.joined(separator: " · ")
	}
}
