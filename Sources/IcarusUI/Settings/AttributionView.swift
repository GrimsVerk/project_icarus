#if canImport(SwiftUI)
    import Foundation
    import SwiftUI

    /// The weather attribution Apple requires beside any WeatherKit data (R29).
    ///
    /// Two parts, and neither of them is ours to write: Apple's mark, and the
    /// link to Apple's own legal page. The URL arrives with the forecast
    /// response and is wired in M7; until then the link is simply absent, which
    /// is honest, where a placeholder sentence would be copy nobody approved
    /// (R42).
    public struct AttributionView: View {
        private let legalURL: URL?

        public init(legalURL: URL?) {
            self.legalURL = legalURL
        }

        public var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "apple.logo")
                if let legalURL {
                    Link(destination: legalURL) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
#endif
