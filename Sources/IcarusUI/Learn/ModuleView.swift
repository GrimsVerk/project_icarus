#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import MarkdownUI
    import SwiftUI

    /// One Learn module: its text, then its citations.
    ///
    /// The text is rendered by MarkdownUI, which renders the tables and the
    /// blockquotes two of the modules carry (D-2026-09-03-DEP1). The sources
    /// blockquote is not part of that text — `ModuleRenderModel` removes it — so
    /// each citation arrives as a row of its own and can be tapped (R26).
    ///
    /// It carries no banner: R39 puts the Learn banner under the module list and
    /// nowhere else, and it shows no figure the user could act on.
    public struct ModuleView: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = false
        public nonisolated static let showsFigures = false

        private let title: String
        private let render: ModuleRenderModel

        public init(module: LearnModule) {
            title = module.title
            render = ModuleRenderModel(module: module)
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Markdown(render.body)
                        .markdownTheme(.icarus)
                    ForEach(render.citations, id: \.self) { citation in
                        CitationRow(citation: citation)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            // The module's own heading, which is Learn content and not app copy.
            .navigationTitle(title)
        }
    }
#endif
