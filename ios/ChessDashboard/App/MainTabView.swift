import ChessDashboardKit
import SwiftUI

/// The tab bar: the five screens used most at the club, then More (Openings,
/// Events, Analysis, and the account).
struct MainTabView: View {
	enum TabID: String { case overview, trends, games, lessons, opponents, more }

	@Environment(AppEnvironment.self) private var env
	@SceneStorage("tab") private var tab: TabID = .overview

	var body: some View {
		TabView(selection: $tab) {
			Tab("Overview", systemImage: "square.grid.2x2", value: .overview) {
				NavigationStack { PlaceholderScreen(title: "Overview", page: .overview) }
			}
			Tab("Trends", systemImage: "chart.xyaxis.line", value: .trends) {
				NavigationStack { PlaceholderScreen(title: "Trends", page: .trends) }
			}
			Tab("Games", systemImage: "list.bullet.rectangle", value: .games) {
				NavigationStack { PlaceholderScreen(title: "Games", page: .games) }
			}
			Tab("Lessons", systemImage: "lightbulb", value: .lessons) {
				NavigationStack { LessonsScreen(context: env.context!) }
			}
			Tab("Opponents", systemImage: "person.2", value: .opponents) {
				NavigationStack { OpponentsScreen(context: env.context!) }
			}
			Tab("More", systemImage: "ellipsis.circle", value: .more) {
				NavigationStack { MoreView() }
			}
		}
	}
}

/// Openings, Events, and Analysis, then who is signed in, freshness, the
/// web-only Reconciliation link, and sign-out.
struct MoreView: View {
	@Environment(AppEnvironment.self) private var env
	@Environment(\.openURL) private var openURL

	var body: some View {
		List {
			Section {
				NavigationLink { PlaceholderScreen(title: "Openings", page: .openings) } label: {
					Label("Openings", systemImage: "point.3.connected.trianglepath.dotted")
				}
				NavigationLink { PlaceholderScreen(title: "Events", page: .events) } label: {
					Label("Events", systemImage: "trophy")
				}
				NavigationLink { AnalysisScreen(context: env.context!) } label: {
					Label("Analysis", systemImage: "cpu")
				}
			}
			Section("Data") {
				if let meta = env.meta.value {
					FreshnessView(freshness: meta.freshness)
				}
				Button {
					openURL(env.config.webURL(.reconciliation))
				} label: {
					Label("Reconciliation on the web", systemImage: "safari")
				}
			}
			Section("Account") {
				if let session = env.session.session {
					LabeledContent("Signed in as", value: accountName(session))
				}
				Button("Sign Out", role: .destructive) { env.session.signOut() }
			}
		}
		.navigationTitle("More")
		.refreshable { await env.refreshMeta() }
	}

	private func accountName(_ session: Session) -> String {
		if let username = session.username { return username }
		return session.role == .guest ? "Guest (read-only)" : "Owner"
	}
}
