import IcarusUI
import SwiftUI

/// The app's shell: two tabs, the foreground refresh, and the deep-link router.
///
/// Nothing is decided here. The tabs' contents arrive with their own slices —
/// the Calculator entry screen with Slice 3 of this plan, the Learn list with
/// Slice 2 of `learn-tab` — and until then each tab is empty rather than filled
/// with a placeholder sentence, because a user-visible sentence would have to be
/// a `CopyKey` the owner approved (R42) and no key stands for "not built yet".
/// The tab items are system images for the same reason; their titles land with
/// the copy for them. History and Settings reach the toolbar with Slice 4.
struct RootTabs: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .calculator

    var body: some View {
        TabView(selection: $tab) {
            // `Color.clear` and not `EmptyView`: a tab whose content is empty is
            // not a tab at all, and the tab structure is what this slice
            // delivers. The screens replace these two lines in their slices.
            Color.clear
                .tabItem { Image(systemName: "sun.max") }
                .tag(Tab.calculator)
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
