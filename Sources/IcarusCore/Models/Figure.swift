import Foundation

/// Which number on the screen this is.
public enum FigureKey: String, Codable, Sendable, CaseIterable {
    case headlineMinutes
    case sideMinutes
    case regionDose
    case remainingBudget
    case cycleDose
    case rangeLower
    case rangeUpper
    /// The upper edge where it is clipped at the redness line (R7).
    case rangeUpperClipped
    case uvaMultiple
    case shortfall
    case extraIfCovered
}

/// The unit a figure is in. Deliberately not called `Unit`: Foundation exports
/// a class of that name.
public enum FigureUnit: Sendable, Equatable {
    case minutes
    case sed
    case multiple
}

/// One number the UI shows, with the provenance of the constants behind it
/// (R22, R30). `reads` is what the Tunables spy recorded while the number was
/// computed, so "is this an estimate?" is answered by the engine, never guessed
/// at by the UI.
public struct Figure: Sendable, Equatable {
    public let key: FigureKey
    public let region: Region?
    public let exposure: Exposure?
    public let value: Double
    public let unit: FigureUnit
    public let reads: Set<String>
    public var isEstimate: Bool
    public var assumptionKeys: [String]

    public init(
        key: FigureKey,
        region: Region? = nil,
        exposure: Exposure? = nil,
        value: Double,
        unit: FigureUnit,
        reads: Set<String>
    ) {
        self.key = key
        self.region = region
        self.exposure = exposure
        self.value = value
        self.unit = unit
        self.reads = reads
        let assumed = reads.intersection(Tunables.assumptionKeys)
        isEstimate = !assumed.isEmpty
        assumptionKeys = assumed.sorted()
    }
}
