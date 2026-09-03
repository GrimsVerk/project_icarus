import IcarusUI
import SwiftUI

/// The app's shell: two tabs, the foreground refresh, and the deep-link router.
///
/// Nothing is decided here. The Calculator tab is the entry screen from Slice 3
/// of `calculator-ui`, built once against the shared environment so the window
/// the user entered survives a tab switch. The Learn list arrives with Slice 2
/// of `learn-tab`; until then that tab is empty rather than filled with a
/// placeholder sentence, because a user-visible sentence would have to be a
/// `CopyKey` the owner approved (R42) and no key stands for "not built yet". The
/// tab items are system images for the same reason; their titles land with the
/// copy for them. History and Settings reach the toolbar with Slice 4.
struct RootTabs: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .calculator

    var body: some View {
        TabView(selection: $tab) {
            CalculatorTab(env: env)
                .tabItem { Image(systemName: "sun.max") }
                .tag(Tab.calculator)
            // `Color.clear` and not `EmptyView`: a tab whose content is empty is
            // not a tab at all, and the tab structure is what Slice 1
            // delivered. The Learn list replaces this line in its own slice.
            Color.clear
                .tabItem { Image(systemName: "book") }
                .tag(Tab.learn)
        }
        .onOpenURL { url in
            // Every deep link the app registers is a Learn module (R27), so the
            // tab is the whole route until the Learn list can open one.
            if env.handle(url) != nil {
                tab = .learn
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await env.didBecomeActive() }
        }
    }

    private enum Tab {
        case calculator
        case learn
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
    private let banner: AnyView?

    init(env: AppEnvironment) {
        _model = StateObject(wrappedValue: CalculatorModel(env: env))
        // The banner slot is the entry screen's (R39); the provider decides
        // whether there is anything in it, and the no-op one says no.
        banner = env.banner(width: Self.bannerWidth)
    }

    var body: some View {
        CalculatorEntryView(model: model, adBanner: banner)
    }

    /// A width for the adaptive banner. The AdMob provider that actually uses it
    /// lands in M7; the no-op provider ignores it.
    private static let bannerWidth: CGFloat = 320
}
