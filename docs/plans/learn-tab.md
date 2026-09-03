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
Slice 1 (content only) lands BEFORE `calculator-ui` Slice 2, which needs
`ModuleIndex`; Slice 2 (views) can follow M3. Revision 2 lands the tactical review.

Non-goals:
- We do NOT edit, paraphrase, or summarise any Learn text (V5).
- We do NOT verify the citations here; S13 is the owner's, with the report in `docs/reviews/citations.md`.
- We do NOT track reading progress.

Owner costs:
- S13: check every `[VERIFY]` and addendum-flagged citation before release.

Rulings: D-2026-09-03-F4, F5 (docs/DECISIONS.md); design revision 2 for markers and identifiers

## The slices

Module files (ruled D-2026-09-03-F4): `scripts/split-learn-content.sh`
generates `Sources/IcarusContent/Resources/Learn/module-NN.md` from
`docs/LEARN_CONTENT.md`; the generated files are committed and S7 fails if
they drift from the source. One source of truth. The script only splits: the
module files keep `[VERIFY]` verbatim and `LearnModule` strips it at load,
setting `needsVerification` from what it stripped (no sidecar; tactical #26).

## Slice 1 — Modules as data, with citations parsed and markers stripped

- **Delivers:** `ModuleIndex.all` lists twelve `LearnModule`s loaded from bundled markdown; each exposes its title, body (markers stripped at load), and parsed `Citation`s with the identifier kind the source carries and `needsVerification` set from the marker the loader stripped; the split script regenerates the files byte-identically and S7 proves the rendered text equals the source section after normalisation. Content only, no views: `calculator-ui` Slice 2 depends on this slice.
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
    public static func normalise(_ text: String) -> String      // strips `[VERIFY]` tokens (with surrounding backticks), the preamble above Module 1, trailing whitespace
    public static func split(_ document: String) throws -> [(ModuleID, String)]   // exactly 12 sections at "^## Module N — "; verbatim, markers kept
}
// Promises (S7): all.count == 12; titles match the source headings; for every module, normalise(sourceSection) == module.markdown;
//  every citation line in the source appears in citations with its identifier kind (Routaboul → .pmid("10066941"); McKinlay → .none; WHO → .url); none dropped;
//  deepLink(3) → icarus://learn/3; module(ModuleID(13)) == nil
```

### Internals

```text
scripts/split-learn-content.sh: `swift run split-learn-content docs/LEARN_CONTENT.md Sources/IcarusContent/Resources/Learn` (a tiny executable target calling LearnSource.split) — sections written verbatim with `[VERIFY]` kept; fails if not exactly 12
LearnModule loader: markdown = normalise(fileText); citations parsed from the file text BEFORE stripping so needsVerification = line contained [VERIFY]
Citation parser: for lines under "> **Sources**" starting "> - ": authors up to first ". *"; title between *…*; venue/year after; identifier by regex: https://doi.org/(.+) | PMID (\d+) | ISO \d+ | https?://…
acceptance/S7-learn.sh: regenerate into a temp dir, diff byte-for-byte against Sources/…/Learn; then `swift test --filter IcarusContentTests`
```

## Slice 2 — The Learn tab: list, markdown with tables, tappable citations, deep links

- **Delivers:** A Learn tab lists the twelve modules; a module screen renders its markdown with MarkdownUI including tables and blockquotes; each citation is a tappable row that opens its DOI or PubMed link and shows the identifier as text otherwise; `icarus://learn/<n>` opens that module from anywhere; the banner slot sits under the module list only.
- **Files:** `Sources/IcarusUI/Learn/LearnListView.swift`, `Sources/IcarusUI/Learn/ModuleView.swift`, `Sources/IcarusUI/Learn/CitationRow.swift`, `Sources/IcarusUI/Navigation/DeepLink.swift`, `Tests/IcarusUITests/LearnViewTests.swift`, `Package.swift`
- **Estimate:** ~340 lines

### Signatures

```text
public struct LearnListView: View, ScreenManifest { public init(adBanner: AnyView?) }   // (true, false): the only Learn screen with a banner slot
public struct ModuleView: View, ScreenManifest { public init(module: LearnModule) }        // (false, false)
public struct ModuleRenderModel: Sendable, Equatable { public let body: String; public let citations: [Citation]; public init(module: LearnModule) }
    // body = markdown with the "> **Sources**" block removed; testable without rendering: contains a table for module 4 ("|---" present), and every citation appears exactly once
public struct CitationRow: View { public init(citation: Citation) }            // Link when identifier has a URL; Text otherwise; never hides a citation
public enum DeepLink: Sendable, Equatable { case learn(ModuleID); public init?(url: URL); public var url: URL }
// Package.swift: IcarusUI adds dependency .product("MarkdownUI", package: "swift-markdown-ui") pinned exact 2.4.1
// Promises (S7, S15): ModuleRenderModel(module 4).body contains a markdown table and no Sources block; ModuleRenderModel(module 3).citations.count == the source's; DeepLink(url: "icarus://learn/6") == .learn(6); ScreenTable rows for LearnListView (true, false) and ModuleView (false, false)
```

### Internals

```text
ModuleView: ScrollView { Markdown(module.markdown).markdownTheme(.icarus) ; ForEach(citations) CitationRow }  — the Sources blockquote is rendered by Markdown AND listed as rows? NO: strip the "> **Sources**" block from the Markdown body at render time and render CitationRows in its place, so each is tappable; the stored markdown keeps it (S7 compares stored text)
CitationRow: identifier.url != nil → Link(destination) { authors, title, venue } else HStack { text; identifier text }
DeepLink: URL scheme icarus, host learn, path /<n>; App target registers the scheme (M3 App/Info) and routes to the Learn tab
```
