#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// "I don't have that SPF": pick the label and the application you can
    /// actually manage, and the engine re-solves against the same region and the
    /// same remaining budget the prescription was solved on (R15).
    ///
    /// The two pickers are the SPF ladder and the three applications, both from
    /// `Tunables` and from the engine's own enum, so the sheet offers exactly
    /// what the solver can answer for. It never offers more frequent application
    /// as a substitute for a higher label — the answer to "not enough" is fewer
    /// minutes, and the re-solve says so in its own line.
    ///
    /// Confirming records the pair on the model, so "I did this" logs the dose
    /// that pair actually delivers rather than the raw whole window.
    public struct SunscreenAlternativeSheet: View {
        @ObservedObject private var model: CalculatorModel
        @Environment(\.dismiss) private var dismiss

        /// Nil until the user picks: the ladder's own first rung is the default,
        /// and the ladder is only readable once the view has the model.
        @State private var label: Int?
        @State private var application: Application = .normal

        public init(model: CalculatorModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                List {
                    Section {
                        labelPicker
                        applicationPicker
                    }
                    if let plan = model.alternative(have: choice) {
                        Section {
                            CopyLineView(line: line(for: plan))
                        }
                        Section {
                            confirmButton
                        }
                    }
                }
            }
        }

        // MARK: - The two pickers

        private var labelPicker: some View {
            Picker(selection: labelBinding) {
                // The ladder is a list of numbers from `Tunables`: data, and the
                // only labels the solver can answer for.
                ForEach(ladder, id: \.self) { spf in
                    Text(String(spf)).tag(spf)
                }
            } label: {
                Image(systemName: "drop.circle")
            }
        }

        private var ladder: [Int] {
            model.env.tunables.spfLadder.sorted()
        }

        private var labelBinding: Binding<Int> {
            Binding(get: { label ?? ladder.first ?? 0 }, set: { label = $0 })
        }

        private var applicationPicker: some View {
            Picker(selection: $application) {
                ForEach(Application.allCases, id: \.self) { applied in
                    Text(applied.rawValue).tag(applied)
                }
            } label: {
                Image(systemName: "hand.draw")
            }
        }

        private var confirmButton: some View {
            Button {
                model.confirmedSunscreen = .alternative(choice)
                dismiss()
            } label: {
                Image(systemName: "checkmark.circle")
            }
        }

        // MARK: - Inside

        private var choice: SunscreenChoice {
            SunscreenChoice(spfLabel: label ?? ladder.first ?? 0, application: application)
        }

        /// The re-solve's own line, with the numbers it produced. The engine
        /// chose which of the three sentences applies; this only fills it in.
        private func line(for plan: AlternativePlan) -> CopyLine {
            let skinType = model.env.profile.load()?.skinType ?? AppEnvironment.startingProfile.skinType
            let zone = model.forecastStatus?.curve?.timeZone ?? .current
            let resolved = AppCopy.text(plan.copy, skinType: skinType, args: [
                "spf": "SPF \(plan.with.spfLabel)",
                "application": plan.with.application.rawValue,
                "coveredMinutes": String(Int(plan.coveredWindow.minutes.rounded())),
                "window": ResultCopy.windowText(model.window, in: zone),
            ])
            let split = ResultCopy.split(resolved)
            return CopyLine(id: plan.copy.rawValue, text: split.text, modules: split.modules)
        }
    }
#endif
