#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI

    /// The skin type, changed after onboarding (SET-21): the six rows of the
    /// onboarding table, with the one the app plans for marked.
    ///
    /// This is where the approved `revisitSkinType` line sends a user whose
    /// reports put them outside their type's range. The page is titled with the
    /// onboarding page's heading (ONB-5), the same question asked again.
    struct SkinTypeSettingView: View {
        @ObservedObject var model: SettingsModel

        var body: some View {
            List(SkinTypeTable.rows, id: \.type) { row in
                Button {
                    Task { await model.setSkinType(row.type) }
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            Text(row.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if model.skinType == row.type {
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(AppCopy.text(.onboardingSkinTypeHeading))
        }
    }
#endif
