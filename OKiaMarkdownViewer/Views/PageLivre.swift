import SwiftUI
import WebKit

/// Le mode livre du Duo partiellement replié : la page de droite. Elle montre la copie du
/// document que la page de gauche lui envoie — rendu, traductions et thème compris — et
/// commence là où la gauche s'arrête. Les deux pages défilent ensemble, comme un livre ouvert.
@MainActor
final class LivreController: ObservableObject {
    weak var webView: WKWebView?
    fileprivate var pret = false
    private var enAttente: [String: Any]?
    private var largeurEnAttente: CGFloat?

    func poser(_ copie: [String: Any]) {
        guard pret, let webView,
              let data = try? JSONSerialization.data(withJSONObject: copie),
              let json = String(data: data, encoding: .utf8) else { enAttente = copie; return }
        webView.evaluateJavaScript("window.OKIA && window.OKIA.poserMiroir(\(json))")
    }

    func largeurNaturelle(_ fin: @escaping (CGFloat) -> Void) {
        guard pret, let webView else { fin(0); return }
        webView.evaluateJavaScript("window.OKIA ? window.OKIA.largeurNaturelle('droite') : 0") { r, _ in
            fin(CGFloat((r as? NSNumber)?.doubleValue ?? 0))
        }
    }

    func setLargeurLivre(_ largeur: CGFloat) {
        guard pret, let webView else { largeurEnAttente = largeur; return }
        webView.evaluateJavaScript("window.OKIA && window.OKIA.setLargeurLivre(\(Int(largeur.rounded())), 'droite')")
    }

    fileprivate func estPret() {
        pret = true
        if let copie = enAttente { enAttente = nil; poser(copie) }
        if let l = largeurEnAttente { largeurEnAttente = nil; setLargeurLivre(l) }
    }
}

struct PageLivre: UIViewRepresentable {
    @ObservedObject var livre: LivreController
    /// Appelé quand la page est prête à recevoir copie et largeur.
    var surPret: () -> Void
    /// Un toucher sur la page : comme à gauche, il montre ou efface la barre.
    var surToucher: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "ready")
        controller.add(context.coordinator, name: "tapPage")
        controller.addUserScript(WKUserScript(
            source: "window.OKIA_LANG = '\(Localization.shared.code)';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let vue = WKWebView(frame: .zero, configuration: config)
        vue.isOpaque = false
        vue.backgroundColor = .clear
        vue.scrollView.backgroundColor = .clear
        vue.scrollView.contentInsetAdjustmentBehavior = .scrollableAxes
        livre.webView = vue
        if let page = Bundle.main.url(forResource: "renderer", withExtension: "html", subdirectory: "Web")
            ?? Bundle.main.url(forResource: "renderer", withExtension: "html") {
            vue.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return vue
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: PageLivre
        init(_ parent: PageLivre) { self.parent = parent }
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "tapPage" { parent.surToucher(); return }
            guard message.name == "ready" else { return }
            parent.livre.estPret()
            parent.surPret()
        }
    }
}

/// Le livre se feuillette : plus de défilement, des doubles pages. La page de gauche montre la
/// page 2k du document, celle de droite la 2k+1 ; un balayage tourne la double page. Les pages
/// sont coupées entre deux lignes (`OKIA.coupuresLivre`), et ce qui dépasse sous la dernière
/// ligne est caché, comme le bas d'une page imprimée.
@MainActor
final class PaginationLivre: NSObject {
    private weak var gauche: WKWebView?
    private weak var droite: WKWebView?
    private var coupes: [CGFloat] = [0]
    private var hauteur: CGFloat = 0
    private var planche = 0
    private var gestes: [(UIView, UIGestureRecognizer)] = []
    private var attente: DispatchWorkItem?

    func relier(gauche: WKWebView?, droite: WKWebView?) {
        delier()
        guard let gauche, let droite else { return }
        self.gauche = gauche
        self.droite = droite
        for vue in [gauche, droite] {
            vue.scrollView.isScrollEnabled = false
            for (direction, sens) in [(UISwipeGestureRecognizer.Direction.left, 1), (.up, 1), (.right, -1), (.down, -1)] {
                let g = UISwipeGestureRecognizer(target: self, action: sens > 0 ? #selector(suivante) : #selector(precedente))
                g.direction = direction
                vue.addGestureRecognizer(g)
                gestes.append((vue, g))
            }
        }
        recalculer()
    }

    func delier() {
        attente?.cancel()
        for (vue, g) in gestes { vue.removeGestureRecognizer(g) }
        gestes = []
        for vue in [gauche, droite].compactMap({ $0 }) {
            vue.scrollView.isScrollEnabled = true
            vue.evaluateJavaScript("window.OKIA && window.OKIA.cacheLivre(null)")
        }
        gauche = nil
        droite = nil
    }

    /// Après un changement de mise en page (copie reçue, traduction, barre, taille du texte).
    func recalculerPlusTard() {
        attente?.cancel()
        let tache = DispatchWorkItem { [weak self] in self?.recalculer() }
        attente = tache
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: tache)
    }

    private func visible(_ v: WKWebView) -> CGFloat {
        let s = v.scrollView
        return s.bounds.height - s.adjustedContentInset.top - s.adjustedContentInset.bottom
    }

    func recalculer() {
        guard let g = gauche, let d = droite else { return }
        let h = floor(min(visible(g), visible(d)))
        guard h > 100 else { return }
        let lu = debut(2 * planche)
        g.evaluateJavaScript("window.OKIA ? window.OKIA.coupuresLivre(\(Int(h))) : [0]") { [weak self] r, _ in
            guard let self else { return }
            let liste = (r as? [NSNumber])?.map { CGFloat($0.doubleValue) } ?? [0]
            self.hauteur = h
            self.coupes = liste.isEmpty ? [0] : liste
            // On reste sur la double page qui contient ce qu'on lisait.
            var k = 0
            while 2 * (k + 1) < self.coupes.count, self.coupes[2 * (k + 1)] <= lu + 1 { k += 1 }
            self.planche = k
            self.afficher(anime: false)
        }
    }

    private func debut(_ page: Int) -> CGFloat {
        if page < coupes.count { return coupes[page] }
        return (coupes.last ?? 0) + hauteur * CGFloat(page - coupes.count + 1)
    }

    private func afficher(anime: Bool) {
        guard let g = gauche, let d = droite else { return }
        let pg = 2 * planche, pd = pg + 1
        let cacheG = debut(pd), cacheD: CGFloat = pd + 1 < coupes.count ? debut(pd + 1) : -1
        g.evaluateJavaScript("window.OKIA && window.OKIA.cacheLivre(\(Int(cacheG)), \(Int(hauteur)))")
        d.evaluateJavaScript("window.OKIA && window.OKIA.cacheLivre(\(Int(cacheD)), \(Int(hauteur)))")
        let poser = {
            g.scrollView.contentOffset.y = self.debut(pg) - g.scrollView.adjustedContentInset.top
            d.scrollView.contentOffset.y = self.debut(pd) - d.scrollView.adjustedContentInset.top
        }
        if anime {
            UIView.transition(with: g, duration: 0.25, options: [.transitionCrossDissolve], animations: {})
            UIView.transition(with: d, duration: 0.25, options: [.transitionCrossDissolve], animations: {})
        }
        poser()
    }

    @objc private func suivante() { tourner(1) }
    @objc private func precedente() { tourner(-1) }

    private func tourner(_ sens: Int) {
        let k = planche + sens
        guard k >= 0, 2 * k < coupes.count else { return }
        planche = k
        afficher(anime: true)
    }
}
