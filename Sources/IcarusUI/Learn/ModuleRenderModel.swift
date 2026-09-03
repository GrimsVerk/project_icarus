#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import MarkdownUI
    import SwiftUI

    /// What a module screen renders: the body markdown, and the citations as
    /// data rather than as text inside it.
    ///
    /// The stored module keeps its `> **Sources**` blockquote verbatim, because
    /// S7 compares the stored text against `docs/LEARN_CONTENT.md` and a
    /// renderer that edited the store would break that comparison. So the block
    /// is removed here, at render time, and the citations it held are shown in
    /// its place as `CitationRow`s — which is what makes each one tappable
    /// (R26). Nothing else in the text is touched: no word is edited,
    /// paraphrased or summarised (V5).
    ///
    /// This is a value, not a view, so every promise about what reaches the
    /// screen can be asserted without rendering anything.
    public struct ModuleRenderModel: Sendable, Equatable {
        /// The module markdown with the `> **Sources**` block removed.
        ///
        /// Only that one blockquote goes. A module may carry other blockquotes —
        /// module 4's minutes-to-one-SED formula is one — and they stay.
        public let body: String

        /// The module's citations, in source order, exactly as parsed. None is
        /// dropped, reordered, or given an identifier the source does not carry.
        public let citations: [Citation]

        public init(module: LearnModule) {
            body = ModuleRenderModel.stripSources(from: module.markdown)
            citations = module.citations
        }

        /// The prefix that opens the sources blockquote in every module file.
        private static let sourcesHeading = "> **Sources**"

        /// Drops the sources blockquote and the whitespace it leaves behind.
        ///
        /// The block runs from its heading line to the first line that is not a
        /// quote, so a `> - ` line belongs to it and the blank line after it ends
        /// it. Trailing blank lines are then removed, so a body that ended with
        /// the block does not end with a hole where it was.
        private static func stripSources(from markdown: String) -> String {
            var kept: [String] = []
            var inSources = false
            for line in markdown.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(sourcesHeading) {
                    inSources = true
                    continue
                }
                if inSources {
                    if trimmed.hasPrefix(">") {
                        continue
                    }
                    inSources = false
                }
                kept.append(line)
            }
            while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                kept.removeLast()
            }
            return kept.joined(separator: "\n")
        }
    }

    public extension Theme {
        /// The Learn tab's markdown theme.
        ///
        /// GitHub's theme is the starting point because it is the one MarkdownUI
        /// ships that styles tables, and two modules carry a table — the reason
        /// this dependency exists at all (D-2026-09-03-DEP1). Nothing is
        /// overridden: the app has no typographic decision of its own to make
        /// here yet, and a theme that only renames someone else's is honest
        /// about that.
        static var icarus: Theme {
            .gitHub
        }
    }
#endif
