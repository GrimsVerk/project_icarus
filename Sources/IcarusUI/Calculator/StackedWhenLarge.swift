#if canImport(SwiftUI)
    import SwiftUI

    /// A form row whose label and control sit side by side, until the text is
    /// one of the accessibility sizes. There the two no longer fit on one line
    /// and SwiftUI clips the label ("rom" for "From", screen review F4), so the
    /// label goes on its own line and the control under it.
    ///
    /// `control` is built with its own label, which VoiceOver keeps reading
    /// when the large layout hides it from view; the line drawn above it is
    /// hidden from VoiceOver instead, so nothing is read twice.
    struct StackedWhenLarge<Control: View>: View {
        @Environment(\.dynamicTypeSize) private var typeSize
        let title: String
        let systemImage: String
        let control: Control

        var body: some View {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: systemImage)
                        .accessibilityHidden(true)
                    control
                        .labelsHidden()
                }
            } else {
                control
            }
        }
    }
#endif
