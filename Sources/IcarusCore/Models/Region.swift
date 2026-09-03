import Foundation

/// The three skin regions the engine models. Each carries its own dose, tan
/// state, adaptation factor and remaining budget, and each can limit a session.
///
/// `CodingKeyRepresentable` is what makes `[Region: SED]` encode as a JSON
/// object keyed "front" / "back" / "headAndShoulders". Without it Swift encodes
/// a dictionary with an enum key as a flat array of alternating keys and
/// values, which the export format must never be.
public enum Region: String, CaseIterable, Codable, Sendable {
    case front
    case back
    case headAndShoulders
}

extension Region: CodingKeyRepresentable {}
