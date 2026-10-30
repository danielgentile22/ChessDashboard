import ChessDashboardKit
import SwiftUI

extension View {
	/// The chrome every screen has: its title, the Official/Live lens toggle
	/// and the filter sheet in the toolbar, "Open on the web", the active
	/// filter summary, the offline indicator for `resource`, per-source
	/// freshness (a menu item, plus a warning bar when a source is stale or
	/// unavailable), and Sync (the
	/// owner's toolbar action; `resource` re-fetches after each Sync). A
	/// screen whose route takes no filters (Analysis, like its web page)
	/// passes `filtered: false` and gets no filter or lens controls.
	func screenChrome<Value: Decodable & Sendable>(
		title: String, page: WebPage, resource: ScreenResource<Value>, filtered: Bool = true
	) -> some View {
		modifier(ScreenChrome(
			title: title, page: page, isOffline: resource.isOffline, cachedAt: resource.cachedAt,
			filtered: filtered, reload: { await resource.reload(in: $0) }))
	}
}

private struct ScreenChrome: ViewModifier {
	let title: String
	let page: WebPage
	let isOffline: Bool
	let cachedAt: Date?
	let filtered: Bool
	let reload: @MainActor (ScreenContext) async -> Void

	@Environment(AppEnvironment.self) private var env
	@Environment(\.openURL) private var openURL
	@State private var showingFilters = false
	@State private var showingFreshness = false

	func body(content: Content) -> some View {
		@Bindable var filters = env.filters
		let freshness = env.meta.value.map { FreshnessSummary($0.freshness) }
		content
			.navigationTitle(title)
			.safeAreaInset(edge: .top, spacing: 0) {
				VStack(spacing: 0) {
					if isOffline { OfflineBanner(cachedAt: cachedAt) }
					if let warning = freshness?.lines.first(where: \.isWarning) {
						FreshnessWarningBar(line: warning) { showingFreshness = true }
					}
					if filtered {
						ActiveFilterBar(state: env.filters.state) { showingFilters = true }
					}
				}
			}
			.toolbar {
				if filtered {
					ToolbarItem(placement: .topBarLeading) {
						LensToggle(lens: $filters.state.lens)
					}
				}
				ToolbarItemGroup(placement: .topBarTrailing) {
					if env.canSync { SyncButton() }
					if filtered {
						Button {
							showingFilters = true
						} label: {
							Label(
								"Filters",
								systemImage: env.filters.state.isFiltered
									? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
						}
					}
					Menu {
						Button {
							openURL(env.config.webURL(page))
						} label: {
							Label("Open on the Web", systemImage: "safari")
						}
						if env.meta.value != nil {
							Button {
								showingFreshness = true
							} label: {
								Label("Data Freshness", systemImage: "clock")
							}
						}
						if let reason = env.syncUnavailableReason {
							Section(reason) {
								Button {} label: {
									Label("Sync", systemImage: "arrow.triangle.2.circlepath")
								}
								.disabled(true)
							}
						}
					} label: {
						Label("More Actions", systemImage: "ellipsis.circle")
					}
				}
			}
			.sheet(isPresented: $showingFilters) {
				FilterSheet()
			}
			.sheet(isPresented: $showingFreshness) {
				FreshnessSheet()
			}
			.overlay(alignment: .bottom) {
				if let report = env.sync.report {
					SyncToast(report: report) { env.sync.dismiss() }
						.padding()
						.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
			.animation(.snappy, value: env.sync.report)
			.onChange(of: env.sync.revision) {
				guard let context = env.context else { return }
				Task { await reload(context) }
			}
	}
}

/// Official or Live: which rating series every rating-derived number uses.
/// A lens, not a filter: it never hides Games.
struct LensToggle: View {
	@Binding var lens: API.Lens

	var body: some View {
		Menu {
			Picker("Rating lens", selection: $lens) {
				Text("Official Rating").tag(API.Lens.official)
				Text("Live Rating").tag(API.Lens.live)
			}
		} label: {
			Text(lens == .official ? "Official" : "Live")
				.font(.subheadline.weight(.semibold))
		}
		.accessibilityLabel("Rating lens: \(lens == .official ? "Official" : "Live")")
	}
}

/// "All Games" or what the filters keep; tap to edit.
struct ActiveFilterBar: View {
	let state: FilterState
	let edit: () -> Void

	var body: some View {
		Button(action: edit) {
			HStack(spacing: 6) {
				Image(systemName: "line.3.horizontal.decrease")
				Text(state.summary).lineLimit(1)
				Spacer(minLength: 0)
			}
			.font(.footnote)
			.foregroundStyle(state.isFiltered ? Theme.primary.color : Theme.muted.color)
			.padding(.horizontal)
			.padding(.vertical, 6)
			// Not into the safe area: there it would paint over the large title.
			.background(.bar, ignoresSafeAreaEdges: [])
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Filters: \(state.summary)")
		.accessibilityHint("Opens the filters")
	}
}

/// When Lichess and USCF were last synced, from any screen's More Actions
/// menu or its freshness warning.
private struct FreshnessSheet: View {
	@Environment(AppEnvironment.self) private var env
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List {
				if let meta = env.meta.value {
					Section {
						FreshnessView(freshness: meta.freshness)
					} footer: {
						Text("Every number on this phone comes from the server's last Sync.")
					}
				}
			}
			.navigationTitle("Data Freshness")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
			.refreshable { await env.refreshMeta() }
		}
		.presentationDetents([.medium, .large])
	}
}

/// A source that fell back to its cache or is unavailable (like "USCF
/// unavailable since"), on every screen as the web header shows it. Tap for
/// the full freshness.
struct FreshnessWarningBar: View {
	let line: FreshnessSummary.Line
	let open: () -> Void

	var body: some View {
		Button(action: open) {
			HStack(spacing: 6) {
				Image(systemName: "exclamationmark.triangle")
				Text(line.text).lineLimit(2)
				Spacer(minLength: 0)
				Image(systemName: "info.circle")
			}
			.font(.footnote.weight(.medium))
			.foregroundStyle(Theme.warning.color)
			.padding(.horizontal)
			.padding(.vertical, 6)
			.frame(maxWidth: .infinity)
			.background(Theme.warningWash.color, ignoresSafeAreaEdges: [])
		}
		.buttonStyle(.plain)
		.accessibilityElement(children: .combine)
		.accessibilityHint("Shows when each source was last synced")
	}
}

/// Shown while a screen displays its cached copy because the server can't
/// be reached.
struct OfflineBanner: View {
	let cachedAt: Date?

	var body: some View {
		HStack(spacing: 6) {
			Image(systemName: "wifi.slash")
			if let cachedAt {
				Text("Offline. Showing data from \(cachedAt, format: .relative(presentation: .named)).")
			} else {
				Text("Offline. Pull to refresh when you're back online.")
			}
			Spacer(minLength: 0)
		}
		.font(.footnote.weight(.medium))
		.foregroundStyle(Theme.warning.color)
		.padding(.horizontal)
		.padding(.vertical, 6)
		.frame(maxWidth: .infinity)
		.background(Theme.warningWash.color, ignoresSafeAreaEdges: [])
		.accessibilityElement(children: .combine)
	}
}
