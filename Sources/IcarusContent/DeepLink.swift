import Foundation

/// An in-app link. Pure value work, so M3's router can map a URL to a screen
/// without reaching into the content layer for anything else (R27).
public enum DeepLink: Sendable, Equatable {
    case learn(ModuleID)

    /// The scheme the app registers.
    public static let scheme = "icarus"

    /// Parses `icarus://learn/<n>`, where n is a real module number.
    /// Anything else — another scheme, another host, no or extra path — is nil.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == DeepLink.scheme,
              components.host == "learn" else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 1, let number = Int(parts[0]), let id = ModuleID(rawValue: number) else { return nil }
        self = .learn(id)
    }

    public var url: URL {
        switch self {
        case let .learn(id):
            guard let url = URL(string: "\(DeepLink.scheme)://learn/\(id.rawValue)") else {
                preconditionFailure("deep link for module \(id.rawValue) is not a URL")
            }
            return url
        }
    }
}
