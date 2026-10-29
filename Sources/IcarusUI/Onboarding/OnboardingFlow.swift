#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI

    #if canImport(CoreLocation)
        import CoreLocation
    #endif
    #if canImport(UserNotifications)
        import UserNotifications
    #endif

    /// First launch, in four pages: Module 1, the disclaimer, the skin-type
    /// table, and the two permissions with the reason for each (R28, R29).
    ///
    /// The order is the design's: the user reads what a tan is before the app
    /// asks them anything about themselves, and the module is the Learn text
    /// unsoftened rather than a gentler retelling of it. Moving on is gated by
    /// the page, not by a warning: the disclaimer page advances once it is
    /// acknowledged, and the table page once a type is chosen.
    ///
    /// It carries no banner and shows no figure (R39).
    public struct OnboardingFlow: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = false
        public nonisolated static let showsFigures = false

        @ObservedObject private var model: OnboardingModel
        private let onComplete: (Profile) -> Void
        @State private var page: Page = .module

        public init(model: OnboardingModel, onComplete: @escaping (Profile) -> Void) {
            self.model = model
            self.onComplete = onComplete
        }

        public var body: some View {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                controls
                    .padding()
            }
        }

        // MARK: - The pages

        private enum Page: Int, CaseIterable {
            case module
            case disclaimer
            case skinType
            case permissions
        }

        @ViewBuilder
        private var content: some View {
            switch page {
            case .module:
                NavigationStack {
                    ModuleView(module: OnboardingModel.module1)
                }
            case .disclaimer:
                DisclaimerView(model: model)
            case .skinType:
                SkinTypePicker(model: model)
            case .permissions:
                permissions
            }
        }

        /// The two permissions, each next to the reason it is being asked for.
        ///
        /// Neither request blocks and neither is required: a denial is an answer
        /// the app lives with, so the finishing button is offered either way.
        private var permissions: some View {
            VStack(alignment: .leading, spacing: 24) {
                permissionRow(
                    reason: AppCopy.text(.onboardingWhyLocation),
                    symbol: "location.circle",
                    request: OnboardingPermissions.requestLocation
                )
                permissionRow(
                    reason: AppCopy.text(.onboardingWhyNotifications),
                    symbol: "bell.circle",
                    request: OnboardingPermissions.requestNotifications
                )
                Spacer(minLength: 0)
            }
            .padding()
        }

        private func permissionRow(reason: String, symbol: String, request: @escaping () -> Void) -> some View {
            HStack(alignment: .top, spacing: 12) {
                Text(reason)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: request) {
                    Image(systemName: symbol)
                        .imageScale(.large)
                }
                .accessibilityLabel(Text(reason))
            }
        }

        // MARK: - Moving through the flow

        /// Back, and either forward or finish. Both are symbols: no approved
        /// copy names them, and a made-up word here would be copy the owner
        /// never saw (R42).
        private var controls: some View {
            HStack {
                Button {
                    page = Page(rawValue: page.rawValue - 1) ?? .module
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(page == .module)
                Spacer()
                if page == .permissions {
                    Button {
                        onComplete(model.complete())
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .disabled(!model.canComplete)
                } else {
                    Button {
                        page = Page(rawValue: page.rawValue + 1) ?? page
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!canAdvance)
                }
            }
            .imageScale(.large)
        }

        /// What the page the user is on still needs before it is answered.
        private var canAdvance: Bool {
            switch page {
            case .module: true
            case .disclaimer: model.disclaimerAcknowledged
            case .skinType: model.skinType != nil
            case .permissions: model.canComplete
            }
        }
    }

    /// The two system permission requests, asked and not waited on.
    ///
    /// Both are fire-and-forget: the answer arrives in the system's own dialog
    /// and the app reads the result where it matters — the location service when
    /// it fetches, the prompt scheduler when it schedules. Onboarding only asks.
    enum OnboardingPermissions {
        #if canImport(CoreLocation)
            /// Held for the life of the app: a manager that is released before
            /// the user answers takes its dialog with it. It is
            /// `nonisolated(unsafe)` rather than actor-bound because the only
            /// thing that touches it is a button action, which SwiftUI runs on
            /// the main thread; binding it to an actor would make these
            /// functions unusable as a `Button`'s action.
            private nonisolated(unsafe) static let locationManager = CLLocationManager()
        #endif

        static func requestLocation() {
            #if canImport(CoreLocation)
                locationManager.requestWhenInUseAuthorization()
            #endif
        }

        static func requestNotifications() {
            #if canImport(UserNotifications)
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            #endif
        }
    }
#endif
