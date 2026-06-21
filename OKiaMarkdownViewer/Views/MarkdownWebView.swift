import SwiftUI
import WebKit

/// A diagram the user tapped, ready to be shown full-screen.
struct TappedDiagram: Identifiable, Equatable {
    let id = UUID()
    let svg: String
    let title: String
}

/// Wraps a WKWebView that renders Markdown + Mermaid via the bundled offline pipeline.
/// Markdown is injected through a script message / JSON-encoded literal — never concatenated
/// into HTML — so arbitrary document content cannot break out into markup.
struct MarkdownWebView: UIViewRepresentable {
    let document: MarkdownDocument
    @Binding var tapped: TappedDiagram?
    @Binding var tappedImage: TappedImage?
    var onTitle: (String) -> Void
    var webController: ReaderWebController
    var onExternalLink: (URL) -> Void
    /// Height of the floating title/search bar overlay, so content scrolls clear of it.
    var topInset: CGFloat = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        for name in ["ready", "docMeta", "rendered", "renderError", "diagramTapped", "imageTapped", "toc"] {
            controller.add(context.coordinator, name: name)
        }

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .always

        context.coordinator.webView = webView
        webController.webView = webView
        loadRenderer(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Inset the scroll content below the floating title/search bar overlay.
        let inset = max(0, topInset)
        if abs(webView.scrollView.contentInset.top - inset) > 0.5 {
            let wasAtTop = webView.scrollView.contentOffset.y <= -webView.scrollView.adjustedContentInset.top + 1
            webView.scrollView.contentInset.top = inset
            webView.scrollView.verticalScrollIndicatorInsets.top = inset
            // Keep the very top of the document visible when the inset first applies.
            if wasAtTop {
                webView.scrollView.contentOffset.y = -webView.scrollView.adjustedContentInset.top
            }
        }

        // Re-render only when the document actually changes.
        if context.coordinator.loadedDocumentID != document.id {
            context.coordinator.parent = self
            if context.coordinator.pageReady {
                context.coordinator.renderCurrentDocument()
            }
        }
        context.coordinator.parent = self
    }

    private func loadRenderer(into webView: WKWebView) {
        guard let webDir = Bundle.main.url(forResource: "renderer", withExtension: "html", subdirectory: "Web")
                ?? Bundle.main.url(forResource: "renderer", withExtension: "html") else {
            return
        }
        let baseDir = webDir.deletingLastPathComponent()
        webView.loadFileURL(webDir, allowingReadAccessTo: baseDir)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        weak var webView: WKWebView?
        var pageReady = false
        var loadedDocumentID: UUID?

        init(_ parent: MarkdownWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            renderCurrentDocument()
        }

        /// Intercept link taps: open web/mail/tel links externally instead of replacing the
        /// rendered document. Allow the initial file:// load and same-page (#anchor) fragments.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            // Same document fragment (#heading) → let it scroll in place.
            if scheme == "file" {
                decisionHandler(.allow)
                return
            }
            if ["http", "https", "mailto", "tel"].contains(scheme) {
                decisionHandler(.cancel)
                parent.onExternalLink(url)
                return
            }
            decisionHandler(.cancel)
        }

        /// Handle target="_blank" links (which would otherwise open a blank view or replace content).
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
               ["http", "https", "mailto", "tel"].contains(scheme) {
                parent.onExternalLink(url)
            }
            return nil
        }

        func renderCurrentDocument() {
            guard let webView else { return }
            let doc = parent.document
            guard let mdJSON = jsonString(doc.text),
                  let nameJSON = jsonString(doc.filename) else { return }
            loadedDocumentID = doc.id
            let js = "window.OKIA && window.OKIA.render(\(mdJSON), \(nameJSON));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func jsonString(_ value: String) -> String? {
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        // MARK: WKScriptMessageHandler
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "docMeta":
                if let dict = message.body as? [String: Any], let title = dict["title"] as? String {
                    parent.onTitle(title)
                }
            case "diagramTapped":
                if let dict = message.body as? [String: Any], let svg = dict["svg"] as? String {
                    let title = (dict["title"] as? String) ?? ""
                    parent.tapped = TappedDiagram(svg: svg, title: title)
                }
            case "imageTapped":
                if let dict = message.body as? [String: Any], let src = dict["src"] as? String {
                    parent.tappedImage = TappedImage(src: src)
                }
            case "toc":
                if let dict = message.body as? [String: Any], let raw = dict["items"] as? [[String: Any]] {
                    let items: [TOCItem] = raw.compactMap { entry in
                        guard let id = entry["id"] as? String, let text = entry["text"] as? String else { return nil }
                        let level = (entry["level"] as? Int) ?? (entry["level"] as? Double).map(Int.init) ?? 1
                        return TOCItem(id: id, level: level, text: text)
                    }
                    parent.webController.toc = items
                }
            case "rendered":
                parent.webController.reapplyFontScale()
            case "renderError":
                break
            default:
                break
            }
        }
    }
}
