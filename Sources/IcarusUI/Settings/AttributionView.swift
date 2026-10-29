#if canImport(SwiftUI)
    import Foundation
    import IcarusData
    import SwiftUI

    /// The weather attribution Apple requires beside any WeatherKit data (R29).
    ///
    /// Two parts, and neither of them is ours to write: Apple's mark, and the
    /// link to Apple's own legal page. Both come from WeatherKit; until it has
    /// answered (or where it cannot, as in previews) the mark is a system symbol
    /// and the link is absent, where a placeholder sentence would be copy nobody
    /// approved (R42).
    public struct AttributionView: View {
        private let attribution: WeatherAttribution?
        @Environment(\.colorScheme) private var colorScheme

        public init(attribution: WeatherAttribution?) {
            self.attribution = attribution
        }

        public var body: some View {
            HStack(spacing: 6) {
                if let attribution {
                    AsyncImage(url: mark(attribution)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "apple.logo")
                    }
                    .frame(height: 14)
                    Link(destination: attribution.legalPageURL) {
                        Image(systemName: "info.circle")
                    }
                } else {
                    Image(systemName: "apple.logo")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        /// Apple's mark for the appearance on screen.
        private func mark(_ attribution: WeatherAttribution) -> URL {
            colorScheme == .dark ? attribution.markDarkURL : attribution.markLightURL
        }
    }
#endif
