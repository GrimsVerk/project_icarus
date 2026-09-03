#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// The question asked days after a report: did the colour last?
    ///
    /// It is about one day and one day only — the day the report is about, not
    /// the day the question is answered — and the answer is attached to that
    /// day's existing report. The store refuses a day with no report, so a
    /// question can never invent one (R20, R14).
    ///
    /// Like the skin check, this decides nothing about the calibration: the
    /// answer is written into the history and the replay is what reads it.
    @MainActor
    public final class LastingColourModel: ObservableObject {
        /// The day the question is about.
        public let day: DayKey

        /// How the question was reached. The report already records the channel
        /// its own answer arrived on and the history carries no second field for
        /// this one, so this is kept for the caller that opened the flow rather
        /// than written anywhere.
        public let channel: Channel

        /// The answer once it is given. The flow shows its last page from this,
        /// and it is also what stops a second write of the same answer.
        @Published public private(set) var answered: LastingColour?

        let env: AppEnvironment

        public init(env: AppEnvironment, day: DayKey, channel: Channel) {
            self.env = env
            self.day = day
            self.channel = channel
        }

        /// Attach the answer to the day's report, at the instant it was given.
        ///
        /// The time is the answer's own, never the report's: the two are days
        /// apart by design, and the replay treats the lasting colour as evidence
        /// about the day it names, dated when it was observed (R14).
        ///
        /// A day with no report throws `HistoryError.noReport`, which is the
        /// store's answer to a question that should never have been due.
        /// The parameter is unlabelled, so the call site is the plan's
        /// `submit(_:now:)`; the name inside is spelled out because the linter
        /// asks for three characters.
        public func submit(_ colour: LastingColour, now: Date) async throws {
            try await env.history.setLastingColour(day: day, colour, at: now)
            answered = colour
        }
    }
#endif
