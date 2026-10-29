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

        /// The file the user picked, waiting for them to confirm the warning
        /// (HIST-4). An import replaces everything on the phone, so picking a
        /// file never imports it: only `confirmImport()` does.
        @Published public private(set) var pendingImport: URL?

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

        /// Hold a picked file until the warning is answered.
        public func choose(_ url: URL) {
            pendingImport = url
        }

        /// The warning was refused: nothing is imported.
        public func cancelImport() {
            pendingImport = nil
        }

        /// The warning was accepted: import the file that was picked. With no
        /// file waiting there is nothing to do.
        @discardableResult
        public func confirmImport() async throws -> ImportSummary? {
            guard let url = pendingImport else { return nil }
            pendingImport = nil
            return try await importFile(url)
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
    /// Each is its symbol in the bar, as iOS draws toolbar buttons, and
    /// VoiceOver reads its line (HIST-2, HIST-3). A picked file is imported
    /// only once the user accepts the warning that it replaces everything
    /// (HIST-4, HIST-5); the answer is then `importApplied` with the counts
    /// filled in, or `importFailed`, which says that nothing changed.
    public struct ExportImportView: View {
        @StateObject private var model: ExportImportModel
        @State private var exported: URL?
        @State private var picking = false
        @State private var warning = false
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
                    Label(AppCopy.text(.historyImport), systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
            }
            .task {
                await refreshExport()
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
                handle(result)
            }
            .importWarning(isPresented: $warning, confirm: confirm, cancel: { model.cancelImport() })
            .alert(Text(answer), isPresented: $answering) {}
        }

        // MARK: - Inside

        /// The share sheet, once there is a file to share. While the export is
        /// still being written — or if it could not be written at all — the
        /// symbol is there and does nothing, rather than sharing an empty file.
        @ViewBuilder
        private var share: some View {
            if let exported {
                ShareLink(item: exported) {
                    Label(AppCopy.text(.historyExport), systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
            } else {
                Label(AppCopy.text(.historyExport), systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }

        private func confirm() {
            Task {
                // The throw is already recorded on the model, and the alert
                // reads the model rather than the error.
                _ = try? await model.confirmImport()
                answering = true
                // The record on disk is a different record now, so the file
                // the share sheet offers must be too.
                await refreshExport()
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
                model.choose(url)
                warning = true
            case let .failure(error):
                model.failed(with: error)
                answering = true
            }
        }

        private func refreshExport() async {
            exported = try? await model.exportURL()
        }
    }

    extension View {
        /// The warning before an import overwrites the record (HIST-4), with
        /// its two answers (HIST-5). History and Settings both import, and
        /// both ask this. Only the first answer imports.
        func importWarning(
            isPresented: Binding<Bool>,
            confirm: @escaping @MainActor () -> Void,
            cancel: @escaping @MainActor () -> Void
        ) -> some View {
            confirmationDialog(
                Text(AppCopy.text(.importWarning)),
                isPresented: isPresented,
                titleVisibility: .visible
            ) {
                Button(role: .destructive, action: confirm) {
                    Text(AppCopy.text(.importConfirm))
                }
                Button(role: .cancel, action: cancel) {
                    Text(AppCopy.text(.importCancel))
                }
            }
        }
    }
#endif
