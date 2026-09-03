// Splits `docs/LEARN_CONTENT.md` into the twelve committed module files.
//
// The document is the single source of the Learn text (D-2026-09-03-F4), so
// this only cuts it: each section is written verbatim, `[VERIFY]` markers kept.
// `LearnModule` strips the markers when it loads a file.
import Foundation
import IcarusContent

func run() -> Int32 {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else {
        FileHandle.standardError.write(Data("usage: split-learn-content <source.md> <output-dir>\n".utf8))
        return 2
    }
    let source = arguments[1]
    let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

    do {
        let document = try String(contentsOfFile: source, encoding: .utf8)
        let sections = try LearnSource.split(document)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (id, text) in sections {
            let name = String(format: "module-%02d.md", id.rawValue)
            let file = outputDirectory.appendingPathComponent(name)
            try (text + "\n").write(to: file, atomically: true, encoding: .utf8)
            print("wrote \(file.path) (\(text.count) characters)")
        }
        print("\(sections.count) modules written from \(source)")
        return 0
    } catch {
        FileHandle.standardError.write(Data("split-learn-content: \(error)\n".utf8))
        return 1
    }
}

exit(run())
