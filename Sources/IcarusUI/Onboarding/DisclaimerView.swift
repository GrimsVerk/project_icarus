#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import SwiftUI

    /// The medical disclaimer, and the acknowledgement of it (R29).
    ///
    /// The words are the approved `disclaimer` copy and they are the toggle's
    /// own label: the thing being acknowledged and the acknowledgement are one
    /// control, so there is no second sentence for this screen to invent and
    /// nothing for VoiceOver to read twice (R35, R42).
    public struct DisclaimerView: View {
        @ObservedObject private var model: OnboardingModel

        public init(model: OnboardingModel) {
            self.model = model
        }

        public var body: some View {
            ScrollView {
                Toggle(isOn: $model.disclaimerAcknowledged) {
                    Text(AppCopy.text(.disclaimer))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
        }
    }
#endif
