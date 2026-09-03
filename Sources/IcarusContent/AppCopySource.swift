import Foundation
import IcarusCore

/// One key's text: the line every skin type gets, and the line that replaces it
/// for types I and II when the owner wrote one (R43).
public struct CopyEntry: Codable, Sendable, Equatable {
    public let base: String
    public let fair: String?

    public init(base: String, fair: String?) {
        self.base = base
        self.fair = fair
    }
}

/// One row of the onboarding skin-type table, as it is carried in the JSON.
/// The citation is not carried: it is one source for the whole table and lives
/// beside the table in `SkinTypeTable`.
public struct SkinTypeEntry: Codable, Sendable, Equatable {
    public let type: Int
    public let name: String
    public let description: String

    public init(type: Int, name: String, description: String) {
        self.type = type
        self.name = name
        self.description = description
    }
}

/// One answer of the Fitzpatrick questionnaire, with the points it scores.
public struct QuizOptionEntry: Codable, Sendable, Equatable {
    public let text: String
    public let points: Int

    public init(text: String, points: Int) {
        self.text = text
        self.points = points
    }
}

/// One question of the Fitzpatrick questionnaire, in the order it is asked.
public struct QuizQuestionEntry: Codable, Sendable, Equatable {
    public let id: Int
    public let text: String
    public let options: [QuizOptionEntry]

    public init(id: Int, text: String, options: [QuizOptionEntry]) {
        self.id = id
        self.text = text
        self.options = options
    }
}

/// `docs/APP_COPY.md`, as data. This is exactly what the generated
/// `Resources/app-copy.json` holds and what the app reads at runtime.
public struct AppCopyDocument: Codable, Sendable, Equatable {
    public let keys: [String: CopyEntry]
    public let skinTypes: [SkinTypeEntry]
    public let quiz: [QuizQuestionEntry]

    public init(keys: [String: CopyEntry], skinTypes: [SkinTypeEntry], quiz: [QuizQuestionEntry]) {
        self.keys = keys
        self.skinTypes = skinTypes
        self.quiz = quiz
    }
}

/// Every way the document can fail to be the contract. Each is loud: the
/// generator refuses to write a JSON file the app would then read as truth.
public enum AppCopySourceError: Error, Equatable {
    /// A `### ` heading outside the notification section that is not a `CopyKey`.
    case unknownKey(String)
    /// A key with a heading but no `- base:` line.
    case missingBase(String)
    /// `CopyKey` cases the document does not carry, sorted.
    case missingKeys([String])
    /// A table row under `## Skin types` that is not `| <roman> | name | text |`.
    case malformedSkinType(String)
    /// A numbered quiz line without its question, or without five answers.
    case malformedQuizLine(String)
    /// The six skin types or the ten questions are not all there.
    case incompleteTable(String)
}

/// Reading `docs/APP_COPY.md` — the single source of every non-Learn string
/// (R42, D-2026-09-03-F7).
///
/// The document is the owner's (S17) and nothing here edits a word of it: the
/// parser only cuts the file into keys, the skin-type table and the quiz.
/// `scripts/build-app-copy.sh` runs this and commits the JSON; `acceptance/S11.sh`
/// regenerates it and fails on any drift.
public enum AppCopySource {
    /// The section whose keys are approved wording for a later plan. They are
    /// not `CopyKey` cases yet, so they are skipped rather than rejected.
    static let deferredSection = "Notification texts"
    static let skinTypeSection = "Skin types"
    static let quizSection = "Fitzpatrick quiz"

    /// The number of answers every published question offers, scoring 0...4.
    static let quizOptionCount = 5

    public static func build(_ markdown: String) throws -> AppCopyDocument {
        var parser = Parser()
        for line in markdown.components(separatedBy: "\n") {
            try parser.take(line)
        }
        return try parser.finish()
    }

    // MARK: - The parser

    /// A line at a time, because the format is a line format: a `## ` heading
    /// opens a section, a `### ` heading opens a key, and everything else
    /// belongs to whichever of the two is open.
    private struct Parser {
        private var keys: [String: CopyEntry] = [:]
        private var skinTypes: [SkinTypeEntry] = []
        private var quiz: [QuizQuestionEntry] = []
        private var section = ""
        private var key: String?
        private var base: String?
        private var fair: String?

        mutating func take(_ rawLine: String) throws {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                try closeKey()
                section = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                return
            }
            if line.hasPrefix("### ") {
                try closeKey()
                try openKey(String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
                return
            }
            if key != nil {
                takeValue(line)
                return
            }
            if section == AppCopySource.skinTypeSection, line.hasPrefix("|") {
                if let row = try AppCopySource.skinTypeRow(line) {
                    skinTypes.append(row)
                }
            }
            if section == AppCopySource.quizSection {
                if let question = try AppCopySource.quizQuestion(line) {
                    quiz.append(question)
                }
            }
        }

        mutating func finish() throws -> AppCopyDocument {
            try closeKey()
            let missing = CopyKey.allCases.map(\.rawValue).filter { keys[$0] == nil }
            guard missing.isEmpty else { throw AppCopySourceError.missingKeys(missing.sorted()) }
            guard skinTypes.count == SkinType.allCases.count else {
                throw AppCopySourceError.incompleteTable("skin types: \(skinTypes.count)")
            }
            guard quiz.count == 10 else {
                throw AppCopySourceError.incompleteTable("quiz questions: \(quiz.count)")
            }
            return AppCopyDocument(keys: keys, skinTypes: skinTypes, quiz: quiz)
        }

        /// A heading in the deferred section opens nothing, so the lines under
        /// it are ignored rather than parsed as a key nobody declared.
        private mutating func openKey(_ heading: String) throws {
            base = nil
            fair = nil
            guard section != AppCopySource.deferredSection else {
                key = nil
                return
            }
            guard CopyKey(rawValue: heading) != nil else {
                throw AppCopySourceError.unknownKey(heading)
            }
            key = heading
        }

        private mutating func takeValue(_ line: String) {
            if let value = AppCopySource.value(after: "- base:", in: line) {
                base = value
            } else if let value = AppCopySource.value(after: "- fair:", in: line) {
                fair = value
            }
        }

        private mutating func closeKey() throws {
            defer {
                key = nil
                base = nil
                fair = nil
            }
            guard let key else { return }
            guard let base else { throw AppCopySourceError.missingBase(key) }
            keys[key] = CopyEntry(base: base, fair: fair)
        }
    }

    // MARK: - Lines

    private static func value(after marker: String, in line: String) -> String? {
        guard line.hasPrefix(marker) else { return nil }
        return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }

    /// `| I | Type I | text |`. The header and the separator row carry no roman
    /// numeral in their first cell, so they are skipped rather than rejected.
    private static func skinTypeRow(_ line: String) throws -> SkinTypeEntry? {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = cells.first, let type = romanNumerals[first] else { return nil }
        guard cells.count == 3 else { throw AppCopySourceError.malformedSkinType(line) }
        return SkinTypeEntry(type: type, name: cells[1], description: cells[2])
    }

    /// `N. question — answer | answer | answer | answer | answer`, scoring 0...4
    /// in the order written. A line that is not numbered is not a question.
    private static func quizQuestion(_ line: String) throws -> QuizQuestionEntry? {
        guard let dot = line.firstIndex(of: "."), let id = Int(line[line.startIndex ..< dot]) else { return nil }
        let rest = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        guard let split = rest.range(of: " — ") else { throw AppCopySourceError.malformedQuizLine(line) }
        let text = String(rest[rest.startIndex ..< split.lowerBound]).trimmingCharacters(in: .whitespaces)
        let answers = String(rest[split.upperBound...])
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard answers.count == quizOptionCount, !answers.contains(where: \.isEmpty) else {
            throw AppCopySourceError.malformedQuizLine(line)
        }
        return QuizQuestionEntry(
            id: id,
            text: text,
            options: answers.enumerated().map { QuizOptionEntry(text: $0.element, points: $0.offset) }
        )
    }

    private static let romanNumerals = ["I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6]
}
