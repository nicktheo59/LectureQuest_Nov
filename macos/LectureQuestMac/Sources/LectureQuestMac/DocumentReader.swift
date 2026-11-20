import Foundation
import PDFKit
import UniformTypeIdentifiers

enum DocumentReader {
    static let supportedTypes: [UTType] = [.pdf, .plainText, .utf8PlainText, .text]
        + [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown")].compactMap { $0 }

    enum ReadError: LocalizedError {
        case unreadable(String), tooShort(String)
        var errorDescription: String? {
            switch self {
            case let .unreadable(n): "Couldn't read text from “\(n)”. If it's a scanned PDF, it has no text layer."
            case let .tooShort(n): "“\(n)” has too little text (need at least 50 characters)."
            }
        }
    }

    /// Returns (title, text) for a PDF / text / markdown file.
    static func read(_ url: URL) throws -> (title: String, text: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.deletingPathExtension().lastPathComponent
        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw ReadError.unreadable(name) }
            text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        } else {
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                text = s
            } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
                text = s
            } else {
                throw ReadError.unreadable(name)
            }
        }
        let cleaned = text.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 50 else { throw ReadError.tooShort(name) }
        return (prettyTitle(name), cleaned)
    }

    static func prettyTitle(_ raw: String) -> String {
        // "Lecture 2 - Tagged_1764427483179" -> "Lecture 2 - Tagged"
        raw.replacingOccurrences(of: "_\\d{8,}$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
    }
}
