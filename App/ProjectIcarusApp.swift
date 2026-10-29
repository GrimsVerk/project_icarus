import IcarusUI
import SwiftUI
import UserNotifications

/// The app target does one thing: it builds the live environment and hands it to
/// the shell. Every service it is made of is chosen in `AppEnvironment.live()`,
/// inside the package, so the app target holds no logic and no copy.
@main
struct ProjectIcarusApp: App {
    @StateObject private var appEnvironment = AppEnvironment.live()
    @StateObject private var taps = NotificationTaps()

    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environmentObject(appEnvironment)
                .environmentObject(taps)
                .onAppear { UNUserNotificationCenter.current().delegate = taps }
        }
    }
}

/// The tapped notification's identifier, and nothing else.
///
/// A tap is the only thing the system tells the app here. What that identifier
/// means — which day, which question, or nothing the app recognises — is decided
/// in `IcarusUI` by `NotificationRouting`, so this object carries a string and
/// makes no decision at all.
@MainActor
final class NotificationTaps: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var tapped: String?

    /// A notification that arrives while the app is open still shows: the
    /// prompts are the app's own questions, and one asked while the user is
    /// somewhere else in the app must not vanish unseen.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run { self.tapped = identifier }
    }
}
