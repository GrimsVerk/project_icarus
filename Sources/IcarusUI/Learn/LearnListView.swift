#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import SwiftUI

    /// The Learn tab: the twelve modules, and the banner under them.
    ///
    /// Each row is a module title straight from the content files — the list is
    /// data, so adding or renaming a module is an edit to
    /// `docs/LEARN_CONTENT.md` and to nothing here (R26). The title is LEARN-1
    /// (BL-2).
    ///
    /// It is the one Learn screen with a banner slot (R39). The banner arrives
    /// as a view from the app, so this package needs no ad code to place it.
    public struct LearnListView: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = true
        public nonisolated static let showsFigures = false

        private let adBanner: AnyView?
        /// The modules open on top of the list. The shell passes its own so a
        /// deep link can open one (R27); without it the list keeps its own.
        private let externalPath: Binding<[ModuleID]>?
        @State private var ownPath: [ModuleID] = []
        /// The shell's History and Settings buttons, for this tab's bar: the
        /// disclaimer must be findable from every tab (R29).
        private let controls: AnyView?

        public init(adBanner: AnyView?, path: Binding<[ModuleID]>? = nil, controls: AnyView? = nil) {
            self.adBanner = adBanner
            externalPath = path
            self.controls = controls
        }

        public var body: some View {
            NavigationStack(path: externalPath ?? $ownPath) {
                VStack(spacing: 0) {
                    List(ModuleIndex.all) { module in
                        NavigationLink(value: module.id) {
                            Text(module.title)
                        }
                        .accessibilityIdentifier("learn.module.\(module.id.rawValue)")
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
                .navigationTitle(AppCopy.text(.learnTitle))
                .toolbar {
                    if let controls {
                        ToolbarItem(placement: .topBarTrailing) {
                            controls
                        }
                    }
                }
            }
        }
    }
#endif
