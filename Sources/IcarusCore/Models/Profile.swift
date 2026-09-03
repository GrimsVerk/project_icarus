import Foundation

/// What the user told the app about themselves: their skin type, how close to
/// the tanning dose they want to plan, and — for testing and for a user who
/// insists — a multiplier that replaces the learned one.
///
/// The skin type is `let` because changing it is starting over, not editing a
/// setting; the other two are the Settings screen's to change.
public struct Profile: Codable, Sendable, Equatable {
    public let skinType: SkinType
    public var ceiling: Ceiling
    /// When set, this replaces the learned sensitivity multiplier everywhere it
    /// would have been read. The learned value keeps moving underneath (R21).
    public var manualMultiplier: Double?

    public init(skinType: SkinType, ceiling: Ceiling, manualMultiplier: Double? = nil) {
        self.skinType = skinType
        self.ceiling = ceiling
        self.manualMultiplier = manualMultiplier
    }
}
