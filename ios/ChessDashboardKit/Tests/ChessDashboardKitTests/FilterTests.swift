import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Filter state")
struct FilterStateTests {
	private func query(_ state: FilterState) -> [String] {
		state.queryItems.map { "\($0.name)=\($0.value ?? "")" }
	}

	@Test("no filters encodes only the lens")
	func allIsJustTheLens() {
		#expect(query(.all) == ["lens=official"])
	}

	@Test("every field encodes as the API's query parameter, in a fixed order")
	func fullEncoding() {
		var s = FilterState()
		s.colors = [.white]
		s.outcomes = [.loss, .win]
		s.terminations = ["win by resignation", "Normal"]
		s.start = "2024-01-06"
		s.end = "2024-06-16"
		s.series = ["Test Open", "Summer Cup"]
		s.minMoves = 20
		s.maxMoves = 60
		s.lens = .live
		#expect(query(s) == [
			"colors=White", "outcomes=Win", "outcomes=Loss",
			"terminations=Normal", "terminations=win by resignation",
			"start=2024-01-06", "end=2024-06-16",
			"series=Summer Cup", "series=Test Open",
			"min_moves=20", "max_moves=60", "lens=live",
		])
	}

	@Test("toggling keeps the canonical form and never empties a selection")
	func toggling() {
		var s = FilterState()
		s.toggle(API.Color.black)
		#expect(s.colors == [.white])
		s.toggle(API.Color.white)  // the last one stays on
		#expect(s.colors == [.white])
		s.toggle(API.Color.black)  // both on again is "no restriction"
		#expect(s.colors.isEmpty)
		#expect(!s.isFiltered)
		s.toggle(API.Outcome.draw)
		#expect(s.outcomes == [.win, .loss])
		#expect(s.isOn(API.Outcome.win) && !s.isOn(API.Outcome.draw))
	}

	@Test("the lens is not a filter")
	func lensIsNotAFilter() {
		var s = FilterState()
		s.lens = .live
		#expect(!s.isFiltered)
		s.reset()
		#expect(s.lens == .live)
	}

	@Test("presets from meta apply and are recognized; archive move bounds are dropped")
	func presets() throws {
		let meta = try JSONDecoder().decode(API.MetaPayload.self, from: Repo.fixture("getMeta"))
		let options = meta.filterOptions
		let all = try #require(meta.presets.first { $0.id == .all })
		let white = try #require(meta.presets.first { $0.id == .white })
		let wins = try #require(meta.presets.first { $0.id == .wins })

		#expect(FilterState(preset: all.filters, options: options, lens: .official) == .all)
		let w = FilterState(preset: white.filters, options: options, lens: .live)
		#expect(w.colors == [.white] && w.minMoves == nil && w.maxMoves == nil && w.lens == .live)
		#expect(w.matches(white, options: options))
		#expect(!w.matches(wins, options: options))
	}

	@Test("the summary names what is kept")
	func summary() {
		#expect(FilterState.all.summary == "All Games")
		var s = FilterState()
		s.colors = [.white]
		s.outcomes = [.win]
		s.start = "2024-01-06"
		s.series = ["Summer Cup"]
		s.minMoves = 20
		#expect(s.summary == "White · Wins · From 2024-01-06 · Summer Cup · 20+ moves")
	}

	@Test("equal selections give equal route keys")
	func routeKeysAreCanonical() {
		var a = FilterState()
		a.series = ["B", "A"]
		var b = FilterState()
		b.series = ["A", "B"]
		#expect(Endpoints.getGames(filters: a).request.routeKey == Endpoints.getGames(filters: b).request.routeKey)
	}
}

@Suite("Filter store")
@MainActor
struct FilterStoreTests {
	@Test("the filter state persists across launches")
	func persists() {
		let defaults = InMemoryKeyValueStore()
		let first = FilterStore(defaults: defaults)
		first.state.toggle(API.Color.black)
		first.state.lens = .live
		let relaunched = FilterStore(defaults: defaults)
		#expect(relaunched.state.colors == [.white])
		#expect(relaunched.state.lens == .live)
	}

	@Test("an unreadable stored value falls back to all")
	func corruptFallsBack() {
		let defaults = InMemoryKeyValueStore()
		defaults.set(Data("nope".utf8), forKey: FilterStore.key)
		#expect(FilterStore(defaults: defaults).state == .all)
	}
}
