import IcarusUI
import SwiftUI
import UserNotifications

/// The app target does one thing: it builds the live environment and hands it to
/// the shell. Every service it is made of is chosen in `AppEnvironment.live()`,
/// inside the package, so the app target holds no logic and no copy.
@main
struct ProjectIcarusApp: App {
    @StateObject private var appEnvironment = Self.environment()
    @StateObject private var taps = NotificationTaps()

    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environmentObject(appEnvironment)
                .environmentObject(taps)
                .onAppear {
                    UNUserNotificationCenter.current().delegate = taps
                    #if DEBUG
                        taps.tapped = PreviewLaunch.tappedNotification
                    #endif
                }
        }
    }

    private static func environment() -> AppEnvironment {
        #if DEBUG
            if let onboarded = PreviewLaunch.onboarded {
                return AppEnvironment.preview(onboarded: onboarded, scenario: PreviewLaunch.scenario)
            }
        #endif
        return AppEnvironment.live()
    }
}

#if DEBUG
    /// The launch arguments the screenshot UI tests start the app with. Debug
    /// builds only: a release build always runs on the live environment.
    ///
    /// `-IcarusPreview fresh` runs on `AppEnvironment.preview()` with no profile,
    /// so onboarding opens; `-IcarusPreview onboarded` skips it.
    /// `yesterday` is onboarded with a session logged the day before, and
    /// `noforecast` is onboarded with no forecast to be had.
    /// `-IcarusTapNotification <identifier>` opens the app as if that
    /// notification had been tapped, through the same route a real tap takes.
    enum PreviewLaunch {
        private static var mode: String? {
            UserDefaults.standard.string(forKey: "IcarusPreview")
        }

        static var onboarded: Bool? {
            switch mode {
            case "fresh": false
            case "onboarded", "yesterday", "noforecast": true
            default: nil
            }
        }

        static var scenario: AppEnvironment.PreviewScenario {
            switch mode {
            case "yesterday": .sessionYesterday
            case "noforecast": .noForecast
            default: .plain
            }
        }

        static var tappedNotification: String? {
            UserDefaults.standard.string(forKey: "IcarusTapNotification")
        }
    }
#endif

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
