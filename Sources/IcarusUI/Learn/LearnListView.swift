#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import SwiftUI

    /// The Learn tab: the twelve modules, and the banner under them.
    ///
    /// Each row is a module title straight from the content files — the list is
    /// data, so adding or renaming a module is an edit to
    /// `docs/LEARN_CONTENT.md` and to nothing here (R26). The screen has no
    /// title of its own: every user-visible string in the UI resolves through
    /// IcarusContent (R42, S11), and no approved copy key names this tab, so it
    /// carries none rather than an unapproved sentence.
    ///
    /// It is the one Learn screen with a banner slot (R39). The banner arrives
    /// as a view from the app, so this package needs no ad code to place it.
    public struct LearnListView: View, ScreenManifest {
        public static let hasBannerSlot = true
        public static let showsFigures = false

        private let adBanner: AnyView?

        public init(adBanner: AnyView?) {
            self.adBanner = adBanner
        }

        public var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    List(ModuleIndex.all) { module in
                        NavigationLink(value: module.id) {
                            Text(module.title)
                        }
                    }
                    .navigationDestination(for: ModuleID.self) { id in
                        // A destination for an id outside 1...12 cannot be
                        // built, because `ModuleID` cannot hold one.
                        if let module = ModuleIndex.module(id) {
                            ModuleView(module: module)
                        }
                    }
                    if let adBanner {
                        adBanner
                    }
                }
            }
        }
    }
#endif
