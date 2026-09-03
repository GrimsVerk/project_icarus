import Foundation

/// The identifier a Learn citation carries in `docs/LEARN_CONTENT.md`.
///
/// The source is authoritative (R26): a citation is never given an identifier
/// the source does not carry, and never dropped for lack of one.
public enum CitationIdentifier: Sendable, Equatable {
    case doi(String)
    case pmid(String)
    case iso(String)
    case url(URL)
    case none

    /// Where the identifier resolves, when it resolves anywhere.
    ///
    /// A DOI goes through doi.org and a PMID through PubMed; an ISO number and
    /// a citation without an identifier have no link, and render as text.
    public var link: URL? {
        switch self {
        case let .doi(doi): URL(string: "https://doi.org/\(doi)")
        case let .pmid(pmid): URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")
        case let .url(url): url
        case .iso, .none: nil
        }
    }
}

/// One source line of a Learn module, parsed from the `> **Sources**` block.
public struct Citation: Sendable, Equatable {
    public let authors: String
    public let title: String
    public let venue: String
    public let year: String?
    public let identifier: CitationIdentifier
    /// True when the source line carried a `[VERIFY]` marker. The marker itself
    /// never reaches the rendered text; this flag is what it becomes (S13).
    public let needsVerification: Bool

    public init(
        authors: String,
        title: String,
        venue: String,
        year: String?,
        identifier: CitationIdentifier,
        needsVerification: Bool
    ) {
        self.authors = authors
        self.title = title
        self.venue = venue
        self.year = year
        self.identifier = identifier
        self.needsVerification = needsVerification
    }

    /// Where this citation resolves, or nil when it renders as text alone.
    public var link: URL? {
        identifier.link
    }
}

// MARK: - Parsing

extension Citation {
    /// Parses one `> - ` line of a `> **Sources**` block.
    ///
    /// Best effort by design: a line that does not match the usual
    /// "Authors. *Title.* Venue, Year. Identifier" shape still yields a
    /// citation, because R26 forbids dropping one for being unparseable.
    init(sourceLine rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        let marked = line.contains(LearnSource.verificationMarker)
        let text = LearnSource.stripMarkers(line).trimmingCharacters(in: .whitespaces)

        var authors = text
        var title = ""
        var remainder = ""
        if let dot = text.range(of: ". *") {
            authors = String(text[..<dot.lowerBound])
            let afterTitleStart = text[dot.upperBound...]
            if let close = afterTitleStart.range(of: "*") {
                title = String(afterTitleStart[..<close.lowerBound])
                remainder = String(afterTitleStart[close.upperBound...])
            } else {
                title = String(afterTitleStart)
            }
        }

        let (venue, year) = Citation.venueAndYear(in: remainder)
        self.init(
            authors: authors.trimmingCharacters(in: .whitespaces),
            title: title.trimmingCharacters(in: .whitespaces),
            venue: venue,
            year: year,
            // The whole line, so an ISO number carried in the title (module 4)
            // is found as readily as one carried after the year (module 3).
            identifier: Citation.identifier(in: line),
            needsVerification: marked
        )
    }

    /// Splits "Venue, Year. …" into its two parts. Either may be absent.
    private static func venueAndYear(in remainder: String) -> (String, String?) {
        let tail = remainder.trimmingCharacters(in: .whitespaces)
        if let match = LearnSource.firstMatch(of: #"^(.*?),\s*((?:19|20)\d{2})\."#, in: tail, groups: 2) {
            return (match[0].trimmingCharacters(in: .whitespaces), match[1])
        }
        // No year: keep whatever sits before the identifier or the note.
        var venue = tail
        for cut in ["https://", "http://", " ("] where venue.range(of: cut) != nil {
            venue = String(venue[..<venue.range(of: cut)!.lowerBound])
        }
        venue = venue.trimmingCharacters(in: .whitespaces)
        while venue.hasSuffix(".") {
            venue.removeLast()
        }
        return (venue.trimmingCharacters(in: .whitespaces), nil)
    }

    /// The identifier kind and value the line carries, in priority order.
    ///
    /// Every capture stops at whitespace, so a trailing `[VERIFY]` marker is
    /// never part of a DOI or a URL.
    private static func identifier(in line: String) -> CitationIdentifier {
        if let match = LearnSource.firstMatch(of: #"https://doi\.org/(\S+)"#, in: line, groups: 1) {
            return .doi(match[0])
        }
        if let match = LearnSource.firstMatch(of: #"PMID (\d+)"#, in: line, groups: 1) {
            return .pmid(match[0])
        }
        if let match = LearnSource.firstMatch(of: #"ISO (\d+(?::\d+)?)"#, in: line, groups: 1) {
            return .iso(match[0])
        }
        if let match = LearnSource.firstMatch(of: #"(https?://\S+)"#, in: line, groups: 1) {
            if let url = URL(string: match[0]) {
                return .url(url)
            }
        }
        return .none
    }
}
