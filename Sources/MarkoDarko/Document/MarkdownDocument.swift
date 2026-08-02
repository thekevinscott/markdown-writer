import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Named distinctly so it can't collide with a future system-declared type.
    static var markdownText: UTType {
        UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    }
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownText, .plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Markdown in the wild is UTF-8; fall back rather than refusing to open.
        if let string = String(data: data, encoding: .utf8) {
            text = string
        } else if let string = String(data: data, encoding: .isoLatin1) {
            text = string
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
