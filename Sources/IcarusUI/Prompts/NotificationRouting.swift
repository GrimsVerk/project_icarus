#if canImport(SwiftUI)
    import Foundation
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// What a tapped notification opens.
    ///
    /// The identifier is the whole route: every prompt identifier carries the
    /// day it is about (`DayKey.id`), so the day comes back out of it in any
    /// zone, and the prefix says which question. Nothing else is stored — an
    /// identifier the app did not build resolves to nothing, and the caller
    /// falls back to the in-app card, which asks whatever is actually due.
    public enum NotificationRouting {
        public static func route(_ id: String) -> DuePrompt? {
            guard let day = PromptScheduler.day(fromNotificationID: id) else { return nil }
            if id.hasPrefix(skinPrefix) {
                return .skinCheck(day)
            }
            if id.hasPrefix(colourPrefix) {
                return .lastingColour(day)
            }
            return nil
        }

        /// The two prefixes `PromptScheduler` builds its question identifiers
        /// from. They are not public there, and this is the only place outside
        /// that actor that has to tell the two questions apart.
        private static let skinPrefix = "skin-"
        private static let colourPrefix = "colour-"
    }

    /// What a tapped notification opens, as a screen.
    ///
    /// The app shell holds the identifier and nothing else: the route, and the
    /// screen it leads to, are decided here, so the shell never names a day, a
    /// prompt kind or a store. An identifier that resolves to nothing opens the
    /// in-app card, which asks whatever is actually due.
    public struct RoutedPromptView: View {
        private let env: AppEnvironment
        private let notificationID: String

        public init(env: AppEnvironment, notificationID: String) {
            self.env = env
            self.notificationID = notificationID
        }

        public var body: some View {
            switch NotificationRouting.route(notificationID) {
            case let .some(.skinCheck(day)):
                SkinCheckFlow(model: SkinCheckModel(env: env, day: day, channel: .notification))
            case let .some(.lastingColour(day)):
                LastingColourFlow(model: LastingColourModel(env: env, day: day, channel: .notification))
            default:
                // A malformed identifier opens the card, which lists whatever
                // is due; a tap on a real prompt goes straight to its question.
                DuePromptsCard(env: env)
            }
        }
    }
#endif
