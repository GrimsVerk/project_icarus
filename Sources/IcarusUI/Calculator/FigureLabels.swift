#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore

    /// The Result screen's figures with the words beside each number (FIG-1 to
    /// FIG-13 in `docs/APP_COPY.md`). Each label sits right after its number:
    /// "33 minutes in total".
    enum FigureLabels {
        /// One figure as the screen shows it.
        struct Shown {
            let figure: Figure
            let label: String
        }

        /// The figures in the engine's order. Two sides of equal length are one
        /// figure, "min per side" (FIG-2, R9); unequal sides are named by the
        /// side (FIG-3, FIG-4).
        static func shown(_ figures: [Figure]) -> [Shown] {
            let sides = figures.filter { $0.key == .sideMinutes }
            let equalSides = sides.count > 1 && Set(sides.map { Int($0.value.rounded()) }).count == 1
            var out: [Shown] = []
            var sideShown = false
            for figure in figures {
                guard figure.key == .sideMinutes, equalSides else {
                    out.append(Shown(figure: figure, label: label(for: figure)))
                    continue
                }
                if !sideShown {
                    sideShown = true
                    out.append(Shown(figure: figure, label: AppCopy.text(.figSideMinutes)))
                }
            }
            return out
        }

        static func label(for figure: Figure) -> String {
            if figure.key == .sideMinutes {
                return sideLabel(figure.exposure)
            }
            guard let key = lines[figure.key] else { return keyLabel(figure) }
            return AppCopy.text(key, args: ["region": figure.region.map(CopyWords.region) ?? ""])
        }

        // MARK: - Inside

        private static func sideLabel(_ exposure: Exposure?) -> String {
            switch exposure {
            case .lying(.faceUp): AppCopy.text(.figSideMinutesFaceUp)
            case .lying(.faceDown): AppCopy.text(.figSideMinutesFaceDown)
            default: AppCopy.text(.figSideMinutes)
            }
        }

        /// The range's edges are minutes on the recommendation (R7), so FIG-8
        /// to FIG-10 name them as such; the clipped upper edge is its own key.
        private static let lines: [FigureKey: CopyKey] = [
            .headlineMinutes: .figHeadlineMinutes,
            .regionDose: .figRegionDose,
            .remainingBudget: .figRemainingBudget,
            .cycleDose: .figCycleDose,
            .rangeLower: .figRangeLower,
            .rangeUpper: .figRangeUpper,
            .rangeUpperClipped: .figRangeUpperClipped,
            .uvaMultiple: .figUvaMultiple,
            .shortfall: .figShortfall,
            .extraIfCovered: .figExtraIfCovered,
        ]

        private static func keyLabel(_ figure: Figure) -> String {
            guard let region = figure.region else { return figure.key.rawValue }
            return "\(figure.key.rawValue) · \(region.rawValue)"
        }
    }
#endif
