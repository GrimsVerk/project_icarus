@testable import IcarusContent
import XCTest

/// Slice 1 — every `> - ` line of `docs/LEARN_CONTENT.md` reaches the loaded
/// module as a `Citation` with the identifier the source carries, the marker
/// it carried, and nothing invented. The source is read from the repository at
/// test time; the expectations are derived from it, never copied into this file.
final class CitationTests: XCTestCase {
    // MARK: - Helpers

    private func sections() throws -> [LearnSourceFixture.Section] {
        try LearnSourceFixture.sections(of: LearnSourceFixture.document())
    }

    private func module(_ number: Int) throws -> LearnModule {
        let id = try XCTUnwrap(ModuleID(number), "ModuleID(\(number))")
        return try XCTUnwrap(ModuleIndex.module(id), "module \(number) loads")
    }

    /// The one citation of a module whose authors name the given surname.
    private func citation(inModule number: Int, authoredBy surname: String) throws -> Citation {
        let matches = try module(number).citations.filter { $0.authors.contains(surname) }
        XCTAssertEqual(matches.count, 1, "module \(number) has one citation by \(surname)")
        return try XCTUnwrap(matches.first)
    }

    /// The source line of that same citation, for comparing against the parse.
    private func sourceLine(inModule number: Int, authoredBy surname: String) throws -> String {
        let section = try XCTUnwrap(sections().first { $0.number == number }, "section \(number)")
        let matches = section.citationLines.filter { $0.contains(surname) }
        XCTAssertEqual(matches.count, 1, "the source has one \(surname) line in module \(number)")
        return try XCTUnwrap(matches.first)
    }

    private func identifierValue(_ identifier: CitationIdentifier) -> String? {
        switch identifier {
        case let .doi(value): value
        case let .pmid(value): value
        case let .iso(value): value
        case let .url(value): value.absoluteString
        case .none: nil
        }
    }

    // MARK: - Nothing dropped

    func testEveryCitationLineInTheSourceIsParsed() throws {
        var total = 0
        for section in try sections() {
            let module = try module(section.number)
            XCTAssertEqual(
                module.citations.count,
                section.citationLines.count,
                "module \(section.number) citation count"
            )
            total += section.citationLines.count
        }
        XCTAssertGreaterThan(total, 20, "the source carries citations to parse")
    }

    func testModulesWithoutASourcesBlockCarryNoCitations() throws {
        let withoutSources = try sections().filter(\.citationLines.isEmpty)
        XCTAssertFalse(withoutSources.isEmpty, "the source has modules with no Sources block")
        for section in withoutSources {
            XCTAssertTrue(try module(section.number).citations.isEmpty, "module \(section.number)")
        }
    }

    func testAuthorsAndTitleAreNeverEmpty() throws {
        for section in try sections() {
            for citation in try module(section.number).citations {
                XCTAssertFalse(citation.authors.isEmpty, "module \(section.number) authors")
                XCTAssertFalse(citation.title.isEmpty, "module \(section.number) title")
            }
        }
    }

    // MARK: - Identifiers are the source's, not the parser's

    func testRoutaboulCarriesItsPubMedIdentifier() throws {
        let citation = try citation(inModule: 2, authoredBy: "Routaboul")
        XCTAssertEqual(citation.identifier, .pmid("10066941"))
        XCTAssertEqual(citation.link, URL(string: "https://pubmed.ncbi.nlm.nih.gov/10066941/"))
        XCTAssertEqual(citation.year, "1999")
        XCTAssertTrue(citation.needsVerification)
        XCTAssertTrue(citation.title.contains("Immediate pigment darkening"))
        XCTAssertTrue(citation.venue.contains("European Journal of Dermatology"))
    }

    func testMcKinlayCarriesTheIsoNumberAndNoLink() throws {
        let citation = try citation(inModule: 3, authoredBy: "McKinlay")
        XCTAssertEqual(citation.identifier, .iso("17166:1999"))
        XCTAssertNil(citation.link, "an ISO number is text, not a link")
        XCTAssertEqual(citation.year, "1987")
        XCTAssertTrue(citation.needsVerification)
    }

    func testTheIsoStandardInModuleFourCarriesTheIsoNumber() throws {
        let citation = try citation(inModule: 4, authoredBy: "International Organization for Standardization")
        XCTAssertEqual(citation.identifier, .iso("17166:1999"))
        XCTAssertNil(citation.link)
    }

    func testWorldHealthOrganizationCarriesItsUrlAsTheLink() throws {
        let citation = try citation(inModule: 3, authoredBy: "World Health Organization")
        let expected = try XCTUnwrap(URL(string: "https://www.who.int/publications/i/item/9241590076"))
        XCTAssertEqual(citation.identifier, .url(expected))
        XCTAssertEqual(citation.link, expected)
        XCTAssertEqual(citation.year, "2002")
        XCTAssertFalse(citation.needsVerification)
    }

    func testMiyamuraDoiStopsAtWhitespaceAndNeverSwallowsTheMarker() throws {
        let doi = "10.1111/j.1600-0749.2006.00358.x"
        for number in [1, 6] {
            let citation = try citation(inModule: number, authoredBy: "Miyamura")
            XCTAssertEqual(citation.identifier, .doi(doi), "module \(number)")
            XCTAssertEqual(citation.link, URL(string: "https://doi.org/\(doi)"), "module \(number)")
            XCTAssertEqual(citation.year, "2007", "module \(number)")
            XCTAssertTrue(citation.needsVerification, "module \(number) carried the marker")
        }
    }

    func testACitationWithNoIdentifierKeepsNoneAndStillAppears() throws {
        let commission = try citation(inModule: 8, authoredBy: "European Commission")
        XCTAssertEqual(commission.identifier, CitationIdentifier.none)
        XCTAssertNil(commission.link)
        XCTAssertFalse(commission.needsVerification)

        // A line with no identifier but with the marker keeps the marker's flag.
        let ledo = try citation(inModule: 10, authoredBy: "Ledo")
        XCTAssertEqual(ledo.identifier, CitationIdentifier.none)
        XCTAssertNil(ledo.link)
        XCTAssertTrue(ledo.needsVerification)
    }

    func testEveryDoiIsWellFormedAndLinksThroughDoiOrg() throws {
        var seen = 0
        for section in try sections() {
            for citation in try module(section.number).citations {
                guard case let .doi(doi) = citation.identifier else { continue }
                seen += 1
                XCTAssertTrue(doi.hasPrefix("10."), "a DOI starts with the registrant prefix: \(doi)")
                XCTAssertFalse(doi.contains(" "), "a DOI stops at whitespace: \(doi)")
                XCTAssertFalse(doi.contains("`"), "a DOI carries no backtick: \(doi)")
                XCTAssertFalse(doi.contains(LearnSourceFixture.verificationMarker), "no marker in: \(doi)")
                XCTAssertEqual(citation.link, URL(string: "https://doi.org/\(doi)"), doi)
            }
        }
        XCTAssertGreaterThan(seen, 10, "most citations in the source carry a DOI")
    }

    func testNoIdentifierIsInventedAndNoFieldCarriesMarkup() throws {
        for section in try sections() {
            let text = section.text
            for citation in try module(section.number).citations {
                if let value = identifierValue(citation.identifier) {
                    XCTAssertTrue(
                        text.contains(value),
                        "module \(section.number) identifier \(value) comes from the source"
                    )
                }
                for field in [citation.authors, citation.title, citation.venue, citation.year ?? ""] {
                    XCTAssertFalse(field.contains(LearnSourceFixture.verificationMarker), "marker in: \(field)")
                    XCTAssertFalse(field.contains("`"), "backtick in: \(field)")
                    XCTAssertFalse(field.contains("*"), "markup in: \(field)")
                }
            }
        }
    }

    // MARK: - Markers

    func testNeedsVerificationCountsMatchTheMarkedSourceLines() throws {
        var totalMarked = 0
        for section in try sections() {
            let marked = try module(section.number).citations.filter(\.needsVerification)
            XCTAssertEqual(
                marked.count,
                section.markedCitationLines.count,
                "module \(section.number) marked citations"
            )
            totalMarked += section.markedCitationLines.count
        }
        XCTAssertGreaterThan(totalMarked, 0, "the source marks citations for verification")
    }

    func testAnUnmarkedCitationIsNotFlagged() throws {
        let line = try sourceLine(inModule: 1, authoredBy: "Agar")
        XCTAssertFalse(line.contains(LearnSourceFixture.verificationMarker), "the source line is unmarked")

        let citation = try citation(inModule: 1, authoredBy: "Agar")
        XCTAssertFalse(citation.needsVerification)
        XCTAssertEqual(citation.identifier, .doi("10.1016/j.mrfmmm.2004.11.016"))
        XCTAssertEqual(citation.year, "2005")
    }

    func testEveryParsedYearAppearsInItsSourceLine() throws {
        for section in try sections() {
            let lines = section.citationLines
            for citation in try module(section.number).citations {
                guard let year = citation.year else { continue }
                XCTAssertEqual(year.count, 4, "a year is four digits: \(year)")
                XCTAssertNotNil(Int(year), "a year is numeric: \(year)")
                XCTAssertTrue(
                    lines.contains { $0.contains(citation.authors) && $0.contains(year) },
                    "module \(section.number): \(year) comes from the source line"
                )
            }
        }
    }
}
