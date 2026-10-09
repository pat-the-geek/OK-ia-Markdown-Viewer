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
        webView.evaluateJavaScript("window.OKIA ? window.OKIA.largeurNaturelle() : 0") { r, _ in
            fin(CGFloat((r as? NSNumber)?.doubleValue ?? 0))
        }
    }

    func setLargeurLivre(_ largeur: CGFloat) {
        guard pret, let webView else { largeurEnAttente = largeur; return }
        webView.evaluateJavaScript("window.OKIA && window.OKIA.setLargeurLivre(\(Int(largeur.rounded())))")
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "ready")
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
            guard message.name == "ready" else { return }
            parent.livre.estPret()
            parent.surPret()
        }
    }
}

/// Fait défiler les deux pages ensemble : le point du document qui touche le bas de la page de
/// gauche est en haut de celle de droite. Qu'on fasse défiler l'une ou l'autre, l'autre suit.
@MainActor
final class SynchroLivre {
    private weak var gauche: UIScrollView?
    private weak var droite: UIScrollView?
    private var suivis: [NSKeyValueObservation] = []
    private var enCours = false

    func relier(gauche: UIScrollView?, droite: UIScrollView?) {
        delier()
        guard let gauche, let droite else { return }
        self.gauche = gauche
        self.droite = droite
        suivis = [
            gauche.observe(\.contentOffset) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.suivre(depuisGauche: true) }
            },
            droite.observe(\.contentOffset) { [weak self] vue, _ in
                MainActor.assumeIsolated {
                    // Seul un geste sur la page de droite la fait mener ; sinon, c'est elle qui suit.
                    if vue.isTracking || vue.isDragging || vue.isDecelerating { self?.suivre(depuisGauche: false) }
                }
            }
        ]
        suivre(depuisGauche: true)
    }

    func delier() {
        suivis.forEach { $0.invalidate() }
        suivis = []
    }

    /// La hauteur de document que montre la page de gauche.
    private func visible(_ s: UIScrollView) -> CGFloat {
        s.bounds.height - s.adjustedContentInset.top - s.adjustedContentInset.bottom
    }

    func suivre(depuisGauche: Bool) {
        guard !enCours, let g = gauche, let d = droite else { return }
        enCours = true
        defer { enCours = false }
        if depuisGauche {
            let basGauche = g.contentOffset.y + g.adjustedContentInset.top + visible(g)
            d.contentOffset.y = basGauche - d.adjustedContentInset.top
        } else {
            let hautDroite = d.contentOffset.y + d.adjustedContentInset.top
            g.contentOffset.y = hautDroite - visible(g) - g.adjustedContentInset.top
        }
    }
}
