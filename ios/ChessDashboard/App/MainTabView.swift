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
				NavigationStack { PlaceholderScreen(title: "Overview", page: .overview).gameDestination() }
			}
			Tab("Trends", systemImage: "chart.xyaxis.line", value: .trends) {
				NavigationStack { PlaceholderScreen(title: "Trends", page: .trends).gameDestination() }
			}
			Tab("Games", systemImage: "list.bullet.rectangle", value: .games) {
				NavigationStack { GamesScreen(context: env.context!).gameDestination() }
			}
			Tab("Lessons", systemImage: "lightbulb", value: .lessons) {
				NavigationStack { PlaceholderScreen(title: "Lessons", page: .lessons).gameDestination() }
			}
			Tab("Opponents", systemImage: "person.2", value: .opponents) {
				NavigationStack { PlaceholderScreen(title: "Opponents", page: .opponents).gameDestination() }
			}
			Tab("More", systemImage: "ellipsis.circle", value: .more) {
				NavigationStack { MoreView().gameDestination() }
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
				NavigationLink { OpeningsScreen(context: env.context!) } label: {
					Label("Openings", systemImage: "point.3.connected.trianglepath.dotted")
				}
				NavigationLink { EventsScreen(context: env.context!) } label: {
					Label("Events", systemImage: "trophy")
				}
				NavigationLink { PlaceholderScreen(title: "Analysis", page: .analysis) } label: {
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
