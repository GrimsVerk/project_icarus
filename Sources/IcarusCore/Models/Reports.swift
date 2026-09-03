import Foundation

/// What the skin looked like the day after a session.
public enum SkinAnswer: String, Codable, Sendable, CaseIterable {
    case normal
    case faintPink
    case clearlyPink
    case redSore
    case blistered
}

/// When the colour appeared and how long it lasted. Immediate darkening that is
/// gone by the evening is not erythema.
public enum RednessTiming: String, Codable, Sendable {
    case withinHourGoneByEvening
    case thatEvening
    case nextMorning
    case notSure
}

/// The region a skin report is about.
public enum ReportRegion: String, Codable, Sendable {
    case front
    case back
    case headAndShoulders
    case allExposed
}

/// Something that makes a report weaker evidence about the skin itself.
public enum Confounder: String, Codable, Sendable, CaseIterable {
    case photosensitisingMedication
    case illness
    case waterOrSnow
    case altitude
    case alcohol
}

/// Whether the tan actually held.
public enum LastingColour: String, Codable, Sendable {
    case yes
    case aLittle
    case no
}

/// How an answer reached the app.
public enum Channel: String, Codable, Sendable {
    case notification
    case inApp
}

/// Where a session is in its life.
public enum SessionState: String, Codable, Sendable {
    case planned
    case logged
    case discarded
}

/// One session, planned and possibly logged. The history is the record: derived
/// state is replayed from these, never stored.
public struct SessionRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let day: DayKey
    public let createdAt: Date
    public var plannedWindow: Window
    public var plannedIntervals: [ExposureInterval]
    public var firstSide: Side
    /// The sub-intervals actually faced, in order — the source of truth once logged.
    public var actualIntervals: [ExposureInterval]?
    public var posture: Posture
    public var coverHeadAndShoulders: Bool
    public var intent: Intent
    public let ceilingAtPlan: Ceiling
    public let manualMultiplierAtPlan: Double?
    /// The pair the result prescribed; nil when the second answer was not a prescription.
    public var prescribedSunscreen: SunscreenChoice?
    /// What the user confirmed at logging (nil = none).
    public var sunscreen: SunscreenChoice?
    public var state: SessionState
    /// After sunscreen and cover. Stored, never recomputed.
    public var dosePerRegion: [Region: SED]
    /// Display records only (R22).
    public var factorsShown: [Region: Double]
    public var targetsShown: [Region: SED]
    public var curveUsed: StoredCurve
    public var forecastFetchedAt: Date
    public var forecastPlace: Coordinate

    /// The span of what was actually faced.
    public var actualWindow: Window? {
        guard let intervals = actualIntervals, !intervals.isEmpty else { return nil }
        let start = intervals.map(\.window.start).min()
        let end = intervals.map(\.window.end).max()
        guard let start, let end else { return nil }
        return Window(start: start, end: end)
    }

    public init(
        id: UUID = UUID(),
        day: DayKey,
        createdAt: Date,
        plannedWindow: Window,
        plannedIntervals: [ExposureInterval],
        firstSide: Side,
        actualIntervals: [ExposureInterval]? = nil,
        posture: Posture,
        coverHeadAndShoulders: Bool,
        intent: Intent,
        ceilingAtPlan: Ceiling,
        manualMultiplierAtPlan: Double? = nil,
        prescribedSunscreen: SunscreenChoice? = nil,
        sunscreen: SunscreenChoice? = nil,
        state: SessionState,
        dosePerRegion: [Region: SED],
        factorsShown: [Region: Double] = [:],
        targetsShown: [Region: SED] = [:],
        curveUsed: StoredCurve,
        forecastFetchedAt: Date,
        forecastPlace: Coordinate
    ) {
        self.id = id
        self.day = day
        self.createdAt = createdAt
        self.plannedWindow = plannedWindow
        self.plannedIntervals = plannedIntervals
        self.firstSide = firstSide
        self.actualIntervals = actualIntervals
        self.posture = posture
        self.coverHeadAndShoulders = coverHeadAndShoulders
        self.intent = intent
        self.ceilingAtPlan = ceilingAtPlan
        self.manualMultiplierAtPlan = manualMultiplierAtPlan
        self.prescribedSunscreen = prescribedSunscreen
        self.sunscreen = sunscreen
        self.state = state
        self.dosePerRegion = dosePerRegion
        self.factorsShown = factorsShown
        self.targetsShown = targetsShown
        self.curveUsed = curveUsed
        self.forecastFetchedAt = forecastFetchedAt
        self.forecastPlace = forecastPlace
    }
}

/// One answer about the skin, and possibly the lasting-colour answer that
/// followed days later.
public struct SkinReport: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let day: DayKey
    public let reportedAt: Date
    public let answer: SkinAnswer
    public let timing: RednessTiming?
    public let region: ReportRegion
    public let confounders: Set<Confounder>
    public let channel: Channel
    public var lastingColour: LastingColour?
    public var lastingColourAt: Date?

    public init(
        id: UUID = UUID(),
        day: DayKey,
        reportedAt: Date,
        answer: SkinAnswer,
        timing: RednessTiming? = nil,
        region: ReportRegion,
        confounders: Set<Confounder> = [],
        channel: Channel,
        lastingColour: LastingColour? = nil,
        lastingColourAt: Date? = nil
    ) {
        self.id = id
        self.day = day
        self.reportedAt = reportedAt
        self.answer = answer
        self.timing = timing
        self.region = region
        self.confounders = confounders
        self.channel = channel
        self.lastingColour = lastingColour
        self.lastingColourAt = lastingColourAt
    }
}

/// Everything the user has done. Replay folds this into derived state.
public struct History: Codable, Sendable, Equatable {
    public var sessions: [SessionRecord]
    public var reports: [SkinReport]

    public init(sessions: [SessionRecord] = [], reports: [SkinReport] = []) {
        self.sessions = sessions
        self.reports = reports
    }

    /// The history as one ordered stream: logged sessions at the end of what
    /// was faced, reports when they were answered, and a lasting-colour answer
    /// at its own timestamp — never at the report's. An answer that has not
    /// been given is not emitted.
    public func ordered() -> [HistoryEvent] {
        var stamped: [Stamped] = []
        for session in sessions where session.state == .logged {
            guard let end = session.actualWindow?.end else { continue }
            stamped.append(Stamped(time: end, rank: 0, event: .session(session)))
        }
        for report in reports {
            stamped.append(Stamped(time: report.reportedAt, rank: 1, event: .report(report)))
            if report.lastingColour != nil, let answeredAt = report.lastingColourAt {
                stamped.append(Stamped(time: answeredAt, rank: 2, event: .lastingColour(report)))
            }
        }
        return stamped
            .sorted { ($0.time, $0.rank) < ($1.time, $1.rank) }
            .map(\.event)
    }
}

/// One event with the instant it belongs at, and a rank that keeps the order
/// stable when a session and a report share a timestamp.
private struct Stamped {
    let time: Date
    let rank: Int
    let event: HistoryEvent
}

/// One thing that happened, in replay order.
public enum HistoryEvent: Sendable {
    case session(SessionRecord)
    case report(SkinReport)
    case lastingColour(SkinReport)
}
