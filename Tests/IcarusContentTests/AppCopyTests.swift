import Foundation
import IcarusContent
import IcarusCore
import XCTest

/// Reads `docs/APP_COPY.md` from the repository at test time and parses it here,
/// with this file's own line scanning rather than the build script, so every
/// assertion compares the resolved copy against the owner-approved document
/// (S17) instead of against the generator that produced the JSON.
enum AppCopyFixture {
    static let notificationSection = "Notification texts"
    static let skinTypesSection = "Skin types"
    static let quizSection = "Fitzpatrick quiz"
    static let questionSeparator = " — "
    static let optionSeparator = " | "
    static let romanNumerals = ["I", "II", "III", "IV", "V", "VI"]

    /// One `### <CopyKey>` entry: the line every skin type gets, and the line
    /// types I and II get instead when the document carries one.
    struct Entry: Equatable {
        let base: String
        let fair: String?
    }

    /// One row of the `## Skin types` table.
    struct SkinRow: Equatable {
        let roman: String
        let name: String
        let description: String
    }

    /// One numbered line of the `## Fitzpatrick quiz` list.
    struct QuizLine: Equatable {
        let id: Int
        let text: String
        let options: [String]
    }

    /// Everything the document declares, in the order it declares it.
    struct Parsed {
        var order: [String] = []
        var entries: [String: Entry] = [:]
        var skinRows: [SkinRow] = []
        var quiz: [QuizLine] = []
    }

    /// `<repository root>/docs/APP_COPY.md`, found relative to this file.
    static var documentURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/IcarusContentTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("docs")
            .appendingPathComponent("APP_COPY.md")
    }

    static func document() throws -> String {
        try String(contentsOf: documentURL, encoding: .utf8)
    }

    /// Splits the document into its keys, its skin-type table and its quiz.
    ///
    /// The `## Notification texts` section is skipped: its keys are approved
    /// wording for a later plan and are not `CopyKey` cases yet.
    static func parse(_ document: String) -> Parsed {
        var parsed = Parsed()
        var section = ""
        var key: String?
        var base: [String: String] = [:]
        var fair: [String: String] = [:]

        for raw in document.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                section = String(line.dropFirst(3))
                key = nil
                continue
            }
            if line.hasPrefix("### ") {
                key = section == notificationSection ? nil : String(line.dropFirst(4))
                if let key {
                    parsed.order.append(key)
                }
                continue
            }
            if let key, let text = value(of: "- base:", in: line) {
                base[key] = text
            }
            if let key, let text = value(of: "- fair:", in: line) {
                fair[key] = text
            }
            if section == skinTypesSection, let row = skinRow(line) {
                parsed.skinRows.append(row)
            }
            if section == quizSection, let question = quizLine(line) {
                parsed.quiz.append(question)
            }
        }

        for key in parsed.order {
            parsed.entries[key] = Entry(base: base[key] ?? "", fair: fair[key])
        }
        return parsed
    }

    /// The `{name}` placeholders a line carries, first appearance first.
    static func placeholders(in text: String) -> [String] {
        var names: [String] = []
        var current: String?
        for character in text {
            switch character {
            case "{":
                current = ""
            case "}":
                if let name = current, !name.isEmpty, !names.contains(name) {
                    names.append(name)
                }
                current = nil
            default:
                current?.append(character)
            }
        }
        return names
    }

    private static func value(of prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    /// A `| I | Type I | … |` row. The header and the separator have no roman
    /// numeral in their first cell, so they fall out here rather than by index.
    private static func skinRow(_ line: String) -> SkinRow? {
        guard line.hasPrefix("|") else { return nil }
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard cells.count == 3, romanNumerals.contains(cells[0]) else { return nil }
        return SkinRow(roman: cells[0], name: cells[1], description: cells[2])
    }

    /// A `N. question — option | option | …` line. Prose in the section's
    /// preamble has no number before its first full stop and is skipped.
    private static func quizLine(_ line: String) -> QuizLine? {
        guard let dot = line.firstIndex(of: "."), let id = Int(line[line.startIndex ..< dot]) else { return nil }
        let rest = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        guard let separator = rest.range(of: questionSeparator) else { return nil }
        let options = rest[separator.upperBound...]
            .components(separatedBy: optionSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return QuizLine(
            id: id,
            text: String(rest[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces),
            options: options
        )
    }
}

/// Every `CopyKey` resolves, and it resolves to the line the owner approved —
/// the promise S11 and S17 are made of (R42).
final class AppCopyTests: XCTestCase {
    private var parsed = AppCopyFixture.Parsed()

    override func setUpWithError() throws {
        parsed = try AppCopyFixture.parse(AppCopyFixture.document())
    }

    func testTheDocumentAndTheEnumDeclareExactlyTheSameKeys() {
        XCTAssertEqual(parsed.order.count, Set(parsed.order).count, "a key is declared twice")
        XCTAssertEqual(Set(parsed.order), Set(CopyKey.allCases.map(\.rawValue)))
    }

    func testAllKeysIsEveryCopyKey() {
        XCTAssertEqual(AppCopy.allKeys, Set(CopyKey.allCases))
    }

    func testEveryKeyResolvesToItsApprovedLineWithNoArgumentSubstituted() throws {
        for key in CopyKey.allCases {
            let entry = try XCTUnwrap(parsed.entries[key.rawValue], "no entry for \(key.rawValue)")
            XCTAssertFalse(entry.base.isEmpty, "\(key.rawValue) has an empty base line")
            XCTAssertEqual(AppCopy.text(key), entry.base, key.rawValue)
        }
    }

    /// Types I and II take the `- fair:` line where the document carries one,
    /// and the `- base:` line everywhere else (R43).
    func testFairSkinTypesTakeTheFairLineAndEveryOtherTypeTakesTheBaseLine() throws {
        for key in CopyKey.allCases {
            let entry = try XCTUnwrap(parsed.entries[key.rawValue], "no entry for \(key.rawValue)")
            for type in SkinType.allCases {
                let expected = type.band == .fair ? (entry.fair ?? entry.base) : entry.base
                XCTAssertEqual(AppCopy.text(key, skinType: type), expected, "\(key.rawValue) type \(type.rawValue)")
            }
        }
    }

    func testSupplyingEveryArgumentLeavesNoPlaceholderBehind() throws {
        for key in CopyKey.allCases {
            let entry = try XCTUnwrap(parsed.entries[key.rawValue], "no entry for \(key.rawValue)")
            let names = AppCopyFixture.placeholders(in: entry.base)
            guard !names.isEmpty else { continue }
            let args = Dictionary(uniqueKeysWithValues: names.map { ($0, "<\($0)>") })
            let text = AppCopy.text(key, args: args)
            for name in names {
                XCTAssertFalse(text.contains("{\(name)}"), "\(key.rawValue) kept {\(name)}")
                XCTAssertTrue(text.contains("<\(name)>"), "\(key.rawValue) dropped \(name)")
            }
        }
    }

    /// An argument nobody supplied stays visible as its placeholder. It is a
    /// programming mistake and must read as one — never as an empty gap in a
    /// sentence the user is asked to act on.
    func testAnArgumentThatIsNotSuppliedStaysAsItsPlaceholder() {
        let text = AppCopy.text(.planStayWearThis, args: ["spf": "SPF 30"])
        XCTAssertTrue(text.contains("SPF 30"))
        XCTAssertFalse(text.contains("{spf}"))
        XCTAssertTrue(text.contains("{window}"))
        XCTAssertTrue(text.contains("{application}"))
    }
}

/// The two non-keyed sections: the onboarding skin-type table and the quiz
/// behind it, both cited to Fitzpatrick 1988 (R28).
final class SkinTypeTableTests: XCTestCase {
    private static let title = "The validity and practicality of sun-reactive skin types I through VI"
    private static let doi = "10.1001/archderm.1988.01670060015008"

    private var parsed = AppCopyFixture.Parsed()

    override func setUpWithError() throws {
        parsed = try AppCopyFixture.parse(AppCopyFixture.document())
    }

    func testTheTableIsTheSixApprovedRowsInOrder() {
        XCTAssertEqual(parsed.skinRows.map(\.roman), AppCopyFixture.romanNumerals)
        XCTAssertEqual(SkinTypeTable.rows.map(\.type), SkinType.allCases)
        XCTAssertEqual(SkinTypeTable.rows.count, parsed.skinRows.count)
        for (row, approved) in zip(SkinTypeTable.rows, parsed.skinRows) {
            XCTAssertEqual(row.name, approved.name)
            XCTAssertEqual(row.description, approved.description)
            XCTAssertFalse(approved.description.isEmpty)
        }
    }

    func testEveryRowCitesFitzpatrick1988WithItsDOI() {
        for row in SkinTypeTable.rows {
            XCTAssertEqual(row.citation.authors, "Fitzpatrick TB")
            XCTAssertEqual(row.citation.title, Self.title)
            XCTAssertEqual(row.citation.venue, "Archives of Dermatology")
            XCTAssertEqual(row.citation.year, "1988")
            XCTAssertEqual(row.citation.identifier, .doi(Self.doi))
            XCTAssertFalse(row.citation.needsVerification)
            XCTAssertEqual(row.citation.link, URL(string: "https://doi.org/\(Self.doi)"))
        }
    }

    func testTheQuizIsTheTenApprovedQuestionsScoringZeroToFourInOrder() {
        XCTAssertEqual(parsed.quiz.count, 10)
        XCTAssertEqual(FitzpatrickQuiz.questions.map(\.id), Array(1 ... 10))
        XCTAssertEqual(FitzpatrickQuiz.questions.count, parsed.quiz.count)
        for (question, approved) in zip(FitzpatrickQuiz.questions, parsed.quiz) {
            XCTAssertEqual(question.id, approved.id)
            XCTAssertEqual(question.text, approved.text)
            XCTAssertEqual(approved.options.count, 5, "question \(approved.id)")
            XCTAssertEqual(question.options.map(\.text), approved.options)
            XCTAssertEqual(question.options.map(\.points), [0, 1, 2, 3, 4], "question \(approved.id)")
        }
    }

    /// The published bands, at both ends of each one.
    func testTheScoreBandsMapToTheApprovedSkinTypes() {
        let bands: [(score: Int, type: SkinType)] = [
            (0, .i), (6, .i),
            (7, .ii), (12, .ii),
            (13, .iii), (18, .iii),
            (19, .iv), (24, .iv),
            (25, .v), (30, .v),
            (31, .vi), (40, .vi),
        ]
        for band in bands {
            XCTAssertEqual(FitzpatrickQuiz.skinType(forScore: band.score), band.type, "score \(band.score)")
        }
    }
}
