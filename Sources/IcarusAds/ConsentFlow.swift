#if canImport(SwiftUI)
    import Foundation

    /// What the user answered in the network's consent form.
    public enum ConsentOutcome: Sendable, Equatable {
        /// They agreed to the network storing and reading data on the device.
        case consented
        /// They did not. The network still serves its limited ads (R39).
        case refused
    }

    /// The ad network's consent service, behind a protocol so the order the
    /// provider calls it in can be asserted without the SDK (S15).
    @MainActor
    public protocol ConsentGateway: AnyObject {
        /// Refreshes what the network knows about this user's consent here, and
        /// answers whether its form is still to be shown.
        func region() async -> ConsentRegion

        /// Shows the form, and answers what the user chose.
        func present() async -> ConsentOutcome

        /// Whether the network allows a request at all after the two above.
        var canRequestAds: Bool { get }

        /// Whether the network requires Settings to offer its privacy options
        /// form, which is how a user changes the answer later.
        var privacyOptionsRequired: Bool { get }

        /// Shows the privacy options form.
        func presentPrivacyOptions() async
    }

    #if canImport(UserMessagingPlatform) && canImport(UIKit)
        import UIKit
        import UserMessagingPlatform

        /// Google's User Messaging Platform. It decides by geography whether a
        /// form is required (the EEA and the UK, among others) and shows
        /// Google's own form; the app writes none of it.
        public final class UMPConsentGateway: ConsentGateway {
            public init() {}

            public func region() async -> ConsentRegion {
                await withCheckedContinuation { continuation in
                    // An update that fails leaves the last known status in place,
                    // which is what the network answers from below.
                    ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { @Sendable _ in
                        continuation.resume()
                    }
                }
                return ConsentInformation.shared.consentStatus == .required ? .requiresConsent : .none
            }

            public func present() async -> ConsentOutcome {
                if let presenter = Self.presenter() {
                    await withCheckedContinuation { continuation in
                        ConsentForm.loadAndPresentIfRequired(from: presenter) { @Sendable _ in
                            continuation.resume()
                        }
                    }
                }
                return Self.storageConsented ? .consented : .refused
            }

            public var canRequestAds: Bool {
                ConsentInformation.shared.canRequestAds
            }

            public var privacyOptionsRequired: Bool {
                ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            }

            public func presentPrivacyOptions() async {
                guard let presenter = Self.presenter() else { return }
                await withCheckedContinuation { continuation in
                    ConsentForm.presentPrivacyOptionsForm(from: presenter) { @Sendable _ in
                        continuation.resume()
                    }
                }
            }

            /// TCF purpose 1, storing and reading information on the device, is
            /// the one Google needs consent for to serve anything but limited ads.
            /// The form writes the answer to the IAB key in `UserDefaults`.
            private static var storageConsented: Bool {
                guard let purposes = UserDefaults.standard.string(forKey: "IABTCF_PurposeConsents") else {
                    return true
                }
                return purposes.first == "1"
            }

            /// The view controller on top, which the form is presented from.
            private static func presenter() -> UIViewController? {
                let scene = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
                var top = scene?.keyWindow?.rootViewController
                while let presented = top?.presentedViewController {
                    top = presented
                }
                return top
            }
        }
    #endif
#endif
