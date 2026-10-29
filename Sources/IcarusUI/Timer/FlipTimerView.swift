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
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle(AppCopy.text(.timerTitle))
            .onReceive(beat) { tick in
                now = tick
                model.tick(now: tick)
            }
        }

        // MARK: - The pieces

        /// Which way up the user starts (D-2026-09-03-F8), in the same words
        /// the posture picker and the skin check use (TIM-2 to TIM-4).
        private var sidePicker: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppCopy.text(.whichSideFirst))
                Picker(selection: $model.firstSide) {
                    Text(CopyWords.side(.faceUp)).tag(Side.faceUp)
                    Text(CopyWords.side(.faceDown)).tag(Side.faceDown)
                } label: {
                    Text(AppCopy.text(.timerSidePicker))
                }
                .pickerStyle(.segmented)
            }
        }

        private var startButton: some View {
            Button {
                start(ignoringNotifications: false)
            } label: {
                Label(AppCopy.text(.timerStart), systemImage: "play.circle.fill").font(.title2)
            }
        }

        private var startAnyway: some View {
            Button {
                start(ignoringNotifications: true)
            } label: {
                Label(AppCopy.text(.timerStartWithoutAlerts), systemImage: "play.circle").font(.title3)
            }
        }

        /// The side that is up, the time left on it, and the time left in the
        /// session. On the last side the big clock runs to the session's end,
        /// so it says that instead of "until you turn over" (TIM-8, TIM-9).
        private func running(exposure: Exposure, endsAt: Date, sessionEnd: Date) -> some View {
            let side: Side = exposure == .lying(.faceDown) ? .faceDown : .faceUp
            let lastSide = abs(endsAt.timeIntervalSince(sessionEnd)) < 1
            return VStack(alignment: .leading, spacing: 16) {
                Label(
                    AppCopy.text(.timerNow, args: ["side": CopyWords.side(side).lowercased()]),
                    systemImage: side == .faceDown ? "figure.wave" : "figure.arms.open"
                )
                .font(.title2)
                countdown(
                    until: endsAt,
                    caption: lastSide ? .timerUntilEnd : .timerUntilTurn,
                    spoken: lastSide ? .voTimerUntilEnd : .voTimerUntilTurn,
                    font: .system(size: 56, weight: .medium, design: .rounded)
                )
                countdown(
                    until: sessionEnd,
                    caption: .timerLeftInSession,
                    spoken: .voTimerLeftInSession,
                    font: .title3
                )
                Button {
                    Task { try? await model.stop(now: Date()) }
                } label: {
                    Label(AppCopy.text(.timerStop), systemImage: "stop.circle.fill").font(.title2)
                }
                // Stopping shortens the record (R11): people should know
                // before they tap.
                Text(AppCopy.text(.timerStopFootnote))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        /// One clock and the words under it, which VoiceOver reads as one
        /// sentence (VO-13) rather than as a string of digits.
        private func countdown(until moment: Date, caption: CopyKey, spoken: CopyKey, font: Font) -> some View {
            let seconds = max(0, Int(moment.timeIntervalSince(now)))
            return VStack(alignment: .leading, spacing: 2) {
                Text(clock(until: moment))
                    .font(font)
                    .monospacedDigit()
                Text(AppCopy.text(caption))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(AppCopy.text(spoken, args: [
                "minutes": String(seconds / 60),
                "seconds": String(seconds % 60),
            ])))
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
