#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusContent
    import IcarusCore
    import SwiftUI

    /// The Calculator entry screen: four inputs, a compute button, and the ad
    /// banner underneath.
    ///
    /// It asks only what the user knows — when they are going out, how they will
    /// spend it, whether head and shoulders are covered, and whether they mean to
    /// stay for the whole window. It never asks what sunscreen they have: what to
    /// wear is the engine's answer (R15).
    ///
    /// It shows **no figure at all** — no UV index, no forecast age, no budget,
    /// no warning — because it is one of the two screens that carries the ad
    /// banner and R39 keeps every actionable number away from the banner.
    /// `acceptance/S11.sh` and `acceptance/S15.sh` check that by grepping this
    /// file for any use of the figure view at all.
    ///
    /// Every label is a line of `docs/APP_COPY.md` (CALC-1 to CALC-11), and
    /// VoiceOver reads the same words (R42, S9).
    public struct CalculatorEntryView: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = true
        public nonisolated static let showsFigures = false

        @ObservedObject private var model: CalculatorModel
        @State private var showingResult = false
        private let adBanner: AnyView?
        private let controls: AnyView?

        /// `controls` go in this screen's navigation bar: the shell's History
        /// and Settings buttons, which a row drawn outside this screen's
        /// navigation stack could not be tapped through.
        public init(model: CalculatorModel, adBanner: AnyView?, controls: AnyView? = nil) {
            self.model = model
            self.adBanner = adBanner
            self.controls = controls
        }

        public var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    // The questions that are due right now, above the inputs: the
                    // in-app fallback for a notification that was never allowed or
                    // never answered (R20). It shows nothing on a day with nothing
                    // due, and no figure ever.
                    DuePromptsCard(env: model.env)
                    Form {
                        Section {
                            windowRows
                        } header: {
                            Text(AppCopy.text(.calcSlotHeader))
                        }
                        Section {
                            postureRow
                            coverRow
                            stayRow
                        }
                        Section {
                            computeRow
                        }
                    }
                    if let adBanner {
                        adBanner
                    }
                }
                .navigationDestination(isPresented: $showingResult) {
                    ResultView(model: model)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        controls
                    }
                }
            }
        }

        // MARK: - The window

        @ViewBuilder
        private var windowRows: some View {
            DatePicker(
                selection: startBinding,
                displayedComponents: [.hourAndMinute]
            ) {
                Label(AppCopy.text(.calcFrom), systemImage: "sun.max")
            }
            DatePicker(
                selection: endBinding,
                in: model.window.start...,
                displayedComponents: [.hourAndMinute]
            ) {
                Label(AppCopy.text(.calcUntil), systemImage: "clock")
            }
        }

        /// Moving the start carries the end with it, so dragging the start never
        /// silently shortens the window to nothing.
        private var startBinding: Binding<Date> {
            Binding(
                get: { model.window.start },
                set: { start in
                    let length = model.window.end.timeIntervalSince(model.window.start)
                    model.window = Window(start: start, end: start.addingTimeInterval(max(0, length)))
                }
            )
        }

        private var endBinding: Binding<Date> {
            Binding(
                get: { model.window.end },
                set: { model.window = Window(start: model.window.start, end: max(model.window.start, $0)) }
            )
        }

        // MARK: - How it will be spent

        private var postureRow: some View {
            Picker(selection: $model.posture) {
                ForEach(Self.postures, id: \.self) { posture in
                    Text(CopyWords.posture(posture)).tag(posture)
                }
            } label: {
                Label(AppCopy.text(.calcPostureLabel), systemImage: "figure.walk")
            }
            .accessibilityIdentifier("calculator.posture")
        }

        /// Sunscreen is never cover (R10), and the line under the toggle says
        /// so, because people switch it on when they wear sunscreen.
        private var coverRow: some View {
            Toggle(isOn: $model.cover) {
                labelled(.calcCover, footnote: .calcCoverFootnote, systemImage: "person.crop.circle")
            }
        }

        /// The toggle swaps the answer's order and turns the warnings on (R15,
        /// R19), which its line underneath spells out.
        private var stayRow: some View {
            Toggle(isOn: $model.stay) {
                labelled(.calcStay, footnote: .calcStayFootnote, systemImage: "hourglass")
            }
        }

        private func labelled(_ title: CopyKey, footnote: CopyKey, systemImage: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Label(AppCopy.text(title), systemImage: systemImage)
                Text(AppCopy.text(footnote))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // MARK: - Computing

        private var computeRow: some View {
            Button {
                Task {
                    await model.compute()
                    showingResult = model.result != nil
                }
            } label: {
                Label(AppCopy.text(.calcCompute), systemImage: "arrow.forward.circle")
            }
            .accessibilityIdentifier("calculator.compute")
        }

        /// The engine's enum does not enumerate itself for a picker, so the
        /// screen lists the two cases it offers.
        private static let postures: [Posture] = [.lyingTurning, .upAndAbout]
    }

    public extension AppEnvironment {
        /// The banner for a slot of this width, or nil when there is none.
        ///
        /// It exists so the app target can fill the entry screen's slot without
        /// naming the ad provider: `AdBannerProvider` is IcarusAds' type, and
        /// R40 keeps ad code out of everything but that package and this one,
        /// which already composes it. VoiceOver names the container (VO-14),
        /// so nobody mistakes the banner for part of the app.
        func banner(width: CGFloat) -> AnyView? {
            ads.banner(width: width).map { banner in
                AnyView(
                    banner
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text(AppCopy.text(.voAdvertisement)))
                )
            }
        }
    }
#endif
