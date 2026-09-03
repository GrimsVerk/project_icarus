#if canImport(SwiftUI)
    import Foundation

    /// What every screen declares about itself: whether it carries the ad slot,
    /// and whether it shows any figure the user could act on (R39).
    ///
    /// It is a static declaration rather than a property of an instance, so the
    /// answer is a fact about the screen's type and can be asserted without
    /// building a view — which is what `ScreenManifestTests` does.
    public protocol ScreenManifest {
        static var hasBannerSlot: Bool { get }
        static var showsFigures: Bool { get }
    }

    /// Every screen the app has, and the two declarations each makes.
    ///
    /// This table is the declaration R39 is checked against: exactly two screens
    /// carry the banner — the Calculator entry screen, which holds inputs only
    /// and shows no figure, and the Learn module list — and no other screen
    /// carries one. Screens that later slices build are listed here before they
    /// exist, so adding a view is agreeing with a decision already recorded
    /// rather than making a new one.
    public enum ScreenTable {
        // Three members: the plan's Signatures block fixes this type, and the
        // manifest test is written blind against it.
        // swiftlint:disable large_tuple
        public static let all: [(name: String, hasBanner: Bool, showsFigures: Bool)] = [
            ("CalculatorEntryView", true, false),
            ("LearnListView", true, false),
            ("ModuleView", false, false),
            ("ResultView", false, true),
            ("FlipTimerView", false, true),
            ("OnboardingFlow", false, false),
            ("SkinCheckFlow", false, false),
            ("LastingColourFlow", false, false),
            ("HistoryView", false, true),
            ("SettingsView", false, true),
        ]

        /// The row for a screen, by the name it is declared under.
        public static func row(_ name: String) -> (name: String, hasBanner: Bool, showsFigures: Bool)? {
            all.first { $0.name == name }
        }

        // swiftlint:enable large_tuple
    }
#endif
