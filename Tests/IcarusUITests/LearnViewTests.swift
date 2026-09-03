#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    @testable import IcarusUI
    import XCTest

    /// Slice 2 of `learn-tab`, asserted without rendering a view.
    ///
    /// Two things are testable off the screen. `ModuleRenderModel` is the split
    /// between what MarkdownUI draws and what `CitationRow` draws, so S7's
    /// promises about the rendered module — the table survives, the
    /// `> **Sources**` block does not, and no citation is dropped or
    /// duplicated (R26) — are assertions about a value. And a screen's banner
    /// declaration is static (R39, S15), so `LearnListView` and `ModuleView`
    /// can be checked against `ScreenTable` without building either one.
    ///
    /// Nothing here renders: a view test would need a host application, and
    /// every promise the slice makes is reachable without one.
    final class LearnViewTests: XCTestCase {
        // MARK: - Fixtures

        /// The module with the skin-type table (R26: "Markdown renders
        /// including tables").
        private static let tableModule = 4
        /// The module whose sources carry an ISO number, a plain URL and two
        /// DOIs — the mix `CitationRow` has to render two different ways.
        private static let mixedCitationModule = 3
        /// The two modules of `docs/LEARN_CONTENT.md` that carry no
        /// `> **Sources**` block at all.
        private static let modulesWithoutSources = [9, 11]

        private func module(_ number: Int) throws -> LearnModule {
            let id = try XCTUnwrap(ModuleID(number), "module \(number) is outside 1...12")
            return try XCTUnwrap(ModuleIndex.module(id), "module \(number) did not load")
        }

        private func render(_ number: Int) throws -> ModuleRenderModel {
            try ModuleRenderModel(module: module(number))
        }

        // MARK: - The table module renders as a table

        /// The reason MarkdownUI is a dependency at all (D-2026-09-03-DEP1):
        /// module 4's MED table has to reach the renderer intact.
        func testTheTableModuleKeepsItsMarkdownTable() throws {
            let body = try render(Self.tableModule).body
            XCTAssertTrue(body.contains("|---"), "the table's delimiter row was lost")
            XCTAssertTrue(body.contains("| Skin type | Typical description | Approx. MED |"))
            XCTAssertTrue(body.contains("| I | Always burns, never tans | ~2 SED |"))
            XCTAssertTrue(body.contains("| VI | Never burns | ~10 SED |"))
        }

        /// The Sources block is `CitationRow`'s data, so it must not also be
        /// drawn as a blockquote above the rows.
        func testTheTableModuleBodyDropsItsSourcesBlock() throws {
            let body = try render(Self.tableModule).body
            XCTAssertFalse(body.contains("**Sources**"))
            XCTAssertFalse(body.contains("Diffey BL, Jansén CT, Urbach F, Wulf HC"))
            XCTAssertFalse(body.contains("https://doi.org/10.1001/archderm.1988.01670060015008"))
            XCTAssertFalse(body.contains("International Organization for Standardization"))
        }

        /// Only the Sources blockquote goes. Module 4 carries a second
        /// blockquote — the minutes-per-SED formula — in the middle of its
        /// prose, and removing every `>` line would take that with it.
        func testTheTableModuleKeepsTheBlockquoteThatIsNotSources() throws {
            let body = try render(Self.tableModule).body
            XCTAssertTrue(
                body.contains("> **Minutes to reach 1 SED = 66.7 ÷ UV Index**"),
                "a blockquote that is not the Sources block was removed"
            )
        }

        /// What is left ends at the prose, with the blank line that separated
        /// it from the Sources block trimmed away.
        func testTheTableModuleBodyEndsAtItsLastProseLine() throws {
            let body = try render(Self.tableModule).body
            XCTAssertTrue(
                body.hasSuffix("`2.5 × 66.7 ÷ 7 ≈ 24 minutes`."),
                "body ended at \(String(body.suffix(40)).debugDescription)"
            )
        }

        /// Removing the block from the body never removes the citations: the
        /// three sources of module 4 are still there to render as rows.
        func testTheTableModuleKeepsItsThreeCitations() throws {
            let model = try render(Self.tableModule)
            XCTAssertEqual(model.citations.count, 3)
            XCTAssertEqual(model.citations, try module(Self.tableModule).citations)
        }

        // MARK: - Citations reach the rows unchanged

        /// S7's count promise, stated against the source rather than against a
        /// number this test made up.
        func testTheMixedModuleCitationCountEqualsTheSources() throws {
            let module = try module(Self.mixedCitationModule)
            XCTAssertEqual(try render(Self.mixedCitationModule).citations.count, module.citations.count)
            XCTAssertEqual(module.citations.count, 4, "module 3 has four source lines")
        }

        /// R26: never assigned an identifier the source does not carry, and
        /// never dropped for lack of one. The render model is a passthrough,
        /// so both kinds arrive at `CitationRow` — the ones that make a `Link`
        /// and the ones that can only be `Text`.
        func testTheMixedModuleCitationsArriveInSourceOrderWithTheirIdentifiers() throws {
            let citations = try render(Self.mixedCitationModule).citations
            XCTAssertEqual(citations, try module(Self.mixedCitationModule).citations)

            let linkable = citations.filter { $0.link != nil }
            let textOnly = citations.filter { $0.link == nil }
            XCTAssertEqual(textOnly.count, 1, "the McKinlay ISO line is the one without a link")
            let isoOnly = try XCTUnwrap(textOnly.first)
            XCTAssertEqual(isoOnly.identifier, CitationIdentifier.iso("17166:1999"))
            XCTAssertEqual(linkable.count, 3, "two DOIs and the WHO URL are tappable")
        }

        /// The prose stays, the sources go — no paraphrase either way (V5).
        func testTheMixedModuleBodyKeepsItsProseAndDropsItsSources() throws {
            let body = try render(Self.mixedCitationModule).body
            XCTAssertTrue(body.contains("It is a **worse ratio**"))
            XCTAssertTrue(body.contains("**One important caveat about the UV Index.**"))
            XCTAssertFalse(body.contains("**Sources**"))
            XCTAssertFalse(body.contains("McKinlay AF, Diffey BL"))
            XCTAssertFalse(body.contains("World Health Organization"))
        }

        // MARK: - Every module

        /// The body is the module's own markdown with a block taken off the
        /// end — never rewritten, reordered, or re-wrapped (R26, V5).
        func testEveryModuleBodyIsAPrefixOfItsMarkdown() {
            for module in ModuleIndex.all {
                let body = ModuleRenderModel(module: module).body
                XCTAssertFalse(body.isEmpty, "module \(module.id) rendered nothing")
                XCTAssertTrue(
                    module.markdown.hasPrefix(body),
                    "module \(module.id) body is not the head of its markdown"
                )
            }
        }

        /// Stated exactly, for all twelve: everything up to the `> **Sources**`
        /// line, minus the quoted lines that follow it, minus trailing blanks.
        func testEveryModuleBodyIsTheMarkdownUpToItsSourcesBlock() {
            for module in ModuleIndex.all {
                XCTAssertEqual(
                    ModuleRenderModel(module: module).body,
                    Self.markdownWithoutSources(module.markdown),
                    "module \(module.id)"
                )
            }
        }

        /// No module leaves a source line behind in the body — not the header,
        /// not a `> - ` entry. The two blockquotes that are not sources
        /// (modules 4 and 8) are the reason this checks the list marker rather
        /// than every quoted line.
        func testNoModuleBodyKeepsASourceLine() {
            for module in ModuleIndex.all {
                let body = ModuleRenderModel(module: module).body
                XCTAssertFalse(body.contains("**Sources**"), "module \(module.id) kept the Sources header")
                let quotedEntries = body
                    .components(separatedBy: "\n")
                    .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("> - ") }
                XCTAssertTrue(quotedEntries.isEmpty, "module \(module.id) kept \(quotedEntries)")
            }
        }

        /// The body is handed to MarkdownUI, so it carries no trailing blank
        /// line to render as space at the foot of the screen.
        func testNoModuleBodyEndsInWhitespace() {
            for module in ModuleIndex.all {
                let body = ModuleRenderModel(module: module).body
                XCTAssertEqual(
                    body,
                    Self.trimmingTrailingWhitespace(body),
                    "module \(module.id) body ends in whitespace"
                )
            }
        }

        /// R26 again, over the whole set: every citation the module carries is
        /// present, once, in the order the source gives.
        func testEveryModuleKeepsEveryCitationExactlyOnce() {
            for module in ModuleIndex.all {
                let citations = ModuleRenderModel(module: module).citations
                XCTAssertEqual(citations, module.citations, "module \(module.id) changed its citations")
                for citation in module.citations {
                    XCTAssertEqual(
                        citations.filter { $0 == citation }.count,
                        1,
                        "module \(module.id) does not carry \(citation.title) exactly once"
                    )
                }
            }
        }

        /// Every module has a heading, and the render model keeps it: the
        /// module screen's own title line is part of the markdown.
        func testEveryModuleBodyStartsWithItsHeading() {
            for module in ModuleIndex.all {
                let body = ModuleRenderModel(module: module).body
                XCTAssertTrue(
                    body.hasPrefix("## Module \(module.id.rawValue) — "),
                    "module \(module.id) lost its heading"
                )
            }
        }

        /// The edge the removal rule has to survive: two modules have no
        /// Sources block. Their body is the markdown untouched, and their
        /// citation list is empty rather than wrong.
        func testModulesWithoutASourcesBlockAreLeftAlone() throws {
            for number in Self.modulesWithoutSources {
                let module = try module(number)
                let model = ModuleRenderModel(module: module)
                XCTAssertEqual(model.body, module.markdown, "module \(number) body was changed")
                XCTAssertTrue(model.citations.isEmpty, "module \(number) invented citations")
            }
        }

        /// The model is a value: the same module gives the same model, and two
        /// modules do not.
        func testTheRenderModelIsEqualForTheSameModule() throws {
            let module = try module(Self.tableModule)
            XCTAssertEqual(ModuleRenderModel(module: module), ModuleRenderModel(module: module))
            XCTAssertNotEqual(
                ModuleRenderModel(module: module),
                try ModuleRenderModel(module: self.module(Self.mixedCitationModule))
            )
        }

        // MARK: - The two screens declare their slots (R39, S15)

        /// The Learn list is one of the two screens that carry the banner, and
        /// it shows no figure the user could act on.
        func testTheLearnListDeclaresTheBannerSlotAndNoFigures() {
            XCTAssertTrue(LearnListView.hasBannerSlot)
            XCTAssertFalse(LearnListView.showsFigures)
        }

        /// A module screen is prose. No banner under it, no figures on it.
        func testTheModuleScreenDeclaresNeitherSlot() {
            XCTAssertFalse(ModuleView.hasBannerSlot)
            XCTAssertFalse(ModuleView.showsFigures)
        }

        /// The declaration and the table have to agree, or the table stops
        /// being the thing R39 is checked against.
        func testEachLearnScreenAgreesWithItsRowInTheTable() throws {
            let list = try XCTUnwrap(ScreenTable.row("LearnListView"))
            XCTAssertEqual(list.hasBanner, LearnListView.hasBannerSlot)
            XCTAssertEqual(list.showsFigures, LearnListView.showsFigures)
            XCTAssertTrue(list.hasBanner)
            XCTAssertFalse(list.showsFigures)

            let moduleRow = try XCTUnwrap(ScreenTable.row("ModuleView"))
            XCTAssertEqual(moduleRow.hasBanner, ModuleView.hasBannerSlot)
            XCTAssertEqual(moduleRow.showsFigures, ModuleView.showsFigures)
            XCTAssertFalse(moduleRow.hasBanner)
            XCTAssertFalse(moduleRow.showsFigures)
        }

        /// The banner sits under the module list only — never under a module.
        func testTheLearnListIsTheOnlyLearnScreenWithABanner() {
            XCTAssertTrue(LearnListView.hasBannerSlot && !ModuleView.hasBannerSlot)
        }

        // MARK: - What the slice promised, restated

        /// The removal rule, written out: drop the `> **Sources**` line and the
        /// quoted lines that follow it up to the first unquoted line, then trim
        /// the trailing blanks. Kept here so a disagreement with the
        /// implementation shows up as a difference in text, not in behaviour
        /// nobody can see.
        private static func markdownWithoutSources(_ markdown: String) -> String {
            var kept: [String] = []
            var dropping = false
            for line in markdown.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("> **Sources**") {
                    dropping = true
                    continue
                }
                if dropping {
                    if trimmed.hasPrefix(">") {
                        continue
                    }
                    dropping = false
                }
                kept.append(line)
            }
            while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                kept.removeLast()
            }
            return kept.joined(separator: "\n")
        }

        private static func trimmingTrailingWhitespace(_ text: String) -> String {
            var trimmed = text
            while let last = trimmed.last, last.isWhitespace || last.isNewline {
                trimmed.removeLast()
            }
            return trimmed
        }
    }
#endif
