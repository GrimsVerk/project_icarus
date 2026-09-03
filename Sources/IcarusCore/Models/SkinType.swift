import Foundation

/// Fitzpatrick skin type. The raw value is the roman numeral as an integer.
public enum SkinType: Int, CaseIterable, Codable, Sendable {
    case i = 1
    case ii
    case iii
    case iv
    case v
    case vi

    /// Types are grouped into three bands wherever the evidence only separates
    /// three groups — the melanogenic fraction, the adaptation gain and the
    /// rise multiplier all vary by band, never by type.
    public var band: SkinBand {
        switch self {
        case .i, .ii: .fair
        case .iii: .medium
        case .iv, .v, .vi: .dark
        }
    }
}

/// The three evidence bands: I–II, III, IV–VI.
public enum SkinBand: String, Codable, Sendable, CaseIterable {
    case fair
    case medium
    case dark
}

/// The user's selector: how close to the tanning dose the engine plans.
/// Aggressive is at the line, never past it.
public enum Ceiling: String, Codable, Sendable, CaseIterable {
    case conservative
    case standard
    case aggressive
}
