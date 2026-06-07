import Foundation

/// A loaded Markdown document: its display name and raw text content.
struct MarkdownDocument: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let text: String
    /// Original file URL when opened from disk (nil for the bundled sample); used for sharing.
    var sourceURL: URL?

    static func == (lhs: MarkdownDocument, rhs: MarkdownDocument) -> Bool {
        lhs.id == rhs.id
    }
}

enum DocumentError: LocalizedError {
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Impossible de lire le fichier « \(name) »."
        }
    }
}

/// Loads Markdown text from a URL, handling security-scoped resources (share / Files)
/// and falling back from UTF-8 to ISO Latin-1 when needed. Kept free of UI/UIKit so it
/// can be reused as-is on a future macOS / Catalyst target (Phase 2).
enum MarkdownLoader {

    static func load(from url: URL) throws -> MarkdownDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Incoming share URLs are sometimes only readable via a coordinated copy.
            if let copied = try? coordinatedCopy(of: url) {
                data = copied
            } else {
                throw DocumentError.unreadable(url.lastPathComponent)
            }
        }

        let text = decode(data)
        return MarkdownDocument(filename: url.lastPathComponent, text: text, sourceURL: url)
    }

    /// UTF-8 first, then Latin-1 fallback, then a lossy last resort.
    static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return String(decoding: data, as: UTF8.self)
    }

    private static func coordinatedCopy(of url: URL) throws -> Data {
        var coordError: NSError?
        var result: Data?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { newURL in
            do { result = try Data(contentsOf: newURL) } catch { readError = error }
        }
        if let coordError { throw coordError }
        if let readError { throw readError }
        guard let result else { throw DocumentError.unreadable(url.lastPathComponent) }
        return result
    }
}
