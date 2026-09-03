import Foundation
import IcarusCore

/// Every non-Learn string the app shows, resolved from the generated
/// `app-copy.json` (R42, D-2026-09-03-F7).
///
/// The engine names a `CopyKey` and never a sentence; a view asks here and never
/// holds a literal — `acceptance/S11.sh` fails on a literal at a copy-bearing
/// call site. The words are the owner's (S17) and nothing here edits them: this
/// only chooses between the base line and the fair-skin line, and fills in the
/// values the engine computed.
public enum AppCopy {
    /// The text for a key, in the wording that applies to this skin type.
    ///
    /// Skin types I and II get the `fair` line where the document carries one
    /// (R43), everyone else gets `base`. Each `{name}` is replaced by
    /// `args["name"]`; an argument that was not supplied stays as its
    /// placeholder, because a hole in a sentence is a bug that must be visible
    /// rather than a sentence that quietly lost a number.
    public static func text(_ key: CopyKey, skinType: SkinType? = nil, args: [String: String] = [:]) -> String {
        guard let entry = document.keys[key.rawValue] else {
            preconditionFailure("no copy for \(key.rawValue) — docs/APP_COPY.md and CopyKey have drifted")
        }
        let fairSkin = skinType?.band == .fair
        let template = (fairSkin ? entry.fair : nil) ?? entry.base
        return fill(template, args: args)
    }

    /// The keys the generated document carries. Every `CopyKey` is one of them:
    /// the generator refuses to write a document that is missing any.
    public static var allKeys: Set<CopyKey> {
        Set(document.keys.keys.compactMap(CopyKey.init(rawValue:)))
    }

    /// The whole document, loaded once. The skin-type table and the quiz read
    /// it too — they are sections of the same owner-approved file.
    static let document: AppCopyDocument = load()

    // MARK: - Inside

    private static func fill(_ template: String, args: [String: String]) -> String {
        guard !args.isEmpty else { return template }
        var text = template
        for (name, value) in args {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return text
    }

    private static let resourceName = "app-copy"
    private static let subdirectory = "Resources"

    private static func load() -> AppCopyDocument {
        let url = Bundle.module.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.module.bundleURL.appendingPathComponent("\(subdirectory)/\(resourceName).json")
        guard let data = try? Data(contentsOf: url) else {
            preconditionFailure("missing bundled app copy at \(url.path)")
        }
        do {
            return try JSONDecoder().decode(AppCopyDocument.self, from: data)
        } catch {
            preconditionFailure("bundled app copy at \(url.path) is unreadable: \(error)")
        }
    }
}
