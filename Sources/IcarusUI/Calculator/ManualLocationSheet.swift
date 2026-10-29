#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// "Change place": type a name, pick a candidate, and the app is pinned to it
    /// until it is cleared (R2).
    ///
    /// This is the remedy the result screen offers on every outcome, and the only
    /// one that a denied location has: with no coordinate and no cached forecast
    /// there is no number to show, and a place the user types is what makes one
    /// possible.
    ///
    /// The resolver arrives in the initializer rather than through
    /// `AppEnvironment`, whose composition is fixed by its own slice. On Apple
    /// platforms it defaults to Apple's geocoder, which is what R2 names.
    public struct ManualLocationSheet: View {
        @ObservedObject private var model: CalculatorModel
        @Environment(\.dismiss) private var dismiss
        private let resolver: any PlaceResolver

        @State private var query = ""
        @State private var candidates: [Place] = []
        /// True once a search has answered, so an empty list can say that
        /// nothing was found (PLACE-3) rather than stay blank.
        @State private var searched = false

        public init(model: CalculatorModel, resolver: (any PlaceResolver)? = nil) {
            self.model = model
            self.resolver = resolver ?? Self.defaultResolver
        }

        public var body: some View {
            NavigationStack {
                List {
                    TextField(text: $query, prompt: Text(AppCopy.text(.placeSearchPrompt))) {
                        Label(AppCopy.text(.placeSearchPrompt), systemImage: "magnifyingglass")
                    }
                    .onSubmit { Task { await search() } }
                    if searched, candidates.isEmpty {
                        Text(AppCopy.text(.placeNotFound))
                            .foregroundStyle(.secondary)
                    }
                    // The candidates are the geocoder's own place names: data
                    // from outside the app, never copy of ours.
                    ForEach(candidates, id: \.name) { place in
                        Button {
                            Task {
                                await model.useManualPlace(place)
                                dismiss()
                            }
                        } label: {
                            Text(place.name)
                        }
                    }
                }
                .navigationTitle(AppCopy.text(.placeSheetTitle))
            }
        }

        private func search() async {
            candidates = await (try? resolver.resolve(query)) ?? []
            searched = true
        }

        /// Apple's geocoder where there is one; a resolver that knows nothing
        /// where there is not, so the sheet still builds and still shows the
        /// field.
        private static var defaultResolver: any PlaceResolver {
            #if canImport(CoreLocation)
                AppleGeocoder()
            #else
                FakePlaceResolver(table: [:])
            #endif
        }
    }
#endif
