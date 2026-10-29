#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import SwiftUI

    /// One citation of a Learn module, as a row.
    ///
    /// A citation whose identifier resolves somewhere is a `Link` to it: a DOI
    /// through doi.org, a PMID through PubMed, a URL as given. One that resolves
    /// nowhere — an ISO number, or no identifier at all — is text carrying the
    /// same authors, title and venue, plus the identifier as the source gives it.
    /// A citation is never hidden for the lack of a link (R26).
    public struct CitationRow: View {
        private let citation: Citation

        public init(citation: Citation) {
            self.citation = citation
        }

        public var body: some View {
            if let link = citation.link {
                Link(destination: link) { reference }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    reference
                    if !identifierText.isEmpty {
                        Text(identifierText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        /// The three parts every citation has, whether or not it links anywhere.
        ///
        /// Each is data from `docs/LEARN_CONTENT.md`, never a string this view
        /// holds (S11); a part the source did not carry is simply absent.
        private var reference: some View {
            VStack(alignment: .leading, spacing: 2) {
                if !citation.authors.isEmpty {
                    Text(citation.authors)
                        .font(.caption)
                }
                if !citation.title.isEmpty {
                    Text(citation.title)
                        .font(.callout)
                }
                if !venueLine.isEmpty {
                    Text(venueLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }

        /// The venue with the year the source gave beside it, or the venue alone.
        private var venueLine: String {
            guard let year = citation.year, !year.isEmpty else { return citation.venue }
            if citation.venue.isEmpty {
                return year
            }
            return "\(citation.venue), \(year)"
        }

        /// The identifier as the source carries it, for the kinds that resolve
        /// nowhere. "ISO" is part of the identifier, not copy about it: the
        /// number alone would name nothing.
        private var identifierText: String {
            switch citation.identifier {
            case let .doi(doi): doi
            case let .pmid(pmid): pmid
            case let .iso(number): "ISO \(number)"
            case let .url(url): url.absoluteString
            case .none: ""
            }
        }
    }
#endif
