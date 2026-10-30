import Foundation
import Observation

/// The owner's Sync action: `POST /api/v1/sync`, then the same feedback the
/// web toast and celebration banner give, then every loaded screen and the
/// shared meta re-fetch so new Games, Series and bounds show up. Pull-to-refresh
/// never comes through here: it only re-fetches.
@MainActor @Observable
public final class SyncModel {
	public enum Phase: Equatable, Sendable {
		case idle
		case running
		case finished(SyncReport)
	}

	public private(set) var phase: Phase = .idle
	/// Bumped after every successful Sync. Screens re-fetch when it changes.
	public private(set) var revision = 0

	public init() {}

	public var isRunning: Bool { phase == .running }

	public var report: SyncReport? {
		if case .finished(let report) = phase { return report }
		return nil
	}

	/// Runs one Sync when `environment.canSync`; a no-op otherwise (a guest
	/// never reaches the server's write path from the app) or while one runs.
	public func run(in environment: AppEnvironment) async {
		guard environment.canSync, !isRunning, let context = environment.context else { return }
		phase = .running
		do {
			let payload = try await context.api.send(Endpoints.runSync())
			phase = .finished(SyncReport(payload))
			if payload.status == .success {
				revision += 1
				await environment.refreshMeta()
			}
		} catch .unauthenticated {
			// SessionGuard has already routed back to sign-in.
			phase = .idle
		} catch {
			phase = .finished(SyncReport(failure: error))
		}
	}

	public func dismiss() {
		if case .finished = phase { phase = .idle }
	}
}

/// What the Sync toast says, worded like the web's (shell.run_sync).
public struct SyncReport: Equatable, Sendable {
	public enum Style: Sendable { case success, warning, failure }

	public let style: Style
	public let title: String
	public let message: String
	/// The celebration banner: personal bests and new official USCF
	/// achievements this Sync brought.
	public let celebrations: [String]
	public let newGames: [API.SyncNewGame]
	/// When Lichess data was last synced, for "synced X ago".
	public let syncedAt: Date?

	public init(_ payload: API.SyncPayload) {
		syncedAt = ISODates.timestamp(payload.syncedAt)
		switch payload.status {
		case .alreadyRunning:
			style = .warning
			title = "Sync already running"
			message = "A Sync is already in progress. Hang tight."
			celebrations = []
			newGames = []
		case .success:
			style = .success
			title = "Sync complete"
			var message = Self.describe(payload.newGames)
			if !payload.failures.isEmpty {
				message += " (couldn't fetch: \(payload.failures.map(\.studyId).joined(separator: ", ")))"
			}
			self.message = message
			celebrations = payload.milestones.map(\.description) + payload.newAchievements.map {
				"Official USCF achievement: \($0.title)" + ($0.ratedEventName.isEmpty ? "" : " (\($0.ratedEventName))")
			}
			newGames = payload.newGames
		}
	}

	public init(failure: APIError) {
		// A timeout isn't a failure yet: the server may still finish the Sync.
		style = failure == .timedOut ? .warning : .failure
		syncedAt = nil
		celebrations = []
		newGames = []
		switch failure {
		case .timedOut:
			title = "Sync is taking a while"
			self.message = "The server hasn't answered yet and may still finish. Pull to refresh in a minute to see new Games."
		case .server(_, "sync_failed", let message) where !message.isEmpty:
			title = "Sync failed"
			self.message = "\(message) (still showing your current Games)."
		case .forbidden(let message):
			title = "Sync unavailable"
			self.message = message.isEmpty ? "This account can't Sync." : message
		default:
			title = "Sync failed"
			self.message = failure.message
		}
	}

	/// "2 new Games: vs Edwards (Win), vs Lopez (Loss)".
	static func describe(_ games: [API.SyncNewGame]) -> String {
		guard !games.isEmpty else { return "No new Games. Everything is already up to date." }
		let list = games.map { "vs \($0.opponent) (\($0.outcome.rawValue))" }.joined(separator: ", ")
		return "\(games.count) new Game\(games.count == 1 ? "" : "s"): \(list)"
	}
}
