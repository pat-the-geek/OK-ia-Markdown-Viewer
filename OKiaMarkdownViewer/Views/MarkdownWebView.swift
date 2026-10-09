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
    /// Draw the document header (big title + meta bar). The chat sheet turns it off: it
    /// already shows the title, and an H1 per render would eat the top of the thread.
    var showsHeader: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        for name in ["ready", "docMeta", "rendered", "renderError", "diagramTapped", "imageTapped", "toc", "miroir", "recouper", "tapPage", "carteTapped"] {
            controller.add(context.coordinator, name: name)
        }

        // Hand the app language to the web pipeline (meta bar label, etc.).
        controller.addUserScript(WKUserScript(
            source: "window.OKIA_LANG = '\(Localization.shared.code)';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = VueWebLecteur(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Les marges du système ne s'ajoutent que dans le sens du défilement. `.always` les
        // ajoutait aussi sur les côtés : sur le Duo, la colonne réservée à droite restait un
        // vide de 84 points sous lequel la page ne passait pas. Les côtés sont tenus par la page
        // elle-même (`env(safe-area-inset-*)` dans style.css), qui protège l'encoche des iPhone.
        webView.scrollView.contentInsetAdjustmentBehavior = .scrollableAxes

        context.coordinator.webView = webView
        webController.webView = webView
        loadRenderer(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Inset the scroll content below the floating title/search bar overlay.
        (webView as? VueWebLecteur)?.margeHaute = max(0, topInset)

        // Re-render only when the document actually changes.
        // Le résumé et la discussion fabriquent leur document dans `body` : un nouvel identifiant
        // à chaque passage, pour le même texte. Dans la seconde partie, le lecteur voisin relance
        // ce `body` sans arrêt (traduction, défilement) : la page se rendait des milliers de fois
        // et revenait en haut, impossible à faire défiler. Même nom, même texte : on garde la page.
        if context.coordinator.loadedDocumentID != document.id,
           context.coordinator.loadedText == document.text,
           context.coordinator.loadedFilename == document.filename {
            context.coordinator.loadedDocumentID = document.id
        }
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
        var loadedText: String?
        var loadedFilename: String?

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
            loadedText = doc.text
            loadedFilename = doc.filename
            let call = parent.showsHeader
                ? "window.OKIA.render(\(mdJSON), \(nameJSON))"
                : "window.OKIA.renderPlain(\(mdJSON))"
            // Le thème d'abord : posé après coup, il ferait clignoter la charte OK-ia.
            let theme = parent.webController.themeScript
            webView.evaluateJavaScript("window.OKIA && (\(theme), \(call));", completionHandler: nil)
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
            case "carteTapped":
                if let d = message.body as? [String: Any], let cfg = d["cfg"] as? String {
                    parent.webController.onCarte?(TappedCarte(cfg: cfg))
                }
            case "tapPage":
                parent.webController.onTapPage?()
            case "miroir":
                if let copie = message.body as? [String: Any] { parent.webController.onMiroir?(copie) }
            case "recouper":
                parent.webController.onRecouper?()
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
                parent.webController.onRendered?()
                // Un document qui s'ouvre presque en haut s'ouvre tout en haut. La hauteur de la
                // barre de verre se mesure en deux temps, et le Duo change la largeur de la page
                // en cours de route : la page partait décalée de quelques dizaines de points, le
                // titre à moitié sous la barre. Plus loin, c'est un défilement voulu (la
                // discussion descend à la dernière question) : on n'y touche pas.
                if let vue = message.webView {
                    let defilement = vue.scrollView, haut = -defilement.adjustedContentInset.top
                    if defilement.contentOffset.y > haut, defilement.contentOffset.y < haut + 120 {
                        defilement.setContentOffset(CGPoint(x: defilement.contentOffset.x, y: haut), animated: false)
                    }
                }
                #if DEBUG
                // Harnais de capture : OKIA_SHOT_JS s'exécute une fois le document rendu — défiler
                // jusqu'à une section, ouvrir un aperçu — pour cadrer une capture sans toucher.
                if let js = ProcessInfo.processInfo.environment["OKIA_SHOT_JS"], !js.isEmpty,
                   let vue = message.webView {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { vue.evaluateJavaScript(js) }
                }
                #endif
            case "renderError":
                break
            default:
                break
            }
        }
    }
}

/// La vue web du lecteur : elle garde sa marge du haut — la place de la barre de verre — et une
/// page lue tout en haut reste tout en haut quand la vue change de taille (pliage du Duo,
/// rotation, Split View). Relevé au pliage : la marge restait juste (51,7 points), mais le
/// défilement finissait à 0 au lieu de −51,7, le titre sous la barre. `window.scrollTo(0, 0)`
/// ne s'en charge pas : il ignore la marge native. Plus bas dans le document, le repère de
/// lecture de WebKit est le bon : on n'y touche pas.
final class VueWebLecteur: WKWebView {
    var margeHaute: CGFloat = 0 {
        didSet { if abs(margeHaute - oldValue) > 0.5 { appliquerMarge() } }
    }

    private var tailleConnue: CGSize = .zero
    /// La page est-elle lue tout en haut ? Suivi au fil du défilement, sauf pendant un changement
    /// de taille : WebKit y recale lui-même le défilement, par étapes, et chacune ferait croire
    /// que le lecteur a quitté le haut.
    private var enHaut = true
    private var transitionJusqua = Date.distantPast
    private var suiviDefilement: NSKeyValueObservation?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard suiviDefilement == nil else { return }
        suiviDefilement = scrollView.observe(\.contentOffset) { [weak self] defilement, _ in
            MainActor.assumeIsolated {
                guard let self, Date() > self.transitionJusqua else { return }
                self.enHaut = defilement.contentOffset.y <= -defilement.adjustedContentInset.top + 1
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        appliquerMarge()
        guard bounds.size != tailleConnue else { return }
        let premiereFois = tailleConnue == .zero
        tailleConnue = bounds.size
        guard enHaut, !premiereFois else { return }
        transitionJusqua = Date().addingTimeInterval(1.0)
        // WebKit recale son défilement après la mise en page : on repasse derrière lui, deux fois.
        for delai in [0.15, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delai) { [weak self] in
                guard let self else { return }
                self.scrollView.contentOffset.y = -self.scrollView.adjustedContentInset.top
            }
        }
    }

    private func appliquerMarge() {
        let defilement = scrollView
        guard abs(defilement.contentInset.top - margeHaute) > 0.5 else { return }
        // Une page lue tout en haut reste en haut, titre visible sous la barre.
        let enHaut = defilement.contentOffset.y <= -defilement.adjustedContentInset.top + 1
        defilement.contentInset.top = margeHaute
        defilement.verticalScrollIndicatorInsets.top = margeHaute
        if enHaut { defilement.contentOffset.y = -defilement.adjustedContentInset.top }
    }
}
