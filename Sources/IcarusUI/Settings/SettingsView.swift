#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI
    import UniformTypeIdentifiers

    /// Settings (R7, R21, R25, R29, R44).
    ///
    /// One list: how close to the tanning dose to plan, the skin type and what
    /// the app has learned about the skin and how to override or reset it, how
    /// many session days were never reported, the weekly and cycle-to-date
    /// dose per region (R24), the record itself — export, import, delete — and
    /// the weather attribution, the privacy rows and the medical disclaimer.
    ///
    /// Every word is `AppCopy`'s (SET-1 to SET-21 and the lines they reuse,
    /// R42). No banner ever appears here (R39).
    public struct SettingsView: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = false
        public nonisolated static let showsFigures = true

        @ObservedObject private var model: SettingsModel
        @Environment(\.dismiss) private var dismiss
        @State private var override: Double = 1
        @State private var exportURL: URL?
        @State private var importing = false
        @State private var importWarning = false
        @State private var importNote: String?
        @State private var confirmingDelete = false

        public init(model: SettingsModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                List {
                    ceilingSection
                    sensitivitySection
                    Section {
                        Text(model.unreportedSentence)
                    }
                    TotalsView(totals: model.totals)
                    recordSection
                    aboutSection
                }
                .navigationTitle(AppCopy.text(.settingsTitle))
                .toolbar {
                    // The sheet could only be swiped away (SET-2).
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text(AppCopy.text(.settingsDone))
                        }
                    }
                }
            }
            .task {
                await model.refresh()
                override = model.manualMultiplier ?? 1
            }
        }

        // MARK: - The sections

        /// The ceiling selector, by R6's names. The aggressive one is disabled
        /// until the reports unlock it, with the approved line saying why (R7).
        private var ceilingSection: some View {
            Section {
                Picker(selection: $model.ceiling) {
                    ForEach(Ceiling.allCases, id: \.self) { ceiling in
                        Text(CopyWords.ceiling(ceiling))
                            .tag(ceiling)
                    }
                } label: {
                    Text(AppCopy.text(.settingsCeilingHeading))
                }
                .pickerStyle(.segmented)
                .disabled(!model.aggressiveUnlocked && model.ceiling == .aggressive)
                footnote(.settingsCeilingFootnote)
                if !model.aggressiveUnlocked {
                    Text(AppCopy.text(.aggressiveLocked, args: ["count": String(model.aggressiveUnlockCount)]))
                        .font(.footnote)
                }
            } header: {
                Label(AppCopy.text(.settingsCeilingHeading), systemImage: "dial.medium")
            }
        }

        /// The skin type, what the app has learned, the override, and the way
        /// back to the learned value (R21). The skin-type row is where the
        /// approved `revisitSkinType` line sends the user.
        private var sensitivitySection: some View {
            Section {
                NavigationLink {
                    SkinTypeSettingView(model: model)
                } label: {
                    Text(AppCopy.text(.settingsSkinType, args: ["type": CopyWords.roman(model.skinType)]))
                }
                .accessibilityIdentifier("settings.skinType")
                Text(model.sensitivitySentence)
                Stepper(value: $override, in: 0.5 ... 1.8, step: 0.05) {
                    Text(AppCopy.text(.settingsManualValue, args: ["value": multiplierLabel]))
                        .monospacedDigit()
                }
                .onChange(of: override) { _, value in
                    // Only a change the user made: filling the stepper in from
                    // the stored profile must not write that profile back.
                    guard value != model.manualMultiplier else { return }
                    Task { await model.overrideMultiplier(value) }
                }
                footnote(.settingsManualFootnote)
                Button {
                    Task {
                        await model.resetSensitivity()
                        override = 1
                    }
                } label: {
                    Label(AppCopy.text(.settingsResetSensitivity), systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text(AppCopy.text(.settingsSensitivityHeading))
            }
        }

        /// The record: a file out, a file in, and the way to delete all of it.
        /// Both the import and the delete ask first, because both replace
        /// everything on the phone (R44, HIST-4).
        private var recordSection: some View {
            Section {
                Button {
                    Task { exportURL = try? await model.exportFile() }
                } label: {
                    Label(AppCopy.text(.settingsExport), systemImage: "square.and.arrow.up")
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label(AppCopy.text(.settingsShare), systemImage: "square.and.arrow.up.on.square")
                    }
                }
                Button {
                    importing = true
                } label: {
                    Label(AppCopy.text(.settingsImport), systemImage: "square.and.arrow.down")
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    picked(result)
                }
                .importWarning(isPresented: $importWarning, confirm: confirmImport, cancel: { model.cancelImport() })
                if let importNote {
                    Text(importNote).font(.footnote)
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(AppCopy.text(.settingsDelete), systemImage: "trash")
                }
                .confirmationDialog(
                    Text(AppCopy.text(.deleteHistoryWarning)),
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        Task { try? await model.deleteHistory() }
                    } label: {
                        Text(AppCopy.text(.deleteConfirm))
                    }
                    Button(role: .cancel) {} label: {
                        Text(AppCopy.text(.deleteCancel))
                    }
                }
            } header: {
                Text(AppCopy.text(.settingsDataHeading))
            }
        }

        private var aboutSection: some View {
            Section {
                AttributionView(attribution: model.attribution)
                privacyRows
                Text(AppCopy.text(.disclaimer))
                    .font(.footnote)
            } header: {
                Text(AppCopy.text(.settingsAboutHeading))
            }
        }

        /// The ad network's privacy options, which open its own form where its
        /// consent applies, and the privacy policy page (R39, R41).
        @ViewBuilder
        private var privacyRows: some View {
            Button {
                Task { await model.showPrivacyOptions() }
            } label: {
                Text(AppCopy.text(.privacyOptions))
            }
            .disabled(!model.privacyOptionsRequired)
            if let policy = model.privacyPolicyURL {
                Link(destination: policy) {
                    Label(AppCopy.text(.privacyPolicyLink), systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings.privacyPolicy")
            }
        }

        // MARK: - Inside

        private func footnote(_ key: CopyKey) -> some View {
            Text(AppCopy.text(key))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        /// A picked file waits for the warning; a file the picker could not
        /// hand over is the failure line.
        private func picked(_ result: Result<URL, any Error>) {
            guard case let .success(url) = result else {
                importNote = AppCopy.text(.importFailed)
                return
            }
            model.choose(url)
            importWarning = true
        }

        /// The warning was accepted: land the file, and say what it did in the
        /// owner's words.
        private func confirmImport() {
            Task {
                do {
                    guard let summary = try await model.confirmImport() else { return }
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
    }
#endif
