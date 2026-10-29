import Foundation
import IcarusCore

/// One row of the onboarding skin-type table: the type, its name, the plain
/// description the user picks from, and the source that description follows.
public struct SkinTypeRow: Sendable, Equatable {
    public let type: SkinType
    public let name: String
    public let description: String
    public let citation: Citation

    public init(type: SkinType, name: String, description: String, citation: Citation) {
        self.type = type
        self.name = name
        self.description = description
        self.citation = citation
    }
}

/// The onboarding table (R28). It is the app's own copy, written to V13 and
/// approved with the rest of `docs/APP_COPY.md`; Module 4's table is Learn copy
/// and stays verbatim under V5, so the two are deliberately separate.
public enum SkinTypeTable {
    public static let rows: [SkinTypeRow] = AppCopy.document.skinTypes.map { entry in
        guard let type = SkinType(rawValue: entry.type) else {
            preconditionFailure("skin type \(entry.type) is outside I...VI")
        }
        return SkinTypeRow(
            type: type,
            name: entry.name,
            description: entry.description,
            citation: fitzpatrick1988
        )
    }

    public static func row(for type: SkinType) -> SkinTypeRow? {
        rows.first { $0.type == type }
    }

    /// The one source behind the table and the quiz alike.
    public static let fitzpatrick1988 = Citation(
        authors: "Fitzpatrick TB",
        title: "The validity and practicality of sun-reactive skin types I through VI",
        venue: "Archives of Dermatology",
        year: "1988",
        identifier: .doi("10.1001/archderm.1988.01670060015008"),
        needsVerification: false
    )
}

/// One answer of the questionnaire and what it scores.
public struct QuizOption: Sendable, Equatable {
    public let text: String
    public let points: Int

    public init(text: String, points: Int) {
        self.text = text
        self.points = points
    }
}

/// One question, with its answers in the published order.
public struct QuizQuestion: Sendable, Equatable {
    public let id: Int
    public let text: String
    public let options: [QuizOption]

    public init(id: Int, text: String, options: [QuizOption]) {
        self.id = id
        self.text = text
        self.options = options
    }
}

/// The optional Fitzpatrick questionnaire and its published scoring bands (R28).
///
/// The questions, the bands and the citation live here rather than in a view,
/// so the onboarding screen only asks them.
public enum FitzpatrickQuiz {
    public static let questions: [QuizQuestion] = AppCopy.document.quiz.map { question in
        QuizQuestion(
            id: question.id,
            text: question.text,
            options: question.options.map { QuizOption(text: $0.text, points: $0.points) }
        )
    }

    /// The source the questions and the bands come from.
    public static let citation = SkinTypeTable.fitzpatrick1988

    /// The type a total score falls in: 0–6 I, 7–12 II, 13–18 III, 19–24 IV,
    /// 25–30 V, 31 and above VI. A score below zero cannot happen — every
    /// answer scores at least nothing — and reads as the most sensitive band.
    public static func skinType(forScore score: Int) -> SkinType {
        switch score {
        case ..<7: .i
        case 7 ... 12: .ii
        case 13 ... 18: .iii
        case 19 ... 24: .iv
        case 25 ... 30: .v
        default: .vi
        }
    }
}
