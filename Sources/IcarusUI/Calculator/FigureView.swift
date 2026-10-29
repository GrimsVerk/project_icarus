#if canImport(SwiftUI)
    import Foundation
    import IcarusCore
    import SwiftUI

    /// One number from a result, with its label and — when the engine says the
    /// number rests on an assumed constant — the estimate badge beside it (R22,
    /// R30).
    ///
    /// Whether this is an estimate is never guessed at here: `Figure.isEstimate`
    /// is the engine's own answer, computed from what a recording `Tunables`
    /// observed while the number was made. The badge's VoiceOver label names the
    /// assumptions themselves, each by its line in `docs/APP_COPY.md`.
    ///
    /// Every figure the app shows goes through this view, and it lives on the
    /// Result screen alone: the Calculator entry screen shows no figure at all
    /// (R39), which `acceptance/S11.sh` and `acceptance/S15.sh` both check.
    public struct FigureView: View {
        private let figure: Figure
        private let label: String

        public init(figure: Figure, label: String) {
            self.figure = figure
            self.label = label
        }

        public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if figure.isEstimate {
                    Image(systemName: "questionmark.circle")
                        .accessibilityLabel(Text(assumptions))
                }
            }
            .accessibilityElement(children: .combine)
        }

        /// The number as the unit it is in: minutes are whole, doses and
        /// multiples carry one decimal. Digits are not copy.
        private var value: String {
            switch figure.unit {
            case .minutes: String(Int(figure.value.rounded()))
            case .sed, .multiple: String(format: "%.1f", figure.value)
            }
        }

        /// "Estimate. It rests on an assumption: …", naming each assumed
        /// constant behind this number in words (VO-1, R30).
        private var assumptions: String {
            CopyWords.estimate(figure.assumptionKeys)
        }
    }
#endif
