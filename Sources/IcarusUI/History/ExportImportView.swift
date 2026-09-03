#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI
    import UniformTypeIdentifiers

    /// The export and the import, as History's own two actions (R25, S10).
    ///
    /// Export writes the whole record — every session's stored curve, the
    /// profile, and the constant set it was written under — to a temporary JSON
    /// file and hands that file to the system share sheet. Import takes a file
    /// back through the same format, and the file the export writes is exactly
    /// the file the import accepts.
    ///
    /// An import is all or nothing: `ExportService` validates every record
    /// before it writes any of them, so a corrupt file leaves the history
    /// exactly as it was and the user is told so. The profile the file carried
    /// is applied with it, because a record replayed under a different profile
    /// is not the record that was exported.
    ///
    /// The work lives in `ExportImportModel` beside the view so it can be tested
    /// without rendering anything.
    @MainActor
    public final class ExportImportModel: ObservableObject {
        /// Why the last import did not happen, or nil when the last one did.
        @Published public var lastError: Error?

        /// What the last import landed. Cleared when an import fails, so the
        /// screen can never report a summary from an earlier file.
        @Published public private(set) var lastSummary: ImportSummary?

        private let env: AppEnvironment

        public init(env: AppEnvironment) {
            self.env = env
        }

        /// The whole record as a file on disk, ready to be shared.
        ///
        /// The file is written into the temporary directory under a name stamped
        /// with the moment it was taken: two exports in one session are two
        /// files, and the system clears them up.
        ///
        /// Before onboarding has saved a profile there is still a profile the
        /// app replays under — the conservative starting one — and that is what
        /// the file records, rather than refusing to export at all.
        public func exportURL() async throws -> URL {
            let now = env.clock()
            let profile = env.profile.load() ?? AppEnvironment.startingProfile
            let data = try await ExportService.export(store: env.history, profile: profile, now: now)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(Self.fileName(at: now))
            try data.write(to: url, options: .atomic)
            return url
        }

        /// Read a file into the history, and apply the profile it carried.
        ///
        /// Everything the file changes is changed here: the store is replaced
        /// whole by `ExportService`, the profile is saved, and the store's
        /// replay memo is dropped so every screen recomputes from the record
        /// that just arrived. A throw means none of that happened.
        @discardableResult
        public func importFile(_ url: URL) async throws -> ImportSummary {
            do {
                let summary = try await ExportService.import(read(url), into: env.history)
                env.profile.save(summary.profile)
                await env.history.invalidate()
                lastSummary = summary
                lastError = nil
                return summary
            } catch {
                // The store was not written to, so there is nothing to undo:
                // the failure is only ever a thing to say.
                lastSummary = nil
                lastError = error
                throw error
            }
        }

        /// Record a failure the picker itself reported — a file that could not
        /// be opened never reaches `importFile`, and the user is owed the same
        /// answer either way.
        public func failed(with error: Error) {
            lastSummary = nil
            lastError = error
        }

        // MARK: - Inside

        /// A file the picker handed us may live outside the app's sandbox, so
        /// the grant is taken for as long as the read and given straight back.
        private func read(_ url: URL) throws -> Data {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try Data(contentsOf: url)
        }

        /// A file name, not copy: the app's own name and the instant the export
        /// was taken, as digits.
        private static func fileName(at now: Date) -> String {
            "icarus-history-\(Int(now.timeIntervalSince1970)).json"
        }
    }

    /// The two actions, as a pair of toolbar buttons for the History screen.
    ///
    /// No approved copy key names either action (R42), so each is its system
    /// symbol and nothing else — the same choice the Calculator toolbar makes
    /// for History itself. The only words on screen are the import's answer,
    /// which is the owner's: `importApplied` with the counts filled in, or
    /// `importFailed`, which says in the owner's words that nothing changed.
    public struct ExportImportView: View {
        @StateObject private var model: ExportImportModel
        @State private var exported: URL?
        @State private var picking = false
        @State private var answering = false

        /// On the main actor because the model it builds is, and because the
        /// environment it reads is main-actor state.
        @MainActor
        public init(env: AppEnvironment) {
            _model = StateObject(wrappedValue: ExportImportModel(env: env))
        }

        public var body: some View {
            HStack(spacing: 16) {
                share
                Button {
                    picking = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .task {
                await refreshExport()
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
                handle(result)
            }
            .alert(Text(answer), isPresented: $answering) {}
        }

        // MARK: - Inside

        /// The share sheet, once there is a file to share. While the export is
        /// still being written — or if it could not be written at all — the
        /// symbol is there and does nothing, rather than sharing an empty file.
        @ViewBuilder
        private var share: some View {
            if let exported {
                ShareLink(item: exported)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
        }

        /// What the import did, in the owner's words. A summary only ever shows
        /// when the last import actually landed one.
        private var answer: String {
            guard let summary = model.lastSummary, model.lastError == nil else {
                return AppCopy.text(.importFailed)
            }
            return AppCopy.text(
                .importApplied,
                args: [
                    "count": String(summary.sessions),
                    "reports": String(summary.reports),
                ]
            )
        }

        private func handle(_ result: Result<URL, Error>) {
            switch result {
            case let .success(url):
                Task {
                    // The throw is already recorded on the model, and the alert
                    // reads the model rather than the error.
                    _ = try? await model.importFile(url)
                    answering = true
                    // The record on disk is a different record now, so the file
                    // the share sheet offers must be too.
                    await refreshExport()
                }
            case let .failure(error):
                model.failed(with: error)
                answering = true
            }
        }

        private func refreshExport() async {
            exported = try? await model.exportURL()
        }
    }
#endif
