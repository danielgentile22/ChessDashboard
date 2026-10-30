import Charts
import ChessDashboardKit
import SwiftUI

/// "How am I doing?": the KPIs, the USCF profile card, the top recurring
/// weakness, last-20 form, Win / Draw / Loss, how Games ended, milestones.
struct OverviewScreen: View {
	@Environment(AppEnvironment.self) private var env
	@State private var model: OverviewModel

	init(context: ScreenContext) { _model = State(initialValue: OverviewModel(context: context)) }

	var body: some View {
		ScreenState(resource: model.resource, retry: model.load) { payload in
			ScrollView {
				LazyVStack(spacing: 14) {
					if model.isEmpty {
						NoGamesView()
					} else {
						KPIGrid(kpis: model.kpis)
					}
					USCFCardView(card: model.uscfCard)
					if !model.isEmpty {
						if let weakness = payload.topWeakness { WeaknessCallout(weakness: weakness) }
						FormCard(form: model.form)
						OutcomeDonut(slices: model.outcomeSlices)
						TerminationChart(terminations: payload.terminations)
						MilestoneCard(rows: model.milestones)
					}
				}
				.padding()
			}
			.background(Theme.bg.color)
		}
		.screenChrome(title: "Overview", page: .overview, resource: model.resource)
		.task(id: env.filters.state) { await model.load() }
		.refreshable { await model.load() }
	}
}

// MARK: KPIs

private struct KPIGrid: View {
	let kpis: [OverviewModel.KPI]

	var body: some View {
		LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
			ForEach(kpis) { kpi in
				VStack(alignment: .leading, spacing: 4) {
					Text(kpi.title)
						.font(.caption)
						.foregroundStyle(Theme.muted.color)
					Text(kpi.value)
						.font(kpi.isText ? .headline : .title2.weight(.semibold).monospacedDigit())
						.foregroundStyle(color(kpi.tone))
						.lineLimit(kpi.isText ? nil : 1)
						.minimumScaleFactor(kpi.isText ? 1 : 0.6)
				}
				.frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
				.padding(12)
				.background(Theme.card.color, in: RoundedRectangle(cornerRadius: 10))
				.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border.color, lineWidth: 1))
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(kpi.accessibilityLabel)
			}
		}
	}

	private func color(_ tone: OverviewModel.KPI.Tone) -> Color {
		switch tone {
		case .neutral: Theme.text.color
		case .win: Theme.win.color
		case .loss: Theme.loss.color
		}
	}
}

// MARK: USCF card

private struct USCFCardView: View {
	let card: OverviewModel.USCFCard

	var body: some View {
		switch card {
		case .hidden:
			EmptyView()
		case .unavailable(let reason):
			DashboardCard(title: "US Chess Federation") {
				Label(
					reason.isEmpty ? "USCF data unavailable" : "USCF data unavailable: \(reason)",
					systemImage: "exclamationmark.triangle")
					.font(.subheadline)
					.foregroundStyle(Theme.warning.color)
			}
		case .profile(let p):
			DashboardCard(title: "US Chess Federation") {
				VStack(alignment: .leading, spacing: 12) {
					ViewThatFits(in: .horizontal) {
						HStack(alignment: .firstTextBaseline) { identity(p); Spacer(); membership(p) }
						VStack(alignment: .leading, spacing: 4) { identity(p); membership(p) }
					}
					if let stale = p.staleNotice { notice(stale, symbol: "clock.arrow.circlepath") }
					if let alert = p.alert { notice(alert, symbol: "exclamationmark.triangle") }
					regular(p)
					Divider().overlay(Theme.border.color)
					LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .topLeading)], alignment: .leading, spacing: 12) {
						ForEach(p.others + p.ranks, id: \.label) { tile($0) }
					}
				}
			}
		}
	}

	private func identity(_ p: OverviewModel.USCFProfile) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Text(p.name).font(.title3.weight(.semibold)).foregroundStyle(Theme.text.color)
			Text(p.memberId).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted.color)
		}
	}

	private func membership(_ p: OverviewModel.USCFProfile) -> some View {
		Text(p.membership).font(.caption).foregroundStyle(Theme.muted.color)
	}

	private func notice(_ text: String, symbol: String) -> some View {
		Label(text, systemImage: symbol)
			.font(.footnote)
			.foregroundStyle(Theme.warning.color)
			.padding(8)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Theme.warningWash.color, in: RoundedRectangle(cornerRadius: 8))
	}

	/// The Official and Live Ratings side by side: the gap between them at a glance.
	private func regular(_ p: OverviewModel.USCFProfile) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Regular").font(.caption).foregroundStyle(Theme.muted.color)
			HStack(alignment: .firstTextBaseline, spacing: 28) {
				ratingValue(p.live == nil ? "Rating" : "Official", p.official, color: Theme.text.color)
				if let live = p.live {
					ratingValue("Live", live, color: Theme.primary.color)
				}
			}
			Text(p.regularNote).font(.caption).foregroundStyle(Theme.dim.color)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(
			"Regular. Official Rating \(p.official)" + (p.live.map { ", Live Rating \($0)" } ?? "") + ". \(p.regularNote)")
	}

	private func ratingValue(_ label: String, _ value: String, color: Color) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted.color)
			Text(value).font(.largeTitle.weight(.semibold).monospacedDigit()).foregroundStyle(color)
		}
	}

	private func tile(_ t: OverviewModel.USCFTile) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(t.label).font(.caption).foregroundStyle(Theme.muted.color)
			Text(t.value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text.color)
			if !t.note.isEmpty {
				Text(t.note).font(.caption2).foregroundStyle(Theme.dim.color)
			}
		}
		.accessibilityElement(children: .combine)
	}
}

// MARK: Weakness

private struct WeaknessCallout: View {
	let weakness: API.OverviewWeakness

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning.color)
				Text(weakness.stat).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text.color)
			}
			HStack {
				TagChip(weakness.tag)
				if !weakness.window.isEmpty {
					Text(weakness.window).font(.caption).foregroundStyle(Theme.muted.color)
				}
			}
			Text("Review these Lessons on the Lessons tab.")
				.font(.caption)
				.foregroundStyle(Theme.muted.color)
		}
		.padding()
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Theme.warningWash.color, in: RoundedRectangle(cornerRadius: 12))
		.overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.warningLine.color, lineWidth: 1))
		.accessibilityElement(children: .combine)
	}
}

// MARK: Form

private struct FormCard: View {
	let form: OverviewModel.FormSummary

	var body: some View {
		DashboardCard(title: "Last 20 Games", subtitle: "Oldest to newest") {
			if let indicator = form.indicator {
				HStack(spacing: 4) {
					Text(indicator.symbol).font(indicator.blazing ? .title : .title2)
					Text("\(indicator.count)").font(.title3.weight(.bold).monospacedDigit())
						.foregroundStyle(Theme.text.color)
				}
				.shadow(color: indicator.blazing ? Theme.fireGlow.color : .clear, radius: 8)
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(indicator.accessibilityLabel)
			}
			LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 30), spacing: 5)], alignment: .leading, spacing: 5) {
				ForEach(Array(form.badges.enumerated()), id: \.offset) { _, badge in
					Text(badge.letter)
						.font(.caption.weight(.bold))
						.frame(width: 26, height: 26)
						.foregroundStyle(Theme.bg.color)
						.background(badge.outcome.themeColor, in: RoundedRectangle(cornerRadius: 6))
				}
			}
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("Last \(form.badges.count) Games: " + form.badges.map(\.outcome.rawValue).joined(separator: ", "))
			HStack(alignment: .top) {
				ForEach(form.stats, id: \.label) { stat in
					VStack(alignment: .leading, spacing: 2) {
						Text(stat.label).font(.caption).foregroundStyle(Theme.muted.color)
						Text(stat.value).font(.title3.weight(.semibold).monospacedDigit())
							.foregroundStyle(stat.outcome?.themeColor ?? Theme.text.color)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.accessibilityElement(children: .combine)
				}
			}
		}
	}
}

// MARK: Win / Draw / Loss

private struct OutcomeDonut: View {
	let slices: [OverviewModel.OutcomeSlice]
	@State private var selectedValue: Int?

	private var selected: OverviewModel.OutcomeSlice? {
		guard let selectedValue else { return nil }
		var running = 0
		for slice in slices {
			running += slice.games
			if selectedValue < running { return slice }
		}
		return slices.last
	}

	var body: some View {
		DashboardCard(title: "Win / Draw / Loss") {
			if slices.isEmpty {
				CardEmptyText("No data")
			} else {
				let total = slices.reduce(0) { $0 + $1.games }
				Chart(slices) { slice in
					SectorMark(
						angle: .value("Games", slice.games), innerRadius: .ratio(0.62), angularInset: 1.5)
						.foregroundStyle(slice.outcome.themeColor)
						.opacity(selected == nil || selected == slice ? 1 : 0.4)
						.accessibilityLabel(slice.label)
						.accessibilityValue("\(slice.games) Games, \(slice.percentText)")
				}
				.chartAngleSelection(value: $selectedValue)
				.chartBackground { proxy in
					GeometryReader { geo in
						if let frame = proxy.plotFrame {
							let rect = geo[frame]
							VStack(spacing: 0) {
								Text("\(selected?.games ?? total)")
									.font(.title.weight(.semibold).monospacedDigit())
									.foregroundStyle(Theme.text.color)
								Text(selected.map { "\($0.label.lowercased()), \($0.percentText)" } ?? "Games")
									.font(.caption)
									.foregroundStyle(Theme.muted.color)
							}
							.position(x: rect.midX, y: rect.midY)
						}
					}
				}
				.frame(height: 200)
				HStack(spacing: 16) {
					ForEach(slices) { slice in
						HStack(spacing: 4) {
							Circle().fill(slice.outcome.themeColor).frame(width: 8, height: 8)
							Text("\(slice.label) \(slice.games)").font(.caption).foregroundStyle(Theme.muted.color)
						}
					}
				}
				.accessibilityHidden(true)
			}
		}
	}
}

// MARK: Terminations

private struct TerminationChart: View {
	let terminations: [API.OverviewTermination]

	var body: some View {
		DashboardCard(title: "How Games ended") {
			if terminations.isEmpty {
				CardEmptyText("No data")
			} else {
				Chart(terminations, id: \.termination) { t in
					BarMark(x: .value("Games", t.games), y: .value("Termination", t.termination))
						.foregroundStyle(Theme.primary.color)
						.annotation(position: .trailing) {
							Text("\(t.games)").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted.color)
						}
						.accessibilityLabel(t.termination)
						.accessibilityValue("\(t.games) Games")
				}
				.chartXAxis(.hidden)
				.chartYAxis {
					AxisMarks { _ in
						AxisValueLabel().font(.caption).foregroundStyle(Theme.muted.color)
					}
				}
				.frame(height: CGFloat(terminations.count) * 34 + 10)
			}
		}
	}
}

// MARK: Milestones

private struct MilestoneCard: View {
	let rows: [OverviewModel.MilestoneRow]

	var body: some View {
		DashboardCard(title: "Milestones") {
			if rows.isEmpty {
				CardEmptyText("No milestone data")
			} else {
				VStack(alignment: .leading, spacing: 0) {
					ForEach(rows) { row in
						HStack(alignment: .firstTextBaseline, spacing: 10) {
							Circle()
								.fill(dotColor(row.kind))
								.frame(width: 8, height: 8)
							VStack(alignment: .leading, spacing: 2) {
								HStack(spacing: 6) {
									Text(row.dateText).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted.color)
									Text(row.badge)
										.font(.caption2.weight(.bold))
										.foregroundStyle(row.isUSCF ? Theme.warning.color : Theme.dim.color)
								}
								Text(row.description)
									.font(.subheadline)
									.foregroundStyle(row.isUSCF ? Theme.warning.color : Theme.text.color)
							}
						}
						.padding(.vertical, 6)
						.accessibilityElement(children: .combine)
					}
				}
			}
		}
	}

	private func dotColor(_ kind: API.OverviewMilestoneKind) -> Color {
		switch kind {
		case .win, .streak: Theme.win.color
		case .loss: Theme.loss.color
		case .draw: Theme.draw.color
		case .peak: Theme.primary.color
		case .uscf: Theme.warning.color
		case .first, .milestone: Theme.accent.color
		}
	}
}
