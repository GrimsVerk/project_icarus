---
slug: learn-tab
status: draft
created: 2026-09-02
design: M4 — Learn
covers: [R26, R27]
format: pseudocode
---

# Learn tab — Plan

## Summary

The twelve Learn modules as data, one file each, generated from
`docs/LEARN_CONTENT.md` by a script so the document stays the single source;
a citation model that keeps every identifier as given; a Learn tab that
renders markdown with tables and tappable citations; deep links the result
screen can use. `[VERIFY]` markers and the preamble are never rendered.

Non-goals:
- We do NOT edit, paraphrase, or summarise any Learn text (V5).
- We do NOT verify the citations here; S13 is the owner's, with the report in `docs/reviews/citations.md`.
- We do NOT track reading progress.

Owner costs:
- S13: check every `[VERIFY]` and addendum-flagged citation before release.

Rulings: D-2026-09-02 revision 2 (markers never rendered; non-DOI identifiers as given; MarkdownUI)

## The slices

FORK F4 (structural, batch): module files. TRUNK — `scripts/split-learn-content.sh`
generates `Sources/IcarusContent/Resources/Learn/module-NN.md` from
`docs/LEARN_CONTENT.md`; the generated files are committed and S7 fails if
they drift from the source. Alternative — hand-split files edited directly,
with the design document as a mirror. The trunk keeps one source of truth
and makes "edit one module" a one-section edit in one document.

## Slice 1 — Modules as data, with citations parsed and markers stripped

- **Delivers:** `ModuleIndex.all` lists twelve `LearnModule`s loaded from bundled markdown; each exposes its title, body (markers and preamble stripped), and parsed `Citation`s with the identifier kind the source carries; the split script regenerates the files and S7 proves the text equals the source section after normalisation.
- **Files:** `scripts/split-learn-content.sh`, `Sources/IcarusContent/Resources/Learn/module-01.md` … `module-12.md`, `Sources/IcarusContent/LearnModule.swift`, `Sources/IcarusContent/ModuleIndex.swift`, `Sources/IcarusContent/Citation.swift`, `Tests/IcarusContentTests/ModuleIndexTests.swift`, `Tests/IcarusContentTests/CitationTests.swift`, `acceptance/S7-learn.sh`
- **Estimate:** ~380 lines

### Signatures

```text
public struct LearnModule: Sendable, Identifiable, Equatable {
    public let id: ModuleID              // 1...12
    public let title: String             // the "## Module N — Title" text after the dash
    public let markdown: String          // body with [VERIFY] markers removed; the "> **Sources**" block retained verbatim
    public let citations: [Citation]
}
public struct ModuleID: RawRepresentable, Hashable, Codable, Sendable { public let rawValue: Int }
public struct Citation: Sendable, Equatable {
    public let authors: String; public let title: String; public let venue: String; public let year: String?
    public let identifier: CitationIdentifier
    public let needsVerification: Bool    // true when the source line carried [VERIFY]
}
public enum CitationIdentifier: Sendable, Equatable { case doi(String), pmid(String), iso(String), url(URL), none }
    // link: doi → https://doi.org/<doi>; pmid → https://pubmed.ncbi.nlm.nih.gov/<pmid>/; iso/none → no link
public enum ModuleIndex {
    public static let all: [LearnModule]                        // loaded once from Bundle.module
    public static func module(_ id: ModuleID) -> LearnModule?
    public static func deepLink(_ id: ModuleID) -> URL          // icarus://learn/<n>
}
public enum LearnSource {
    public static func normalise(_ text: String) -> String      // strips [VERIFY] (with surrounding backticks), the preamble above Module 1, trailing whitespace
}
// Promises (S7): all.count == 12; titles match the source headings; for every module, normalise(sourceSection) == module.markdown;
//  every citation line in the source appears in citations with its identifier kind (Routaboul → .pmid("10066941"); McKinlay → .none; WHO → .url); none dropped;
//  deepLink(3) → icarus://learn/3; module(ModuleID(13)) == nil
```

### Internals

```text
scripts/split-learn-content.sh: awk over docs/LEARN_CONTENT.md: drop everything before "## Module 1"; split at "^## Module "; write module-NN.md with the heading kept; remove `[VERIFY]` tokens; fail if not exactly 12
Citation parser: for lines under "> **Sources**" starting "> - ": authors up to first ". *"; title between *…*; venue/year after; identifier by regex: https://doi.org/(.+) | PMID (\d+) | ISO \d+ | https?://… ; needsVerification if the line had [VERIFY] in the SOURCE (the script records a sidecar module-NN.verify.json listing citation indexes before stripping)
acceptance/S7-learn.sh: regenerate into a temp dir with the script, diff against Sources/…/Learn; then `swift test --filter IcarusContentTests`
```

## Slice 2 — The Learn tab: list, markdown with tables, tappable citations, deep links

- **Delivers:** A Learn tab lists the twelve modules; a module screen renders its markdown with MarkdownUI including tables and blockquotes; each citation is a tappable row that opens its DOI or PubMed link and shows the identifier as text otherwise; `icarus://learn/<n>` opens that module from anywhere; the banner slot sits under the module list only.
- **Files:** `Sources/IcarusUI/Learn/LearnListView.swift`, `Sources/IcarusUI/Learn/ModuleView.swift`, `Sources/IcarusUI/Learn/CitationRow.swift`, `Sources/IcarusUI/Navigation/DeepLink.swift`, `Tests/IcarusUITests/LearnViewTests.swift`, `Package.swift`
- **Estimate:** ~340 lines

### Signatures

```text
public struct LearnListView: View { public init(adBanner: AnyView?) }          // the only Learn screen with a banner slot
public struct ModuleView: View { public init(module: LearnModule) }
public struct CitationRow: View { public init(citation: Citation) }            // Link when identifier has a URL; Text otherwise; never hides a citation
public enum DeepLink: Sendable, Equatable { case learn(ModuleID); public init?(url: URL); public var url: URL }
// Package.swift: IcarusUI adds dependency .product("MarkdownUI", package: "swift-markdown-ui") pinned exact 2.4.1
// Promises (S7, S15): LearnListView renders 12 rows; ModuleView for module 4 renders a table (MarkdownUI Table node present); every citation of module 3 has a row; DeepLink(url: "icarus://learn/6") == .learn(6); ModuleView contains no banner slot
```

### Internals

```text
ModuleView: ScrollView { Markdown(module.markdown).markdownTheme(.icarus) ; ForEach(citations) CitationRow }  — the Sources blockquote is rendered by Markdown AND listed as rows? NO: strip the "> **Sources**" block from the Markdown body at render time and render CitationRows in its place, so each is tappable; the stored markdown keeps it (S7 compares stored text)
CitationRow: identifier.url != nil → Link(destination) { authors, title, venue } else HStack { text; identifier text }
DeepLink: URL scheme icarus, host learn, path /<n>; App target registers the scheme (M3 App/Info) and routes to the Learn tab
```
