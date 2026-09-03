import Foundation

/// A span of clock time. Always today, and never a minute before "now" once the
/// engine has clipped it (R17).
public struct Window: Codable, Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// Length in minutes. Never negative.
    public var minutes: Double {
        max(0, end.timeIntervalSince(start) / 60)
    }
}

/// Which way up the user is lying.
public enum Side: String, Codable, Sendable {
    case faceUp
    case faceDown
}

/// What the body is doing during a sub-interval of a session. Encodes as
/// `{"lying":"faceUp"}` or as the bare string `"upAndAbout"`.
public enum Exposure: Codable, Sendable, Hashable {
    case lying(Side)
    case upAndAbout

    private enum CodingKeys: String, CodingKey {
        case lying
    }

    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            guard name == "upAndAbout" else {
                throw DecodingError.dataCorruptedError(
                    in: single, debugDescription: "unknown exposure \"\(name)\""
                )
            }
            self = .upAndAbout
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self = try .lying(keyed.decode(Side.self, forKey: .lying))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case let .lying(side):
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encode(side, forKey: .lying)
        case .upAndAbout:
            var single = encoder.singleValueContainer()
            try single.encode("upAndAbout")
        }
    }
}

/// An exposure over a span: what the timer records and what a plan proposes.
public struct ExposureInterval: Codable, Sendable, Equatable {
    public let exposure: Exposure
    public let window: Window

    public init(exposure: Exposure, window: Window) {
        self.exposure = exposure
        self.window = window
    }
}

/// How the user will spend the session.
public enum Posture: String, Codable, Sendable {
    case lyingTurning
    case upAndAbout
}

/// Whether the user wants the best block of minutes or means to stay out for
/// the whole window they entered.
public enum Intent: String, Codable, Sendable {
    case bestMinutes
    case stayWholeWindow
}
