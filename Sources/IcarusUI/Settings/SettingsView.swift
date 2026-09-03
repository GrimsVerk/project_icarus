#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI
    import UniformTypeIdentifiers

    /// Settings (R7, R21, R25, R29, R44).
    ///
    /// Eight things in one list: how close to the tanning dose to plan, what the
    /// app has learned about the skin and how to override or reset it, how many
    /// session days were never reported, the weekly and cycle-to-date dose per
    /// region (R24), the weather attribution, the medical
    /// disclaimer, the privacy row the ad consent will reach in M7, and the
    /// record itself — export, import, delete.
    ///
    /// Every sentence is `AppCopy`'s (R42). Where no approved line names a
    /// control — the three ceilings, the buttons — the control shows the number
    /// behind it or a symbol, never a sentence this file made up. No banner ever
    /// appears here (R39).
    public struct SettingsView: View, ScreenManifest {
        public static let hasBannerSlot = false
        public static let showsFigures = true

        @ObservedObject private var model: SettingsModel
        @State private var override: Double = 1
        @State private var exportURL: URL?
        @State private var importing = false
        @State private var importNote: String?
        @State private var confirmingDelete = false

        public init(model: SettingsModel) {
            self.model = model
        }

        public var body: some View {
            List {
                ceilingSection
                sensitivitySection
                Section {
                    Text(AppCopy.text(.unreportedDays, args: ["count": String(model.unreportedDays)]))
                }
                TotalsView(totals: model.totals)
                recordSection
                Section {
                    AttributionView(legalURL: nil)
                    Text(AppCopy.text(.privacyOptions))
                    Text(AppCopy.text(.disclaimer))
                        .font(.footnote)
                }
            }
            .task {
                await model.refresh()
                override = model.manualMultiplier ?? 1
            }
        }

        // MARK: - The sections

        /// The ceiling selector. Each option is named by the share of the
        /// binding threshold it plans at, which is a figure and not copy; the
        /// aggressive one is disabled until the reports unlock it, with the
        /// approved line saying why (R7).
        private var ceilingSection: some View {
            Section {
                Picker(selection: $model.ceiling) {
                    ForEach(Ceiling.allCases, id: \.self) { ceiling in
                        Text(percent(model.scalePercent(ceiling)))
                            .tag(ceiling)
                    }
                } label: {
                    Image(systemName: "dial.medium")
                }
                .pickerStyle(.segmented)
                .disabled(!model.aggressiveUnlocked && model.ceiling == .aggressive)
                if !model.aggressiveUnlocked {
                    Text(AppCopy.text(.aggressiveLocked, args: ["count": String(model.aggressiveUnlockCount)]))
                        .font(.footnote)
                }
            }
        }

        /// What the app has learned, the override, and the way back to the
        /// learned value (R21).
        private var sensitivitySection: some View {
            Section {
                Text(model.sensitivitySentence)
                Stepper(value: $override, in: 0.5 ... 1.8, step: 0.05) {
                    Text(multiplierLabel)
                        .monospacedDigit()
                }
                .onChange(of: override) { _, value in
                    // Only a change the user made: filling the stepper in from
                    // the stored profile must not write that profile back.
                    guard value != model.manualMultiplier else { return }
                    Task { await model.overrideMultiplier(value) }
                }
                Button {
                    Task {
                        await model.resetSensitivity()
                        override = 1
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }

        /// The record: a file out, a file in, and the way to delete all of it.
        private var recordSection: some View {
            Section {
                Button {
                    Task { exportURL = try? await model.exportFile() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                }
                Button {
                    importing = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    load(result)
                }
                if let importNote {
                    Text(importNote).font(.footnote)
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .confirmationDialog(
                    Text(AppCopy.text(.deleteHistoryWarning)),
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        Task { try? await model.deleteHistory() }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }

        // MARK: - Inside

        /// Land a chosen file, and say what it did in the owner's words.
        private func load(_ result: Result<URL, any Error>) {
            guard case let .success(url) = result else {
                importNote = AppCopy.text(.importFailed)
                return
            }
            Task {
                do {
                    let summary = try await model.importFile(url)
                    importNote = AppCopy.text(
                        .importApplied,
                        args: [
                            "count": String(summary.sessions),
                            "reports": String(summary.reports),
                        ]
                    )
                    override = model.manualMultiplier ?? 1
                } catch {
                    importNote = AppCopy.text(.importFailed)
                }
            }
        }

        /// The override, as the number it is.
        private var multiplierLabel: String {
            String(format: "%.2f", override)
        }

        private func percent(_ value: Int) -> String {
            "\(value)%"
        }
    }
#endif
