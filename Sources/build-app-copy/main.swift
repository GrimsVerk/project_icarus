// Turns `docs/APP_COPY.md` into the committed `app-copy.json`.
//
// The document is the single source of every non-Learn string (R42,
// D-2026-09-03-F7), so this only reads it: `AppCopySource` cuts it into keys,
// the skin-type table and the quiz, and the JSON is written with sorted keys so
// two runs of the same document are the same bytes. `acceptance/S11.sh`
// regenerates it and diffs it against the committed file.
import Foundation
import IcarusContent

func run() -> Int32 {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else {
        FileHandle.standardError.write(Data("usage: build-app-copy <APP_COPY.md> <output.json>\n".utf8))
        return 2
    }
    let source = arguments[1]
    let output = URL(fileURLWithPath: arguments[2])

    do {
        let markdown = try String(contentsOfFile: source, encoding: .utf8)
        let document = try AppCopySource.build(markdown)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var json = try encoder.encode(document)
        // A trailing newline, so the committed file is a text file like every
        // other one in the tree and `diff` has nothing to say about its end.
        json.append(0x0A)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try json.write(to: output, options: .atomic)
        print("wrote \(output.path)")
        print("\(document.keys.count) copy keys, \(document.skinTypes.count) skin types, "
            + "\(document.quiz.count) quiz questions from \(source)")
        return 0
    } catch {
        FileHandle.standardError.write(Data("build-app-copy: \(error)\n".utf8))
        return 1
    }
}

exit(run())
