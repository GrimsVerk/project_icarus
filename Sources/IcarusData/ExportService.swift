import Foundation
import IcarusCore

/// The export file, version 1. An EXTERNAL format: it carries the whole record,
/// each session's stored curve, the profile and the constant set it was written
/// under, so importing it reproduces the state and every figure (R25).
public struct ExportFile: Codable, Sendable {
    public let formatVersion: Int
    public let tunablesVersion: String
    public let profile: Profile
    public let history: History
    public let exportedAt: Date

    public init(
        formatVersion: Int,
        tunablesVersion: String,
        profile: Profile,
        history: History,
        exportedAt: Date
    ) {
        self.formatVersion = formatVersion
        self.tunablesVersion = tunablesVersion
        self.profile = profile
        self.history = history
        self.exportedAt = exportedAt
    }
}

/// What an import landed, including the profile the file carried — the app asks
/// the user about that profile rather than assuming it.
public struct ImportSummary: Sendable, Equatable {
    public let sessions: Int
    public let reports: Int
    public let tunablesVersion: String
    public let profile: Profile

    public init(sessions: Int, reports: Int, tunablesVersion: String, profile: Profile) {
        self.sessions = sessions
        self.reports = reports
        self.tunablesVersion = tunablesVersion
        self.profile = profile
    }
}

/// Why a file could not be imported. The store is untouched in every case.
public enum ImportError: Error, Sendable, Equatable {
    /// A format version this build does not know how to read.
    case unsupportedVersion(Int)
    /// The file decoded but a record in it is not one this app could have
    /// written: intervals out of order, a negative dose, an unusable curve.
    case invalidRecord(String)
}

/// Export, import, and the recomputation that proves a session record is
/// enough on its own (R22, R25).
public enum ExportService {
    /// The format this build writes.
    public static let formatVersion = 1

    /// The whole history, the profile and the constant set, as one JSON file.
    public static func export(store: HistoryStore, profile: Profile, now: Date) async throws -> Data {
        let file = try await ExportFile(
            formatVersion: formatVersion,
            tunablesVersion: store.tunablesVersion,
            profile: profile,
            history: store.history(),
            exportedAt: now
        )
        return try encoder().encode(file)
    }

    /// Read a file into the store, whole or not at all: every record is
    /// validated before anything is written.
    public static func `import`(_ data: Data, into store: HistoryStore) async throws -> ImportSummary {
        let file = try decoder().decode(ExportFile.self, from: data)
        guard file.formatVersion == formatVersion else {
            throw ImportError.unsupportedVersion(file.formatVersion)
        }
        try validate(file.history)
        try await store.replaceAll(file.history)
        return ImportSummary(
            sessions: file.history.sessions.count,
            reports: file.history.reports.count,
            tunablesVersion: file.tunablesVersion,
            profile: file.profile
        )
    }

    /// Recompute a session's per-region dose from its own record: the intervals
    /// actually faced, over the curve it was planned on, attenuated by the
    /// sunscreen and the cover it was logged with. No derived state is needed,
    /// which is what makes the record reproducible on its own.
    public static func reproduce(_ session: SessionRecord, tunables: Tunables) throws -> [Region: SED] {
        guard let intervals = session.actualIntervals, !intervals.isEmpty else { return [:] }
        let curve = try session.curveUsed.curve()
        var raw = [Region: SED]()
        for interval in intervals {
            let part = ExposureModel.dose(
                interval.exposure,
                coverHeadAndShoulders: session.coverHeadAndShoulders,
                over: interval.window,
                curve: curve,
                tunables: tunables
            )
            for (region, dose) in part {
                raw[region, default: 0] += dose
            }
        }
        return ExposureModel.attenuated(
            raw,
            sunscreen: session.sunscreen,
            coverHeadAndShoulders: session.coverHeadAndShoulders
        )
    }

    // MARK: - Inside

    /// Dates as ISO 8601 and keys in order, so two exports of the same history
    /// are the same bytes.
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Everything a written-by-this-app history must satisfy. A file that fails
    /// here never reaches the store.
    private static func validate(_ history: History) throws {
        for session in history.sessions {
            try validate(intervals: session.plannedIntervals, of: session, named: "planned")
            try validate(intervals: session.actualIntervals ?? [], of: session, named: "actual")
            for (region, dose) in session.dosePerRegion where dose < 0 {
                throw ImportError.invalidRecord("session \(session.id): negative dose for \(region)")
            }
            do {
                _ = try session.curveUsed.curve()
            } catch {
                throw ImportError.invalidRecord("session \(session.id): stored curve does not decode")
            }
        }
    }

    /// Intervals run forwards and in order, and never overlap.
    private static func validate(
        intervals: [ExposureInterval],
        of session: SessionRecord,
        named name: String
    ) throws {
        for interval in intervals where interval.window.end < interval.window.start {
            throw ImportError.invalidRecord("session \(session.id): \(name) interval ends before it starts")
        }
        let overlapping = zip(intervals, intervals.dropFirst())
            .contains { earlier, later in later.window.start < earlier.window.end }
        if overlapping {
            throw ImportError.invalidRecord("session \(session.id): \(name) intervals out of order")
        }
    }
}
