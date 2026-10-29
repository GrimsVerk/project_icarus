import IcarusContent
import IcarusUI
import SwiftUI

/// The app's shell: two tabs, the foreground refresh, and the deep-link router.
///
/// Nothing is decided here. The Calculator tab is the entry screen from Slice 3
/// of `calculator-ui`, built once against the shared environment so the window
/// the user entered survives a tab switch; the Learn tab is the module list. The
/// tab items are system images: their titles wait for approved copy (R42, BL-2).
/// Settings opens as a sheet from the Calculator's navigation bar; History sits
/// beside it and opens over the Calculator. First launch opens onboarding over everything (R28).
struct RootTabs: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var taps: NotificationTaps
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .calculator
    /// The notification whose flow is open over the tabs. Held as the tapped
    /// identifier, because that is all the shell knows: `RoutedPromptView` is
    /// what turns it into a day and a question.
    @State private var tappedPrompt: TappedPrompt?
    /// Settings is a sheet off the Calculator's toolbar, not a third tab: R39
    /// keeps the two tabs, and the banner, exactly where they are.
    @State private var settingsShown = false
    /// Whether the History screen is open over the Calculator (M6).
    @State private var showingHistory = false
    /// The Learn modules open on top of the list, so a deep link can open one.
    @State private var learnPath: [ModuleID] = []
    /// Whether onboarding is open. Decided once, on appear, from the profile's
    /// flags: finishing it is what sets them.
    @State private var onboarding = false

    var body: some View {
        TabView(selection: $tab) {
            // The entry screen owns its navigation stack, so the shell hands it
            // its controls for that bar. Settings is a sheet, not a third tab
            // (R39).
            CalculatorTab(env: env, controls: AnyView(controls))
                .tabItem { Image(systemName: "sun.max") }
                .tag(Tab.calculator)
            LearnListView(adBanner: env.banner(width: Self.bannerWidth), path: $learnPath)
                .tabItem { Image(systemName: "book") }
                .tag(Tab.learn)
        }
        .onAppear {
            onboarding = !env.profile.flags().onboardingComplete
        }
        .fullScreenCover(isPresented: $onboarding) {
            OnboardingCover(env: env) { onboarding = false }
        }
        .sheet(isPresented: $settingsShown) {
            SettingsView(model: SettingsModel(env: env))
        }
        // A sheet and not a push: History carries its own navigation.
        .sheet(isPresented: $showingHistory) {
            HistoryView(env: env)
        }
        .onOpenURL { url in
            // Every deep link the app registers is a Learn module (R27).
            if case let .learn(id) = env.handle(url) {
                tab = .learn
                learnPath = [id]
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await env.didBecomeActive() }
        }
        .onChange(of: taps.tapped) { _, identifier in
            guard let identifier else { return }
            tappedPrompt = TappedPrompt(id: identifier)
        }
        .sheet(item: $tappedPrompt, onDismiss: { taps.tapped = nil }) { prompt in
            RoutedPromptView(env: env, notificationID: prompt.id)
        }
    }

    /// History and Settings. History is reached from the Calculator rather
    /// than from a tab of its own: the record is what the user already did,
    /// not a third thing they do (M6).
    private var controls: some View {
        HStack {
            Button {
                showingHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("history")
            Button {
                settingsShown = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityIdentifier("settings")
        }
    }

    private enum Tab {
        case calculator
        case learn
    }

    /// A width for the adaptive banner. The AdMob provider that actually uses it
    /// lands in M7; the no-op provider ignores it.
    static let bannerWidth: CGFloat = 320

    /// One tapped identifier, as the sheet's item. The identifier is its own
    /// identity: two taps on the same prompt are the same sheet.
    private struct TappedPrompt: Identifiable {
        let id: String
    }
}

/// The Calculator tab, which owns the one `CalculatorModel` the entry screen and
/// the result screen share.
///
/// It is a view of its own only so that the model can be a `@StateObject` built
/// from the environment: the shell receives the environment as an object and a
/// `@StateObject` has to be built in an initializer. Owning it here keeps the
/// window the user entered across a tab switch.
private struct CalculatorTab: View {
    @StateObject private var model: CalculatorModel
    private let env: AppEnvironment
    private let banner: AnyView?
    private let controls: AnyView

    init(env: AppEnvironment, controls: AnyView) {
        _model = StateObject(wrappedValue: CalculatorModel(env: env))
        self.env = env
        self.controls = controls
        // The banner slot is the entry screen's (R39); the provider decides
        // whether there is anything in it, and the no-op one says no.
        banner = env.banner(width: RootTabs.bannerWidth)
    }

    var body: some View {
        CalculatorEntryView(model: model, adBanner: banner, controls: controls)
    }
}

/// Onboarding, holding its model for as long as it is open.
///
/// A view of its own for the same reason as `CalculatorTab`: the model has to be
/// a `@StateObject`, or every redraw of the shell would start the flow over.
private struct OnboardingCover: View {
    @StateObject private var model: OnboardingModel
    private let env: AppEnvironment
    private let done: () -> Void

    init(env: AppEnvironment, done: @escaping () -> Void) {
        _model = StateObject(wrappedValue: OnboardingModel(store: env.profile))
        self.env = env
        self.done = done
    }

    var body: some View {
        OnboardingFlow(model: model) { _ in
            // The replay reads the profile it just saved.
            Task { await env.history.invalidate() }
            done()
        }
    }
}
