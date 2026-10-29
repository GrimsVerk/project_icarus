import IcarusUI
import SwiftUI

/// The app target does one thing: it builds the live environment and hands it to
/// the shell. Every service it is made of is chosen in `AppEnvironment.live()`,
/// inside the package, so the app target holds no logic and no copy.
@main
struct ProjectIcarusApp: App {
    @StateObject private var appEnvironment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environmentObject(appEnvironment)
        }
    }
}
