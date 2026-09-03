import Foundation

/// How thickly the sunscreen is actually applied, in mg/cm². The label on the
/// bottle is measured at 2.0; people apply about 1.0 (Module 8).
public enum Application: String, Codable, Sendable, CaseIterable {
    case thin
    case normal
    case thick

    public var density: Double {
        switch self {
        case .thin: 0.5
        case .normal: 1.0
        case .thick: 2.0
        }
    }
}

/// A label and the way it will be applied. The pair, never the label alone —
/// SPF 50 applied thinly is worth less than SPF 15 applied properly.
public struct SunscreenChoice: Codable, Sendable, Equatable, Hashable {
    public let spfLabel: Int
    public let application: Application

    public init(spfLabel: Int, application: Application) {
        self.spfLabel = spfLabel
        self.application = application
    }

    /// The protection the user will actually get: the label's protection falls
    /// off exponentially with the applied density.
    public var effectiveSPF: Double {
        pow(Double(spfLabel), application.density / 2)
    }
}

/// What the user confirmed at logging time.
public enum SunscreenConfirmation: Codable, Sendable, Equatable {
    case asPrescribed
    case alternative(SunscreenChoice)
    case none

    private enum CodingKeys: String, CodingKey {
        case alternative
    }

    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            switch name {
            case "asPrescribed": self = .asPrescribed
            case "none": self = .none
            default:
                throw DecodingError.dataCorruptedError(
                    in: single, debugDescription: "unknown sunscreen confirmation \"\(name)\""
                )
            }
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self = try .alternative(keyed.decode(SunscreenChoice.self, forKey: .alternative))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case let .alternative(choice):
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode(choice, forKey: .alternative)
        case .asPrescribed:
            var single = encoder.singleValueContainer()
            try single.encode("asPrescribed")
        case .none:
            var single = encoder.singleValueContainer()
            try single.encode("none")
        }
    }
}
