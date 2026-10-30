import ChessDashboardKit
import SwiftUI

/// The one filter sheet, reachable from every screen's toolbar: the presets,
/// the lens, and every filter the web drawer has. Edits apply as they are
/// made; options and presets come from meta, so they follow each Sync.
struct FilterSheet: View {
	@Environment(AppEnvironment.self) private var env
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		@Bindable var filters = env.filters
		let options = env.meta.value?.filterOptions
		NavigationStack {
			Form {
				if let presets = env.meta.value?.presets, !presets.isEmpty {
					Section("Presets") {
						ForEach(presets, id: \.id) { preset in
							Button {
								env.filters.apply(preset, options: options)
							} label: {
								HStack {
									Text(preset.label).foregroundStyle(Theme.text.color)
									Spacer()
									if filters.state.matches(preset, options: options) {
										Image(systemName: "checkmark").foregroundStyle(Theme.primary.color)
									}
								}
							}
						}
					}
				}
				Section {
					Picker("Rating lens", selection: $filters.state.lens) {
						Text("Official").tag(API.Lens.official)
						Text("Live").tag(API.Lens.live)
					}
					.pickerStyle(.segmented)
				} header: {
					Text("Rating lens")
				} footer: {
					Text("Changes which rating every rating number uses. It never hides Games.")
				}
				Section("Color") {
					ForEach(API.Color.allCases, id: \.self) { color in
						Toggle(color.rawValue, isOn: Binding(
							get: { filters.state.isOn(color) },
							set: { _ in filters.state.toggle(color) }))
					}
				}
				Section("Outcome") {
					ForEach(API.Outcome.allCases, id: \.self) { outcome in
						Toggle(outcome.rawValue, isOn: Binding(
							get: { filters.state.isOn(outcome) },
							set: { _ in filters.state.toggle(outcome) }))
					}
				}
				Section("Dates") {
					DayBound(label: "From", day: $filters.state.start, options: options, fallback: options?.minDate)
					DayBound(label: "Until", day: $filters.state.end, options: options, fallback: options?.maxDate)
				}
				if let options {
					Section("Series and terminations") {
						NavigationLink {
							ChoiceList(title: "Series", choices: options.series, selected: $filters.state.series)
						} label: {
							LabeledContent("Series", value: countLabel(filters.state.series, all: "All Series"))
						}
						NavigationLink {
							ChoiceList(
								title: "Terminations", choices: options.terminations,
								selected: $filters.state.terminations)
						} label: {
							LabeledContent("Terminations", value: countLabel(filters.state.terminations, all: "All"))
						}
					}
					Section("Length in moves") {
						MoveBound(label: "At least", value: $filters.state.minMoves, range: options.minMoves...options.maxMoves, fallback: options.minMoves)
						MoveBound(label: "At most", value: $filters.state.maxMoves, range: options.minMoves...max(options.minMoves, options.maxMoves), fallback: options.maxMoves)
					}
				}
				Section {
					Button("Reset Filters", role: .destructive) { filters.state.reset() }
						.disabled(!filters.state.isFiltered)
				}
			}
			.navigationTitle("Filters")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
			}
		}
	}

	private func countLabel(_ set: Set<String>, all: String) -> String {
		switch set.count {
		case 0: all
		case 1: set.first!
		default: "\(set.count) selected"
		}
	}
}

/// An optional date bound: off means no bound.
private struct DayBound: View {
	let label: String
	@Binding var day: String?
	let options: API.MetaFilterOptions?
	let fallback: String?

	var body: some View {
		Toggle(label, isOn: Binding(
			get: { day != nil },
			set: { on in day = on ? (fallback ?? ISODates.dayString(.now)) : nil }))
		if let current = day, let date = ISODates.day(current) {
			DatePicker(
				label, selection: Binding(
					get: { date },
					set: { day = ISODates.dayString($0, calendar: Self.utc) }),
				displayedComponents: .date)
				.environment(\.timeZone, .gmt)
				.labelsHidden()
		}
	}

	private static let utc: Calendar = {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = .gmt
		return c
	}()
}

/// An optional move-count bound.
private struct MoveBound: View {
	let label: String
	@Binding var value: Int?
	let range: ClosedRange<Int>
	let fallback: Int

	var body: some View {
		Toggle(label, isOn: Binding(get: { value != nil }, set: { value = $0 ? fallback : nil }))
		if let current = value {
			Stepper("\(current) moves", value: Binding(get: { current }, set: { value = $0 }), in: range)
		}
	}
}

/// Pick any number of choices; none picked means all.
private struct ChoiceList: View {
	let title: String
	let choices: [String]
	@Binding var selected: Set<String>

	var body: some View {
		List {
			Section {
				Button("All") { selected = [] }
			}
			Section {
				ForEach(choices, id: \.self) { choice in
					Button {
						if selected.contains(choice) { selected.remove(choice) } else { selected.insert(choice) }
					} label: {
						HStack {
							Text(choice).foregroundStyle(Theme.text.color)
							Spacer()
							if selected.contains(choice) {
								Image(systemName: "checkmark").foregroundStyle(Theme.primary.color)
							}
						}
					}
				}
			} footer: {
				Text("None picked means all.")
			}
		}
		.navigationTitle(title)
	}
}
