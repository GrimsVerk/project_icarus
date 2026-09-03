import Foundation

/// A Learn module number, 1...12. Nothing outside that range exists, so the
/// initialisers are the range check and callers never carry an invalid id.
public struct ModuleID: RawRepresentable, Hashable, Codable, Sendable {
    /// The module numbers the Learn section has, in order.
    public static let range = 1 ... 12

    public let rawValue: Int

    public init?(rawValue: Int) {
        guard ModuleID.range.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public init?(_ raw: Int) {
        self.init(rawValue: raw)
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        guard let id = ModuleID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "module id \(raw) is outside 1...12")
            )
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ModuleID: ExpressibleByIntegerLiteral {
    /// Literals are for call sites that know the number is a real module — a
    /// deep link to module 6, say. An out-of-range literal is a programming
    /// error and traps; parsed input goes through `init?` instead.
    public init(integerLiteral value: Int) {
        guard let id = ModuleID(rawValue: value) else {
            preconditionFailure("module id \(value) is outside 1...12")
        }
        self = id
    }
}

extension ModuleID: CustomStringConvertible {
    public var description: String {
        String(rawValue)
    }
}

/// One Learn module: its heading, its body, and the citations in its
/// `> **Sources**` block.
public struct LearnModule: Sendable, Identifiable, Equatable {
    public let id: ModuleID
    /// The heading text after the em dash of "## Module N — Title".
    public let title: String
    /// The module body with `[VERIFY]` markers removed. The `> **Sources**`
    /// block is kept verbatim; stripping it is the renderer's job (slice 2).
    public let markdown: String
    public let citations: [Citation]

    public init(id: ModuleID, title: String, markdown: String, citations: [Citation]) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.citations = citations
    }

    /// Builds a module from the text of one `module-NN.md` file.
    ///
    /// The citations are parsed from the file text BEFORE the markers are
    /// stripped, which is how `needsVerification` survives with no sidecar
    /// file to keep in step (D-2026-09-03-F4).
    public init(id: ModuleID, fileText: String) {
        self.init(
            id: id,
            title: LearnSource.title(ofSection: fileText),
            markdown: LearnSource.normalise(fileText),
            citations: LearnSource.citations(inSection: fileText)
        )
    }
}

/// Errors the source document can produce when it is split.
public enum LearnSourceError: Error, Equatable {
    /// The document did not carry exactly twelve `## Module N — ` headings.
    case wrongModuleCount(Int)
    /// The headings were not 1...12 in order.
    case unexpectedModuleNumber(Int)
}

/// Reading `docs/LEARN_CONTENT.md` — the single source of the Learn text.
///
/// `split` is what the generator uses: it cuts the document into its twelve
/// sections verbatim, markers kept. `normalise` is what the loader and S7 use:
/// it removes exactly the build annotations (the `[VERIFY]` markers and the
/// preamble above Module 1) and whitespace, and nothing else. No text is ever
/// edited, paraphrased or summarised here (V5).
public enum LearnSource {
    /// The build annotation a citation carries when the owner must check it.
    public static let verificationMarker = "[VERIFY]"

    private static let headingPattern = #"^## Module (\d+) — "#

    /// Removes the build annotations and trailing whitespace.
    ///
    /// Exactly three things go: every `[VERIFY]` token with its surrounding
    /// backticks and the space before it, everything above the first
    /// "## Module 1 — " heading, and trailing whitespace on every line and at
    /// the end of the text. A module section carries no preamble, so for one
    /// section only the markers and the whitespace are affected.
    public static func normalise(_ text: String) -> String {
        var body = stripMarkers(text)

        if let start = body.range(of: #"(?m)^## Module 1 — "#, options: [.regularExpression]) {
            body = String(body[start.lowerBound...])
        }

        var lines = body.components(separatedBy: "\n").map { line in
            String(line.reversed().drop { $0 == " " || $0 == "\t" || $0 == "\r" }.reversed())
        }
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Cuts the document into its twelve module sections, verbatim.
    ///
    /// A section runs from its "## Module N — " heading up to the next module
    /// heading, without the `---` separator and blank lines that sit between
    /// them. `[VERIFY]` markers are kept: the generated files carry them and
    /// the loader is what strips them.
    public static func split(_ document: String) throws -> [(ModuleID, String)] {
        let lines = document.components(separatedBy: "\n")
        var headings: [(number: Int, line: Int)] = []
        for (index, line) in lines.enumerated() {
            guard let match = firstMatch(of: headingPattern, in: line, groups: 1),
                  let number = Int(match[0]) else { continue }
            headings.append((number, index))
        }

        guard headings.count == 12 else { throw LearnSourceError.wrongModuleCount(headings.count) }

        var sections: [(ModuleID, String)] = []
        for (offset, heading) in headings.enumerated() {
            guard heading.number == offset + 1, let id = ModuleID(rawValue: heading.number) else {
                throw LearnSourceError.unexpectedModuleNumber(heading.number)
            }
            let end = offset + 1 < headings.count ? headings[offset + 1].line : lines.count
            var section = Array(lines[heading.line ..< end])
            while let last = section.last, isSectionSeparator(last) {
                section.removeLast()
            }
            sections.append((id, section.joined(separator: "\n")))
        }
        return sections
    }

    /// A blank line or the `---` rule that sits between two module sections.
    private static func isSectionSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "---"
    }

    /// The heading text after the em dash of the section's first line.
    static func title(ofSection section: String) -> String {
        guard let heading = section.components(separatedBy: "\n").first,
              let dash = heading.range(of: " — ") else { return "" }
        return String(heading[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// Every `> - ` line under a `> **Sources**` block, in source order.
    static func citations(inSection section: String) -> [Citation] {
        var citations: [Citation] = []
        var inSources = false
        for rawLine in section.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("> **Sources**") {
                inSources = true
            } else if inSources, line.hasPrefix("> - ") {
                citations.append(Citation(sourceLine: String(line.dropFirst(4))))
            } else if inSources, !line.hasPrefix(">") {
                inSources = false
            }
        }
        return citations
    }

    /// Removes every `[VERIFY]` token, with its backticks and the space before.
    static func stripMarkers(_ text: String) -> String {
        var stripped = text
        for token in [
            " `\(verificationMarker)`",
            "`\(verificationMarker)`",
            " \(verificationMarker)",
            verificationMarker,
        ] {
            stripped = stripped.replacingOccurrences(of: token, with: "")
        }
        return stripped
    }

    /// The capture groups of the first match, or nil when nothing matches.
    static func firstMatch(of pattern: String, in text: String, groups: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var captures: [String] = []
        for group in 1 ... groups {
            guard let groupRange = Range(match.range(at: group), in: text) else { return nil }
            captures.append(String(text[groupRange]))
        }
        return captures
    }
}
