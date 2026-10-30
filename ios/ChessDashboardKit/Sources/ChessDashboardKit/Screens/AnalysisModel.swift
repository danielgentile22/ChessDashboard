import Foundation
import Observation

/// Tactical or positional: the two kinds of mistake in the Error Profile.
public enum MistakeKind: String, CaseIterable, Sendable {
	case tactical = "Tactical"
	case positional = "Positional"
}

/// One cell of the Phase by Mistake Type matrix.
public struct PhaseCell: Hashable, Sendable {
	public let phase: API.AnalysisPhaseRowPhase
	public let kind: MistakeKind
	public let count: Int

	public init(phase: API.AnalysisPhaseRowPhase, kind: MistakeKind, count: Int) {
		self.phase = phase
		self.kind = kind
		self.count = count
	}
}

/// The Analysis screen: the Error Profile from the engine analysis Lichess
/// embedded in the Study. Like the web page it takes no filters and reads
/// every Game.
@MainActor @Observable
public final class AnalysisModel {
	public let resource = ScreenResource<API.AnalysisPayload>()
	private let context: ScreenContext

	public init(context: ScreenContext) { self.context = context }

	public func load() async {
		await resource.load(Endpoints.getAnalysis(), in: context)
	}

	/// The matrix as cells, phase by phase, tactical first.
	public var cells: [PhaseCell] { Self.cells(resource.value?.phaseTypeMatrix ?? []) }

	/// The worst specific combination to train, or nil with no mistakes.
	public var hottestCell: PhaseCell? { Self.hottestCell(resource.value?.phaseTypeMatrix ?? []) }

	public static func cells(_ rows: [API.AnalysisPhaseRow]) -> [PhaseCell] {
		rows.flatMap {
			[PhaseCell(phase: $0.phase, kind: .tactical, count: $0.tactical),
			 PhaseCell(phase: $0.phase, kind: .positional, count: $0.positional)]
		}
	}

	/// The largest count; the first one wins a tie.
	public static func hottestCell(_ rows: [API.AnalysisPhaseRow]) -> PhaseCell? {
		cells(rows).reduce(nil) { best, cell in
			cell.count > (best?.count ?? 0) ? cell : best
		}
	}
}
