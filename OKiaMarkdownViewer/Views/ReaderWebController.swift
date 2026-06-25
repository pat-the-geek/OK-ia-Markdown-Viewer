import SwiftUI
import WebKit

/// One heading entry of the document outline.
struct TOCItem: Identifiable, Equatable {
    let id: String      // DOM element id
    let level: Int      // 1…6
    let text: String
}

/// Result of a search call: total matches and the 1-based index of the current one.
struct SearchResult: Equatable {
    var count: Int
    var index: Int
}

/// Bridges SwiftUI ⇄ the reader WKWebView: outline, search navigation, PDF export.
@MainActor
final class ReaderWebController: ObservableObject {
    weak var webView: WKWebView?

    @Published var toc: [TOCItem] = []
    @Published var searchResult = SearchResult(count: 0, index: 0)

    // MARK: Font size
    private(set) var fontScale: Double = 1.0

    func setFontScale(_ scale: Double) {
        fontScale = min(2.2, max(0.6, scale))
        eval("window.OKIA && window.OKIA.setFontScale(\(fontScale))")
    }

    /// Re-apply the stored scale (e.g. after a fresh render).
    func reapplyFontScale() {
        eval("window.OKIA && window.OKIA.setFontScale(\(fontScale))")
    }

    // MARK: TOC
    func scrollToHeading(_ id: String) {
        eval("window.OKIA && window.OKIA.scrollToHeading(\(jsString(id)))")
    }

    // MARK: Search
    func search(_ query: String) {
        evalResult("window.OKIA ? JSON.stringify(window.OKIA.search(\(jsString(query)))) : null") { [weak self] dict in
            self?.searchResult = Self.parse(dict)
        }
    }
    func searchNext() {
        evalResult("window.OKIA ? JSON.stringify(window.OKIA.searchNext()) : null") { [weak self] dict in
            self?.searchResult = Self.parse(dict)
        }
    }
    func searchPrev() {
        evalResult("window.OKIA ? JSON.stringify(window.OKIA.searchPrev()) : null") { [weak self] dict in
            self?.searchResult = Self.parse(dict)
        }
    }
    func clearSearch() {
        eval("window.OKIA && window.OKIA.clearSearch()")
        searchResult = SearchResult(count: 0, index: 0)
    }

    // MARK: Word (.docx) export
    /// Fetch the structured export model (blocks) from the rendered document.
    func buildExportModel(completion: @escaping ([[String: Any]]?) -> Void) {
        guard let webView else { completion(nil); return }
        let js = "return await window.OKIA.exportModel(document.getElementById('content'));"
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            if case .success(let value) = result { completion(value as? [[String: Any]]) }
            else { completion(nil) }
        }
    }

    // MARK: PDF export
    func exportPDF(completion: @escaping (URL?) -> Void) {
        guard let webView else { completion(nil); return }
        let config = WKPDFConfiguration()
        webView.createPDF(configuration: config) { result in
            switch result {
            case .success(let data):
                let name = (webView.title?.isEmpty == false ? webView.title! : "Document")
                    .replacingOccurrences(of: "/", with: "-")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
                do { try data.write(to: url); completion(url) } catch { completion(nil) }
            case .failure:
                completion(nil)
            }
        }
    }

    // MARK: helpers
    private func eval(_ js: String) { webView?.evaluateJavaScript(js, completionHandler: nil) }

    private func evalResult(_ js: String, _ handler: @escaping ([String: Any]?) -> Void) {
        webView?.evaluateJavaScript(js) { value, _ in
            if let s = value as? String, let data = s.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                handler(obj)
            } else {
                handler(nil)
            }
        }
    }

    private static func parse(_ dict: [String: Any]?) -> SearchResult {
        let count = (dict?["count"] as? Int) ?? (dict?["count"] as? Double).map(Int.init) ?? 0
        let index = (dict?["index"] as? Int) ?? (dict?["index"] as? Double).map(Int.init) ?? 0
        return SearchResult(count: count, index: index)
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let s = String(data: data, encoding: .utf8) else { return "\"\"" }
        return s
    }
}
