import SwiftUI
import WebKit
import PDFKit

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

    /// Paper the PDF is laid out on. A4 everywhere except the handful of countries that
    /// use US Letter — exporting an A4 report to someone who prints on Letter crops it,
    /// and the reverse leaves a band of white.
    private static var paperSize: CGSize {
        // 72 points to the inch: A4 = 210×297 mm, Letter = 8.5×11 in.
        let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "PR", "GT", "CR", "DO", "NI", "PA", "SV"]
        let region = Locale.current.region?.identifier ?? "CH"
        return letterRegions.contains(region) ? CGSize(width: 612, height: 792)
                                              : CGSize(width: 595.2, height: 841.8)
    }

    /// Export the document as an ordinary paginated PDF.
    ///
    /// `WKWebView.createPDF` was the obvious call and the wrong one: it returns a single
    /// page as tall as the whole document and as wide as the screen. Such a file opens, but
    /// it cannot be paged through, and annotating it in Apple Notes with the Pencil means
    /// scrolling one endless sheet. `UIPrintPageRenderer` lays the same content out for
    /// paper instead, so the result is a normal multi-page A4 (or Letter) document.
    ///
    /// The layout rules live in the print stylesheet (`@media print` in style.css); this
    /// method only decides the sheet and its margins.
    func exportPDF(completion: @escaping (URL?) -> Void) {
        guard let webView else { completion(nil); return }
        // Freeze the maps to still images first — Leaflet does not reflow for the print
        // width and would otherwise print a part-covered box. Restored right after.
        //
        // callAsyncJavaScript, not evaluateJavaScript: the freeze is asynchronous (it
        // rasterises, then waits for the image to decode) and evaluateJavaScript returns
        // without awaiting the promise — the PDF was then drawn before any of it happened.
        webView.callAsyncJavaScript("return await window.OKIA.freezeMapsForPrint();",
                                    in: nil, in: .page) { _ in
            // Headings are read from the DOM, not taken from `toc`: that one is filled by a
            // script message and may not have arrived, which would silently disable the
            // orphan pass below.
            webView.callAsyncJavaScript("return JSON.stringify(window.OKIA.headings());",
                                        in: nil, in: .page) { result in
                var headings: [(id: String, text: String)] = []
                if case .success(let value) = result, let json = value as? String,
                   let data = json.data(using: .utf8),
                   let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                    headings = raw.compactMap { entry in
                        guard let id = entry["id"], let text = entry["text"] else { return nil }
                        return (id, text)
                    }
                }
                self.renderPass(webView, headings: headings, attempt: 0) { url in
                    webView.evaluateJavaScript("window.OKIA && window.OKIA.unfreezeMaps();") { _, _ in
                        completion(url)
                    }
                }
            }
        }
    }

    /// Draw the PDF, look for headings left stranded at the foot of a page, mark those for a
    /// page break, and draw again.
    ///
    /// This costs a second (rarely a third) render, and it is the only thing that works: this
    /// print engine ignores `break-inside: avoid` and `break-after: avoid` — measured, a
    /// heading followed by a map that did not fit stayed behind while the map moved on. It
    /// does honour an explicit break, but nothing in the DOM knows where the page boundaries
    /// will fall. So the boundaries are read back from the PDF that was just produced.
    private func renderPass(_ webView: WKWebView, headings: [(id: String, text: String)],
                            attempt: Int, completion: @escaping (URL?) -> Void) {
        renderPDF(webView) { url in
            guard attempt < 2, !headings.isEmpty, let url,
                  let data = try? Data(contentsOf: url),
                  let doc = PDFDocument(data: data) else { completion(url); return }

            let stranded = self.strandedHeadingIDs(in: doc, headings: headings)
            guard !stranded.isEmpty else { completion(url); return }

            let list = stranded.map { "\"\($0)\"" }.joined(separator: ",")
            webView.evaluateJavaScript("window.OKIA && window.OKIA.markBreakBefore([\(list)]);") { _, _ in
                self.renderPass(webView, headings: headings, attempt: attempt + 1,
                                completion: completion)
            }
        }
    }

    /// Outline entries whose heading is the last thing printed on a page — the reader has to
    /// turn over to find what it announces. The last page is exempt: a heading there has
    /// nowhere better to go.
    private func strandedHeadingIDs(in doc: PDFDocument,
                                    headings: [(id: String, text: String)]) -> [String] {
        guard doc.pageCount > 1 else { return [] }
        var ids: [String] = []
        for index in 0..<(doc.pageCount - 1) {
            guard let text = doc.page(at: index)?.string else { continue }
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let last = lines.last else { continue }
            // The PDF may wrap a long heading, so compare on a prefix rather than equality.
            if let item = headings.first(where: { headingMatches($0.text, last) }) {
                ids.append(item.id)
            }
        }
        return ids
    }

    private func headingMatches(_ heading: String, _ line: String) -> Bool {
        let a = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.count > 3, b.count > 3 else { return a == b }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }

    private func renderPDF(_ webView: WKWebView, completion: @escaping (URL?) -> Void) {
        let paper = Self.paperSize
        let margin: CGFloat = 42                    // ≈ 15 mm, comfortable for annotation
        let paperRect = CGRect(origin: .zero, size: paper)
        let printable = paperRect.insetBy(dx: margin, dy: margin)

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(paperRect, forKey: "paperRect")
        renderer.setValue(printable, forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paperRect, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        guard data.length > 0 else { completion(nil); return }

        let name = (webView.title?.isEmpty == false ? webView.title! : "Document")
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        do {
            try data.write(to: url, options: .atomic)
            completion(url)
        } catch {
            completion(nil)
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
