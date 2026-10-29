#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import SwiftUI

    /// The medical disclaimer, and the acknowledgement of it (R29).
    ///
    /// The page is headed ONB-3, the approved `disclaimer` copy is the text,
    /// and the toggle under it has a short label of its own (ONB-4), so
    /// VoiceOver reads the disclaimer once and the switch as a switch (R35).
    public struct DisclaimerView: View {
        @ObservedObject private var model: OnboardingModel

        public init(model: OnboardingModel) {
            self.model = model
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppCopy.text(.onboardingDisclaimerHeading))
                        .font(.title2.bold())
                    Text(AppCopy.text(.disclaimer))
                    Toggle(isOn: $model.disclaimerAcknowledged) {
                        Text(AppCopy.text(.onboardingAcknowledge))
                    }
                    .accessibilityIdentifier("disclaimer.acknowledge")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
    }
#endif
