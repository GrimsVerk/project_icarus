import Foundation
import IcarusCore

#if canImport(UserNotifications)
    import UserNotifications

    /// The real notification centre behind `NotificationPort`. It holds no state
    /// of its own: the pending set lives in the system, and every identifier is
    /// derived from the day or the timer step it is about, so what is pending can
    /// always be read back and matched.
    ///
    /// The words are placeholders until the content layer (M3) resolves the copy
    /// keys carried in `userInfo`.
    public struct UserNotificationAdapter: NotificationPort {
        public init() {}

        public func authorization() async -> NotificationAuthorization {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: return .granted
            case .denied: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        }

        public func schedule(_ n: PendingNotification) async {
            let content = UNMutableNotificationContent()
            content.title = Self.title(for: n.kind)
            content.body = Self.body(for: n.kind)
            if let key = Self.copyKey(for: n.kind) {
                content.userInfo = ["copyKey": key.rawValue]
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Self.zone(for: n.kind)
            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: n.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: n.id, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }

        public func cancel(idPrefix: String) async {
            let centre = UNUserNotificationCenter.current()
            let doomed = await centre.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(idPrefix) }
            centre.removePendingNotificationRequests(withIdentifiers: doomed)
        }

        public func pending() async -> [PendingNotification] {
            await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
                guard let kind = NotificationID.kind(of: request.identifier),
                      let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let fireAt = trigger.nextTriggerDate()
                else { return nil }
                return PendingNotification(id: request.identifier, fireAt: fireAt, kind: kind)
            }
        }

        /// A question about a day is asked in that day's zone; a timer alert is
        /// about the clock the user is standing in.
        private static func zone(for kind: NotificationKind) -> TimeZone {
            switch kind {
            case let .skinCheck(day), let .lastingColour(day):
                TimeZone(identifier: day.timeZoneID) ?? .current
            default:
                .current
            }
        }

        private static func copyKey(for kind: NotificationKind) -> CopyKey? {
            switch kind {
            case .skinCheck: .didYouDoThisSession
            default: nil
            }
        }

        private static func title(for kind: NotificationKind) -> String {
            switch kind {
            case .skinCheck: "How is your skin?"
            case .lastingColour: "Did the colour last?"
            case .timerSideEnd: "Turn over"
            case .timerReapply: "Reapply sunscreen"
            case .timerSessionEnd: "Time to go in"
            }
        }

        private static func body(for kind: NotificationKind) -> String {
            switch kind {
            case .skinCheck: "Tell the app what your skin looked like after your session."
            case .lastingColour: "Did you notice lasting colour?"
            case .timerSideEnd: "Your first side is done."
            case .timerReapply: "It is time for the next application."
            case .timerSessionEnd: "Your session is over."
            }
        }
    }
#endif
