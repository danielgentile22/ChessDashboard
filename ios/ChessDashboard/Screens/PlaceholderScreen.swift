import ChessDashboardKit
import SwiftUI

/// Stands in for a screen that a later build fills in. It already carries the
/// chrome every screen has (filters, lens, web link, freshness), so a real
/// screen replaces only the body.
struct PlaceholderScreen: View {
	let title: String
	let page: WebPage
	@Environment(AppEnvironment.self) private var env

	var body: some View {
		List {
			Section {
				ContentUnavailableView(
					"\(title) is on its way", systemImage: "hammer",
					description: Text("This screen arrives in a later build. Open it on the web for now."))
			}
			if let meta = env.meta.value {
				Section("Data") { FreshnessView(freshness: meta.freshness) }
			}
		}
		.screenChrome(title: title, page: page, resource: env.meta)
		.refreshable { await env.refreshMeta() }
	}
}
