#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI

    /// The flip timer (R11).
    ///
    /// It shows the question about which side is up first, the time left on the
    /// side that is running, and the time left in the session; the alerts
    /// themselves are local notifications the model schedules, so the screen may
    /// be locked. Every sentence on it resolves through `AppCopy` (R42): the only
    /// strings built here are the clock's own numbers, which are data.
    ///
    /// It carries no banner and it does show figures, which is exactly what its
    /// `ScreenTable` row declares (R39).
    public struct FlipTimerView: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = false
        public nonisolated static let showsFigures = true

        @ObservedObject private var model: FlipTimerModel
        @State private var now = Date()
        @State private var refusal: TimerError?

        private let beat = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

        public init(model: FlipTimerModel) {
            self.model = model
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                switch model.phase {
                case .idle:
                    sidePicker
                    startButton
                case let .running(exposure, endsAt, sessionEnd):
                    running(exposure: exposure, endsAt: endsAt, sessionEnd: sessionEnd)
                case let .finished(stoppedAtPlannedEnd):
                    if stoppedAtPlannedEnd {
                        Text(AppCopy.text(.timerStoppedAtPlannedEnd))
                    }
                }
                if let refusal {
                    Text(sentence(for: refusal))
                    if case .notificationsDenied = refusal {
                        startAnyway
                    }
                }
            }
            .padding()
            .onReceive(beat) { tick in
                now = tick
                model.tick(now: tick)
            }
        }

        // MARK: - The pieces

        /// Which way up the user starts (D-2026-09-03-F8). The two options carry
        /// no words: no approved copy names a side, so each is the figure of a
        /// body lying that way up.
        private var sidePicker: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppCopy.text(.whichSideFirst))
                Picker(selection: $model.firstSide) {
                    Image(systemName: "figure.arms.open").tag(Side.faceUp)
                    Image(systemName: "figure.wave").tag(Side.faceDown)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .pickerStyle(.segmented)
            }
        }

        private var startButton: some View {
            Button {
                start(ignoringNotifications: false)
            } label: {
                Image(systemName: "play.circle.fill").font(.largeTitle)
            }
        }

        private var startAnyway: some View {
            Button {
                start(ignoringNotifications: true)
            } label: {
                Image(systemName: "play.circle").font(.title)
            }
        }

        private func running(exposure: Exposure, endsAt: Date, sessionEnd: Date) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: exposure == .lying(.faceDown) ? "figure.wave" : "figure.arms.open")
                    .font(.largeTitle)
                // Two clocks, and both are numbers rather than sentences: what
                // is left of this side, and what is left of the session.
                Text(clock(until: endsAt))
                    .font(.system(size: 56, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(clock(until: sessionEnd))
                    .font(.title3)
                    .monospacedDigit()
                Button {
                    Task { try? await model.stop(now: Date()) }
                } label: {
                    Image(systemName: "stop.circle.fill").font(.largeTitle)
                }
            }
        }

        // MARK: - Inside

        private func start(ignoringNotifications: Bool) {
            Task {
                do {
                    refusal = nil
                    try await model.start(now: Date(), ignoringNotifications: ignoringNotifications)
                } catch let error as TimerError {
                    refusal = error
                } catch {
                    refusal = nil
                }
            }
        }

        /// The refusal, in the owner's words: the notification warning as it
        /// stands, and the "no session to run" line with the outcome's own line
        /// as its reason.
        private func sentence(for error: TimerError) -> String {
            switch error {
            case .notificationsDenied:
                AppCopy.text(.timerNeedsNotifications)
            case let .cannotStart(outcome):
                AppCopy.text(.timerCannotStart, args: ["reason": AppCopy.text(Self.key(for: outcome))])
            }
        }

        /// The line an outcome shows on the Result screen, which is the reason
        /// the timer has no session to run. Keys, never words.
        private static func key(for outcome: Outcome) -> CopyKey {
            switch outcome {
            case .plan: .planBareSubWindow
            case .tooWeak: .tooWeak
            case .noViableWindow: .noViableWindow
            case .windowPassed: .windowPassed
            case .budgetSpent: .budgetSpent
            case let .missingForecast(kind):
                kind == .noLocation ? .missingForecastNoLocation : .missingForecast
            }
        }

        /// `mm:ss` while under an hour, `h:mm:ss` past it. Zero once the moment
        /// has gone by.
        private func clock(until moment: Date) -> String {
            let seconds = max(0, Int(moment.timeIntervalSince(now)))
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            let rest = seconds % 60
            let padded = String(format: "%02d:%02d", minutes, rest)
            return hours > 0 ? "\(hours):\(padded)" : padded
        }
    }
#endif
