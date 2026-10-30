import Foundation
import Observation

/// Push this to open one Rated Event (its Sections, placement, and
/// crosstables).
public struct EventRoute: Hashable, Sendable {
	public let eventID: String

	public init(eventID: String) {
		self.eventID = eventID
	}
}

/// The Events screen: Series, the Rated Events inside each, the Performance
/// per Series chart, and the Rated Events entered but never played.
@MainActor @Observable
public final class EventsModel {
	public let resource = ScreenResource<API.EventsPayload>()
	private let context: ScreenContext

	public init(context: ScreenContext) { self.context = context }

	public func load() async {
		await resource.load(Endpoints.getEvents(filters: context.filters.state), in: context)
	}
}

/// One Rated Event, pushed from the Events screen.
@MainActor @Observable
public final class EventModel {
	public let resource = ScreenResource<API.EventPayload>()
	public let eventID: String
	private let context: ScreenContext

	public init(context: ScreenContext, eventID: String) {
		self.context = context
		self.eventID = eventID
	}

	public func load() async {
		await resource.load(Endpoints.getEvent(eventId: eventID, filters: context.filters.state), in: context)
	}

	/// The dashboard player's own crosstable row in a Section, if any.
	public static func playerRow(in section: API.EventSection) -> API.EventCrosstableRow? {
		section.crosstable.first(where: \.isPlayer)
	}
}
