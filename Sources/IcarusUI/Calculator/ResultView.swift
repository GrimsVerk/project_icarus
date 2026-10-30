#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// The Result screen: the whole answer for one window.
    ///
    /// The forecast line — the place, "change place" and "refresh" — is outside
    /// the outcome, so it renders for every one of them, including the outcome
    /// that shows no number at all: a user whose location was denied and whose
    /// cache is empty can still say where they are (R2, R3).
    ///
    /// Everything else follows the result. The engine renders no words: it names
    /// copy keys in display order and this view resolves each one through
    /// `AppCopy`, filling the `{arguments}` from the figures the same result
    /// carries (R42, D-2026-09-03-F7). Every number goes through `FigureView`,
    /// which carries the estimate badge when the engine says the number rests on
    /// an assumption (R22, R30). Warnings are shown only when the user marked
    /// that they will stay the whole window (R19).
    ///
    /// It carries no ad banner: R39 keeps the banner away from every screen that
    /// shows a figure the user could act on, and this is the screen that shows
    /// all of them.
    public struct ResultView: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = false
        public nonisolated static let showsFigures = true

        @ObservedObject private var model: CalculatorModel
        @State private var changingPlace = false
        @State private var choosingSunscreen = false
        /// The result "I did this" logged, so the line saying so shows under
        /// it (RES-9) and only for that result: computing again clears it.
        @State private var logged: DoseResult?
        @Environment(\.dynamicTypeSize) private var typeSize

        public init(model: CalculatorModel) {
            self.model = model
        }

        public var body: some View {
            List {
                Section {
                    forecastLine
                }
                if let result = model.result {
                    outcomeSection(result)
                    figuresSection(result)
                    actionsSection(result)
                }
            }
            .navigationTitle(AppCopy.text(.resultTitle))
            .sheet(isPresented: $changingPlace) {
                ManualLocationSheet(model: model)
            }
            .sheet(isPresented: $choosingSunscreen) {
                SunscreenAlternativeSheet(model: model)
            }
        }

        // MARK: - The forecast line, on every outcome

        private var forecastLine: some View {
            VStack(alignment: .leading, spacing: 8) {
                if !placeLine.isEmpty {
                    Text(placeLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // Each button is a full 44-point target (screen review F5).
                // At the accessibility text sizes the two do not fit side by
                // side and broke mid-word, so they stack (F4).
                buttonLayout {
                    forecastButton(.resultChangePlace, systemImage: "mappin.and.ellipse") {
                        changingPlace = true
                    }
                    if !typeSize.isAccessibilitySize {
                        Spacer()
                    }
                    forecastButton(.resultRefresh, systemImage: "arrow.clockwise") {
                        Task { await model.refreshForecast() }
                    }
                }
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }

        private var buttonLayout: AnyLayout {
            typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout())
        }

        /// At the accessibility sizes the icon alone took half the row and
        /// squeezed the words to a few letters a line, so there the button is
        /// its words across the whole row, wrapping as they need.
        private func forecastButton(
            _ title: CopyKey,
            systemImage: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                if typeSize.isAccessibilitySize {
                    Text(AppCopy.text(title))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                } else {
                    Label(AppCopy.text(title), systemImage: systemImage)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }

        /// Whose forecast this is (RES-2, RES-3). A coordinate means nothing to
        /// a reader, and turning it into a town would be one more network
        /// call (V11), so the phone's own place is "your location".
        private var placeLine: String {
            if let name = model.placeName {
                return AppCopy.text(.resultForecastFor, args: ["place": name])
            }
            return model.forecastStatus?.curve == nil ? "" : AppCopy.text(.resultForecastHere)
        }

        /// `{place}` in the stale-forecast heads-up (FILL-6).
        private var placeText: String {
            model.placeName ?? AppCopy.text(.placeYourLocation)
        }

        /// `{place}` in "the saved forecast is for {place}, which is not where
        /// you are": there FILL-6's "your location" would contradict itself,
        /// so the line names the saved forecast's own coordinate, as data.
        private var cachedPlaceText: String {
            guard let location = model.forecastStatus?.curve?.location else { return "" }
            return String(format: "%.2f, %.2f", location.latitude, location.longitude)
        }

        // MARK: - The outcome

        private func outcomeSection(_ result: DoseResult) -> some View {
            Section {
                ForEach(copy(for: result).lines) { line in
                    CopyLineView(line: line)
                }
            }
        }

        /// Every figure the result carries, under the line that says the number
        /// is what to do (RES-6, R7), each with its own label (FIG-1 to FIG-13).
        @ViewBuilder
        private func figuresSection(_ result: DoseResult) -> some View {
            let figures = FigureLabels.shown(result.figures)
            if !figures.isEmpty {
                Section {
                    Text(AppCopy.text(.resultDoTheNumber))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(Array(figures.enumerated()), id: \.offset) { numbered in
                        FigureView(figure: numbered.element.figure, label: numbered.element.label)
                    }
                }
            }
        }

        // MARK: - What the user can do about it

        @ViewBuilder
        private func actionsSection(_ result: DoseResult) -> some View {
            if case let .plan(_, sunscreen, _) = result.outcome {
                Section {
                    if case .prescribe = sunscreen {
                        Button {
                            choosingSunscreen = true
                        } label: {
                            Label(AppCopy.text(.resultNoSuchSPF), systemImage: "drop.circle")
                        }
                    }
                    Button {
                        Task {
                            do {
                                try await model.didThis()
                                logged = result
                            } catch {
                                logged = nil
                            }
                        }
                    } label: {
                        Label(AppCopy.text(.resultDidThis), systemImage: "checkmark.circle")
                    }
                    .accessibilityIdentifier("result.didThis")
                    // Nothing else changes on the screen after the tap, so
                    // without this line people tap twice.
                    if logged == result {
                        Text(AppCopy.text(.resultLogged))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    // Lying down, the flip timer is the session clock (R11), and
                    // starting it is the other way a plan becomes a record.
                    if model.posture == .lyingTurning {
                        NavigationLink {
                            FlipTimerScreen(calculator: model)
                        } label: {
                            Label(AppCopy.text(.resultStartTimer), systemImage: "timer")
                        }
                        .accessibilityIdentifier("result.timer")
                    }
                }
            }
        }

        // MARK: - Inside

        private func copy(for result: DoseResult) -> ResultCopy {
            ResultCopy(
                result: result,
                skinType: model.env.profile.load()?.skinType ?? AppEnvironment.startingProfile.skinType,
                tunables: model.env.tunables,
                window: model.window,
                place: placeText,
                cachedPlace: cachedPlaceText,
                showWarnings: model.stay,
                timeZone: model.forecastStatus?.curve?.timeZone ?? .current
            )
        }
    }

    /// The flip timer, holding its model for as long as the screen is open.
    struct FlipTimerScreen: View {
        @StateObject private var model: FlipTimerModel

        init(calculator: CalculatorModel) {
            _model = StateObject(wrappedValue: FlipTimerModel(env: calculator.env, calculator: calculator))
        }

        var body: some View {
            FlipTimerView(model: model)
        }
    }

    // MARK: - One line of the app's own words

    /// One resolved line of copy: the sentence with its `[Module N]` markers
    /// taken out, and the modules those markers named.
    struct CopyLine: Identifiable {
        let id: String
        let text: String
        let modules: [ModuleID]
    }

    /// A line and the Learn links it carries. The link's words are the module's
    /// own title, which is Learn content rather than app copy (R26, R27).
    struct CopyLineView: View {
        let line: CopyLine

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(line.text)
                    .font(.body)
                ForEach(line.modules, id: \.rawValue) { id in
                    if let module = ModuleIndex.module(id) {
                        Link(destination: ModuleIndex.deepLink(id)) {
                            Text(module.title)
                                .font(.footnote)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The result, as words

    /// Turns one `DoseResult` into the lines the screen shows.
    ///
    /// The engine fixed the order and the set: `copyKeys` is display order and
    /// this only resolves each key and fills its `{arguments}` from the numbers
    /// the same result carries. It invents no sentence and drops none, except the
    /// two warning lines, which R19 shows only when the user marked that they
    /// will stay out for the whole window.
    struct ResultCopy {
        let result: DoseResult
        let skinType: SkinType
        let tunables: Tunables
        let window: Window
        let place: String
        let cachedPlace: String
        let showWarnings: Bool
        let timeZone: TimeZone

        var lines: [CopyLine] {
            result.copyKeys
                .filter { showWarnings || !Self.warningKeys.contains($0) }
                .map { key in
                    let resolved = AppCopy.text(key, skinType: skinType, args: args(for: key))
                    let split = Self.split(resolved)
                    return CopyLine(id: key.rawValue, text: split.text, modules: split.modules)
                }
        }

        // MARK: The arguments each line needs

        func args(for key: CopyKey) -> [String: String] {
            outcomeArgs(key) ?? staleArgs(key) ?? adaptationArgs(key) ?? planArgs(key) ?? sunscreenArgs(key) ?? [:]
        }

        private func outcomeArgs(_ key: CopyKey) -> [String: String]? {
            switch key {
            case .planBareSubWindow:
                ["minutes": Self.minutes(plan?.totalMinutes ?? 0)]
            case .planStayWearThis:
                ["window": windowText, "spf": spfText, "application": applicationText]
            case .planStayWholeWindowFits:
                ["window": windowText]
            case .tooWeak:
                ["shortfall": Self.sed(shortfall), "nextDay": nextViableDay, "nextHour": nextViableHour]
            case .noViableWindow:
                ["days": String(horizonDays), "peakUVI": Self.sed(peakUVI)]
            case .budgetSpent:
                ["region": CopyWords.region(spentRegion)]
            case .missingForecast:
                ["reason": missingReason]
            default:
                nil
            }
        }

        private func staleArgs(_ key: CopyKey) -> [String: String]? {
            switch key {
            case .staleHeadsUp:
                ["hours": staleHours, "place": place]
            case .staleWarn:
                ["hours": staleHours]
            case .staleFarFromCache:
                ["place": cachedPlace]
            default:
                nil
            }
        }

        private func adaptationArgs(_ key: CopyKey) -> [String: String]? {
            switch key {
            case .escalationRisen:
                ["cycleDose": Self.sed(result.cycleDose[focusRegion] ?? 0)]
            case .toleranceDropped:
                ["percent": Self.percent(droppedFraction)]
            case .ceilingReached, .underDosed:
                ["count": String(tunables.ceilingNoColourCount)]
            case .maintenance:
                ["percent": Self.percent(tunables.maintenanceFraction)]
            case .conservativeUntilCalibrated:
                ["count": String(tunables.calibrationReports)]
            case .aggressiveLocked:
                ["count": String(tunables.aggressiveUnlockReports)]
            default:
                nil
            }
        }

        private func planArgs(_ key: CopyKey) -> [String: String]? {
            switch key {
            case .coverToRunLonger:
                ["minutes": Self.minutes(plan?.extraMinutesIfCovered.values.max() ?? 0)]
            case .oneSideSpent:
                ["region": CopyWords.region(plan?.limitingRegion ?? focusRegion)]
            case .warnPastTarget, .warnReachesThreshold:
                warningArgs(key)
            default:
                nil
            }
        }

        private func sunscreenArgs(_ key: CopyKey) -> [String: String]? {
            switch key {
            case .sunscreenPrescribed:
                return ["window": windowText, "spf": spfText, "application": applicationText]
            case .uvaMultiple:
                return ["multiple": Self.sed(advice?.uvaMultiple ?? 1)]
            case .reapply:
                let clock = Self.time(in: timeZone)
                return ["times": (advice?.reapplyAt ?? []).map(clock).joined(separator: ", ")]
            default:
                return nil
            }
        }

        /// The warning's own region and the day total it names — never a number
        /// derived from the target (R19).
        private func warningArgs(_ key: CopyKey) -> [String: String] {
            var region = focusRegion
            var total: SED = 0
            for warning in plan?.warnings ?? [] {
                switch warning {
                case let .pastTarget(warned, dayTotal) where key == .warnPastTarget:
                    region = warned
                    total = dayTotal
                case let .reachesThreshold(warned, dayTotal) where key == .warnReachesThreshold:
                    region = warned
                    total = dayTotal
                default:
                    continue
                }
            }
            return ["window": windowText, "region": CopyWords.region(region), "sed": Self.sed(total)]
        }

        // MARK: What the result says

        private var plan: ExposurePlan? {
            if case let .plan(solved, _, _) = result.outcome {
                return solved
            }
            return nil
        }

        private var advice: SunscreenAdvice? {
            if case let .plan(_, sunscreen, _) = result.outcome, case let .prescribe(prescribed) = sunscreen {
                return prescribed
            }
            return nil
        }

        private var focusRegion: Region {
            result.attenuationRegion ?? plan?.limitingRegion ?? .front
        }

        private var spentRegion: Region {
            if case let .budgetSpent(region) = result.outcome {
                return region
            }
            return focusRegion
        }

        private var shortfall: SED {
            if case let .tooWeak(missing, _) = result.outcome {
                return missing
            }
            return 0
        }

        private var nextViable: Window? {
            if case let .tooWeak(_, next) = result.outcome {
                return next
            }
            return nil
        }

        private var horizonDays: Int {
            if case let .noViableWindow(days, _) = result.outcome {
                return days
            }
            return tunables.forecastHorizonDays
        }

        private var peakUVI: UVI {
            if case let .noViableWindow(_, peak) = result.outcome {
                return peak
            }
            return 0
        }

        private var missingReason: String {
            if case let .missingForecast(kind) = result.outcome {
                return CopyWords.reason(kind)
            }
            return ""
        }

        private var droppedFraction: Double {
            if case let .dropped(fraction)? = result.notices.escalation {
                return fraction
            }
            return 0
        }

        private var staleHours: String {
            switch result.notices.stale {
            case .fresh: "0"
            case let .headsUp(hours): String(Int(hours.rounded()))
            case let .warn(hours, _): String(Int(hours.rounded()))
            }
        }

        // MARK: Formatting — digits and unit tokens, never sentences

        private var spfText: String {
            "SPF \(advice?.prescribed.spfLabel ?? 0)"
        }

        /// FILL-2: "applied normally", not the enum's "applied normal".
        private var applicationText: String {
            CopyWords.application(advice?.prescribed.application ?? .normal)
        }

        private var windowText: String {
            Self.windowText(window, in: timeZone)
        }

        /// A window as the two clock times that bound it, in the forecast's own
        /// zone — the day and its hours belong to the place, not to the device.
        static func windowText(_ window: Window, in zone: TimeZone) -> String {
            let clock = time(in: zone)
            return "\(clock(window.start))–\(clock(window.end))"
        }

        private var nextViableDay: String {
            guard let next = nextViable else { return "" }
            return Self.formatter(in: timeZone, dateStyle: .medium, timeStyle: .none).string(from: next.start)
        }

        private var nextViableHour: String {
            guard let next = nextViable else { return "" }
            return Self.time(in: timeZone)(next.start)
        }

        private static let warningKeys: Set<CopyKey> = [.warnPastTarget, .warnReachesThreshold]

        private static func minutes(_ value: Double) -> String {
            String(Int(value.rounded()))
        }

        private static func sed(_ value: Double) -> String {
            String(format: "%.1f", value)
        }

        private static func percent(_ fraction: Double) -> String {
            String(Int((fraction * 100).rounded()))
        }

        private static func time(in zone: TimeZone) -> (Date) -> String {
            let formatter = Self.formatter(in: zone, dateStyle: .none, timeStyle: .short)
            return { formatter.string(from: $0) }
        }

        private static func formatter(
            in zone: TimeZone,
            dateStyle: DateFormatter.Style,
            timeStyle: DateFormatter.Style
        ) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = zone
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
            return formatter
        }

        /// Splits `[Module N]` markers out of a resolved line: the sentence keeps
        /// its words, and each marker becomes a module the view links to.
        static func split(_ text: String) -> (text: String, modules: [ModuleID]) {
            var body = text
            var modules: [ModuleID] = []
            let marker = "[Module "
            while true {
                guard let open = body.range(of: marker),
                      let close = body.range(of: "]", range: open.upperBound ..< body.endIndex)
                else { break }
                let digits = body[open.upperBound ..< close.lowerBound].trimmingCharacters(in: .whitespaces)
                if let number = Int(digits), let id = ModuleID(rawValue: number) {
                    modules.append(id)
                }
                body.removeSubrange(open.lowerBound ..< close.upperBound)
            }
            return (body.trimmingCharacters(in: .whitespaces), modules)
        }
    }
#endif
