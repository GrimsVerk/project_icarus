import Foundation

/// The twelve Learn modules, loaded once from the bundled markdown.
///
/// The files under `Resources/Learn` are generated from `docs/LEARN_CONTENT.md`
/// by `scripts/split-learn-content.sh` and committed; S7 fails if they drift
/// from the source (D-2026-09-03-F4). Nothing here edits the text.
public enum ModuleIndex {
    public static let all: [LearnModule] = ModuleID.range.map { number in
        guard let id = ModuleID(rawValue: number) else {
            preconditionFailure("module id \(number) is outside 1...12")
        }
        return LearnModule(id: id, fileText: fileText(for: id))
    }

    public static func module(_ id: ModuleID) -> LearnModule? {
        all.first { $0.id == id }
    }

    /// The deep link that opens this module from anywhere in the app (R27).
    public static func deepLink(_ id: ModuleID) -> URL {
        DeepLink.learn(id).url
    }

    // MARK: - Loading

    private static let subdirectory = "Resources/Learn"

    private static func fileText(for id: ModuleID) -> String {
        let name = String(format: "module-%02d", id.rawValue)
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: subdirectory)
            ?? Bundle.module.bundleURL.appendingPathComponent("\(subdirectory)/\(name).md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("missing bundled Learn module at \(url.path)")
        }
        return text
    }
}
