@testable import IcarusContent
import XCTest

/// Reads `docs/LEARN_CONTENT.md` from the repository at test time and parses it
/// here, with this file's own line scanning rather than the code under test, so
/// the assertions compare the loaded modules against the source document
/// instead of against the loader that produced them.
enum LearnSourceFixture {
    static let headingPrefix = "## Module "
    static let headingSeparator = " — "
    static let citationPrefix = "> - "
    static let sourcesHeading = "> **Sources**"
    static let verificationMarker = "[VERIFY]"

    /// `<repository root>/docs/LEARN_CONTENT.md`, found relative to this file.
    static var documentURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/IcarusContentTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("docs")
            .appendingPathComponent("LEARN_CONTENT.md")
    }

    static func document() throws -> String {
        try String(contentsOf: documentURL, encoding: .utf8)
    }

    /// One `## Module N — Title` section of the source document.
    struct Section {
        let number: Int
        let title: String
        let lines: [String]

        var text: String {
            lines.joined(separator: "\n")
        }

        var citationLines: [String] {
            lines.filter { $0.hasPrefix(citationPrefix) }
        }

        var markedCitationLines: [String] {
            citationLines.filter { $0.contains(verificationMarker) }
        }
    }

    /// Splits the document at its module headings. Everything above the first
    /// heading — the document's preamble — is discarded.
    static func sections(of document: String) -> [Section] {
        var sections: [Section] = []
        var number = 0
        var title = ""
        var lines: [String] = []
        var started = false

        for line in document.components(separatedBy: "\n") {
            if line.hasPrefix(headingPrefix), let separator = line.range(of: headingSeparator) {
                let start = line.index(line.startIndex, offsetBy: headingPrefix.count)
                if start <= separator.lowerBound, let parsed = Int(line[start ..< separator.lowerBound]) {
                    if started {
                        sections.append(Section(number: number, title: title, lines: lines))
                    }
                    started = true
                    number = parsed
                    title = String(line[separator.upperBound...])
                    lines = [line]
                    continue
                }
            }
            if started {
                lines.append(line)
            }
        }
        if started {
            sections.append(Section(number: number, title: title, lines: lines))
        }
        return sections
    }

    /// The build annotation removed the way the loader is asked to remove it:
    /// the marker, its backticks, and the single space before it.
    static func withoutMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: " `\(verificationMarker)`", with: "")
            .replacingOccurrences(of: "`\(verificationMarker)`", with: "")
            .replacingOccurrences(of: verificationMarker, with: "")
    }
}

/// Slice 1 — the twelve modules load from the bundle, carry the source's
/// titles and its text with the build annotations stripped, and every id
/// resolves.
final class ModuleIndexTests: XCTestCase {
    func testTwelveModulesLoadInIdOrder() {
        let modules = ModuleIndex.all
        XCTAssertEqual(modules.count, 12)
        XCTAssertEqual(modules.map(\.id.rawValue), Array(1 ... 12))
    }

    func testEveryModuleIdResolves() {
        for number in 1 ... 12 {
            guard let id = ModuleID(number) else {
                XCTFail("ModuleID(\(number)) should exist")
                continue
            }
            let module = ModuleIndex.module(id)
            XCTAssertEqual(module?.id, id, "module \(number)")
            XCTAssertEqual(module, ModuleIndex.all[number - 1], "module \(number)")
            XCTAssertFalse(module?.title.isEmpty ?? true, "module \(number) has a title")
            XCTAssertFalse(module?.markdown.isEmpty ?? true, "module \(number) has a body")
        }
    }

    func testModuleIdRejectsNumbersOutsideOneToTwelve() {
        XCTAssertNil(ModuleID(0))
        XCTAssertNil(ModuleID(13))
        XCTAssertNil(ModuleID(-1))
        XCTAssertNil(ModuleID(rawValue: 0))
        XCTAssertNil(ModuleID(rawValue: 13))
        XCTAssertEqual(ModuleID(1)?.rawValue, 1)
        XCTAssertEqual(ModuleID(rawValue: 12)?.rawValue, 12)
    }

    func testModuleIdRoundTripsThroughCodable() throws {
        let id = try XCTUnwrap(ModuleID(7))
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(try JSONDecoder().decode(ModuleID.self, from: data), id)
    }

    func testTitlesMatchTheSourceHeadings() throws {
        let sections = try LearnSourceFixture.sections(of: LearnSourceFixture.document())
        XCTAssertEqual(sections.count, 12, "the source document carries twelve module headings")
        XCTAssertEqual(sections.map(\.number), Array(1 ... 12))

        for section in sections {
            let id = try XCTUnwrap(ModuleID(section.number))
            let module = try XCTUnwrap(ModuleIndex.module(id))
            XCTAssertEqual(module.title, section.title, "module \(section.number) title")
        }
    }

    func testModuleMarkdownEqualsTheNormalisedSourceSection() throws {
        let document = try LearnSourceFixture.document()
        let sections = try LearnSource.split(document)
        XCTAssertEqual(sections.count, 12)

        for (id, text) in sections {
            let module = try XCTUnwrap(ModuleIndex.module(id), "module \(id.rawValue) loads")
            XCTAssertEqual(LearnSource.normalise(text), module.markdown, "module \(id.rawValue) body")
        }
    }

    func testSplitReturnsTheSourceSectionsVerbatimWithTheirMarkers() throws {
        let document = try LearnSourceFixture.document()
        let sections = try LearnSource.split(document)
        XCTAssertEqual(sections.map(\.0.rawValue), Array(1 ... 12))

        // Counted over the module sections only: the document's preamble
        // carries a marker of its own, and the preamble is not a module.
        let markersInSource = LearnSourceFixture.sections(of: document)
            .reduce(0) { $0 + $1.text.components(separatedBy: LearnSourceFixture.verificationMarker).count - 1 }
        XCTAssertGreaterThan(markersInSource, 0, "the source carries build annotations to keep")

        var markersInSections = 0
        for (id, text) in sections {
            XCTAssertTrue(
                document.contains(text),
                "module \(id.rawValue) section is verbatim source text"
            )
            XCTAssertTrue(
                text
                    .hasPrefix(
                        "\(LearnSourceFixture.headingPrefix)\(id.rawValue)\(LearnSourceFixture.headingSeparator)"
                    ),
                "module \(id.rawValue) section starts at its heading"
            )
            markersInSections += text.components(separatedBy: LearnSourceFixture.verificationMarker).count - 1
        }
        XCTAssertEqual(markersInSections, markersInSource, "split keeps every marker")
    }

    func testSplitRejectsADocumentThatIsNotTwelveModules() {
        XCTAssertThrowsError(try LearnSource.split("## Module 1 — One\n\nBody.\n\n## Module 2 — Two\n\nBody.\n"))
        XCTAssertThrowsError(try LearnSource.split("There are no modules in this text.\n"))
    }

    func testNormaliseStripsTheMarkersThePreambleAndTrailingWhitespace() throws {
        let document = try LearnSourceFixture.document()
        let firstHeading = "\(LearnSourceFixture.headingPrefix)1\(LearnSourceFixture.headingSeparator)"

        // Guards: the raw document has both the preamble and the markers, so a
        // do-nothing `normalise` cannot pass the assertions below.
        XCTAssertFalse(document.hasPrefix(firstHeading), "the source opens with its preamble")
        XCTAssertTrue(document.contains(LearnSourceFixture.verificationMarker))

        let normalised = LearnSource.normalise(document)
        XCTAssertTrue(normalised.hasPrefix(firstHeading), "the preamble above Module 1 is dropped")
        XCTAssertFalse(normalised.contains(LearnSourceFixture.verificationMarker), "no marker survives")
        XCTAssertFalse(normalised.contains("`\(LearnSourceFixture.verificationMarker)`"))
        let last: Character? = normalised.last
        XCTAssertNotNil(last, "the normalised document is not empty")
        XCTAssertFalse(last?.isWhitespace ?? true, "no trailing whitespace at the end")
        for line in normalised.components(separatedBy: "\n") {
            XCTAssertFalse(line.hasSuffix(" "), "line has no trailing space: \(line)")
            XCTAssertFalse(line.hasSuffix("\t"), "line has no trailing tab: \(line)")
        }
    }

    func testLoadedModulesCarryTheSourceTextWithoutBuildAnnotations() throws {
        let sections = try LearnSourceFixture.sections(of: LearnSourceFixture.document())

        for section in sections {
            let id = try XCTUnwrap(ModuleID(section.number))
            let module = try XCTUnwrap(ModuleIndex.module(id))

            XCTAssertFalse(
                module.markdown.contains(LearnSourceFixture.verificationMarker),
                "module \(section.number) renders no marker"
            )
            XCTAssertTrue(
                module.markdown.contains("\(LearnSourceFixture.headingPrefix)\(section.number)"
                    + "\(LearnSourceFixture.headingSeparator)\(section.title)"),
                "module \(section.number) keeps its heading"
            )

            // Every prose and citation line of the source survives, marker aside.
            for line in section.lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let expected = LearnSourceFixture.withoutMarkers(line)
                XCTAssertTrue(
                    module.markdown.contains(expected),
                    "module \(section.number) keeps line: \(expected)"
                )
            }

            if !section.citationLines.isEmpty {
                XCTAssertTrue(
                    module.markdown.contains(LearnSourceFixture.sourcesHeading),
                    "module \(section.number) keeps its Sources block"
                )
            }
        }
    }
}
