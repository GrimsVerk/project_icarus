#if canImport(SwiftUI)
    import Foundation
    import IcarusCore
    import SwiftUI

    /// The times a session actually ran, as the user can correct them.
    ///
    /// The list starts as the planned intervals and every one of them is
    /// editable, because "yes, I did that session" is rarely the plan to the
    /// minute (R20). What each stretch was — lying face up, face down, or up and
    /// about — is not editable here: that was decided when the session was
    /// planned, and changing it would be planning a different session.
    ///
    /// It shows no dose. No figure appears anywhere in the logging flow (R39),
    /// and MED and SED never appear in it at all (R20).
    public struct IntervalEditor: View {
        @Binding private var intervals: [ExposureInterval]

        public init(intervals: Binding<[ExposureInterval]>) {
            _intervals = intervals
        }

        public var body: some View {
            ForEach(Array(intervals.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(PromptWords.words(for: intervals[index].exposure))
                        .font(.footnote)
                    DatePicker(
                        selection: start(index), displayedComponents: .hourAndMinute
                    ) {
                        Image(systemName: "sun.horizon")
                    }
                    DatePicker(
                        selection: end(index), displayedComponents: .hourAndMinute
                    ) {
                        Image(systemName: "sunset")
                    }
                }
            }
        }

        // MARK: - Inside

        /// Moving a start never takes it past its own end, and moving an end
        /// never takes it before its start: a negative window is a dose of
        /// nothing, which would silently swallow the stretch.
        private func start(_ index: Int) -> Binding<Date> {
            Binding(
                get: { intervals[index].window.start },
                set: { moved in
                    let window = intervals[index].window
                    intervals[index] = ExposureInterval(
                        exposure: intervals[index].exposure,
                        window: Window(start: min(moved, window.end), end: window.end)
                    )
                }
            )
        }

        private func end(_ index: Int) -> Binding<Date> {
            Binding(
                get: { intervals[index].window.end },
                set: { moved in
                    let window = intervals[index].window
                    intervals[index] = ExposureInterval(
                        exposure: intervals[index].exposure,
                        window: Window(start: window.start, end: max(moved, window.start))
                    )
                }
            )
        }
    }
#endif
