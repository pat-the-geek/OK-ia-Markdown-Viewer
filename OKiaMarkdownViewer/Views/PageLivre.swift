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
/// page 2k du document, celle de droite la 2k+1. Un balayage tourne la page, comme dans un livre.
/// Elles sont coupées entre deux lignes
/// (`OKIA.coupuresLivre`), et ce qui dépasse sous la dernière ligne est caché, comme le bas
/// d'une page imprimée.
@MainActor
final class PaginationLivre: NSObject, UIGestureRecognizerDelegate {
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
            // Le doigt tourne la page vers la gauche (suivante) ou la droite (précédente).
            let doigt = UIPanGestureRecognizer(target: self, action: #selector(suivreDoigt(_:)))
            doigt.delegate = self
            vue.addGestureRecognizer(doigt)
            gestes.append((vue, doigt))
            // Balayer vers le haut ou le bas tourne la page d'un seul coup.
            for (direction, sens) in [(UISwipeGestureRecognizer.Direction.up, 1), (.down, -1)] {
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
        g.scrollView.contentOffset.y = debut(pg) - g.scrollView.adjustedContentInset.top
        d.scrollView.contentOffset.y = debut(pd) - d.scrollView.adjustedContentInset.top
    }

    // MARK: La page qui tourne

    /// Une page qui tourne, comme un livre, et qui suit le doigt : en avant, la page de droite se
    /// soulève autour de la pliure et découvre dessous la nouvelle page de droite ; son verso
    /// montre la nouvelle page de gauche. Lâchée avant la moitié, elle retombe là où on était ;
    /// au-delà, ou d'un geste vif, elle se pose de l'autre côté. Les images des pages viennent de
    /// WebKit (`takeSnapshot`) ; la page qui tourne vit dans la fenêtre, pour franchir la pliure.
    private final class Tour {
        let sens: Int
        let leve: WKWebView
        let reste: WKWebView
        let cache: UIView
        let scene: CALayer
        let page: CATransformLayer
        let ombre: CALayer
        let ombreDos: CALayer
        /// L'ombre que la page levée jette sur la page qu'elle découvre, ou sur celle où elle va se poser.
        let ombrePortee: CAGradientLayer
        let cadre: CGRect
        var avancement: CGFloat = 0
        init(sens: Int, leve: WKWebView, reste: WKWebView, cache: UIView, scene: CALayer,
             page: CATransformLayer, ombre: CALayer, ombreDos: CALayer,
             ombrePortee: CAGradientLayer, cadre: CGRect) {
            self.sens = sens; self.leve = leve; self.reste = reste; self.cache = cache
            self.scene = scene; self.page = page; self.ombre = ombre; self.ombreDos = ombreDos
            self.ombrePortee = ombrePortee; self.cadre = cadre
        }
    }

    private var tour: Tour?
    private var enPreparation = false
    /// Le doigt a lâché pendant la préparation : la décision attend que la page soit prête.
    private var decisionEnAttente: Bool?
    private var dernierAvancement: CGFloat = 0

    private func image(_ vue: WKWebView, _ fin: @escaping (UIImage?) -> Void) {
        vue.takeSnapshot(with: nil) { image, _ in fin(image) }
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: pan.view)
        return abs(v.x) > abs(v.y) && tour == nil && !enPreparation
    }

    @objc private func suivante() { tournerDUnCoup(1) }
    @objc private func precedente() { tournerDUnCoup(-1) }

    private func tournerDUnCoup(_ sens: Int) {
        guard tour == nil, !enPreparation else { return }
        decisionEnAttente = true
        preparer(sens)
    }

    @objc private func suivreDoigt(_ pan: UIPanGestureRecognizer) {
        let dx = pan.translation(in: pan.view).x
        let largeur = max(pan.view?.bounds.width ?? 400, 1)
        switch pan.state {
        case .changed:
            if tour == nil && !enPreparation {
                guard abs(dx) > 6 else { return }
                decisionEnAttente = nil
                preparer(dx < 0 ? 1 : -1)
            }
            if let t = tour {
                let p = min(1, max(0, (t.sens > 0 ? -dx : dx) / largeur))
                poser(t, p)
            } else {
                dernierAvancement = abs(dx) / largeur
            }
        case .ended, .cancelled, .failed:
            let v = pan.velocity(in: pan.view).x
            let sens = tour?.sens ?? (dx < 0 ? 1 : -1)
            let p = (sens > 0 ? -dx : dx) / largeur
            let vif = sens > 0 ? v < -600 : v > 600
            let valider = pan.state == .ended && (p > 0.5 || vif)
            if let t = tour { finir(t, valider: valider) } else if enPreparation { decisionEnAttente = valider }
        default:
            break
        }
    }

    /// Construit la page qui tournera, à plat, prête à suivre le doigt.
    private func preparer(_ sens: Int) {
        guard let g = gauche, let d = droite, let fenetre = g.window else { return }
        let k = planche + sens
        guard k >= 0, 2 * k < coupes.count else { decisionEnAttente = nil; return }
        enPreparation = true
        let leve = sens > 0 ? d : g, reste = sens > 0 ? g : d
        image(leve) { recto in
            self.image(reste) { ancienne in
                guard let recto, let ancienne else { self.enPreparation = false; return }
                // L'ancienne page reste visible sous la page qui tourne, jusqu'à ce qu'elle la couvre.
                let cache = UIImageView(image: ancienne)
                cache.frame = reste.bounds
                reste.addSubview(cache)
                self.planche = k
                self.afficher(anime: false)
                // Le temps que WebKit dessine la nouvelle double page, qui donnera le verso.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.image(reste) { verso in
                        let t = self.construire(recto: recto, verso: verso ?? ancienne, leve: leve,
                                                reste: reste, cache: cache, sens: sens, fenetre: fenetre)
                        self.tour = t
                        self.enPreparation = false
                        if let valider = self.decisionEnAttente {
                            self.decisionEnAttente = nil
                            self.finir(t, valider: valider)
                        } else {
                            self.poser(t, self.dernierAvancement)
                        }
                    }
                }
            }
        }
    }

    private func construire(recto: UIImage, verso: UIImage, leve: WKWebView, reste: WKWebView,
                            cache: UIView, sens: Int, fenetre: UIWindow) -> Tour {
        let cadre = leve.convert(leve.bounds, to: fenetre)
        let scene = CALayer()
        scene.frame = fenetre.bounds
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 1800
        scene.sublayerTransform = perspective

        let page = CATransformLayer()
        page.bounds = CGRect(origin: .zero, size: cadre.size)
        // La charnière de la page est la pliure : son bord gauche en avant, son bord droit en arrière.
        page.anchorPoint = CGPoint(x: sens > 0 ? 0 : 1, y: 0.5)
        page.position = CGPoint(x: sens > 0 ? cadre.minX : cadre.maxX, y: cadre.midY)

        func face(_ image: UIImage, retournee: Bool) -> (CALayer, CALayer) {
            let f = CALayer()
            f.frame = page.bounds
            f.contents = image.cgImage
            f.contentsGravity = .resize
            f.isDoubleSided = false
            if retournee { f.transform = CATransform3DMakeRotation(.pi, 0, 1, 0) }
            let o = CALayer()
            o.frame = f.bounds
            o.backgroundColor = UIColor.black.cgColor
            o.opacity = 0
            f.addSublayer(o)
            page.addSublayer(f)
            return (f, o)
        }
        let (_, ombre) = face(recto, retournee: false)
        let (_, ombreDos) = face(verso, retournee: true)
        // L'ombre portée : une bande dégradée au pied du bord libre de la page, sous elle.
        let ombrePortee = CAGradientLayer()
        ombrePortee.startPoint = CGPoint(x: 0, y: 0.5)
        ombrePortee.endPoint = CGPoint(x: 1, y: 0.5)
        ombrePortee.opacity = 0
        scene.addSublayer(ombrePortee)
        scene.addSublayer(page)
        fenetre.layer.addSublayer(scene)
        return Tour(sens: sens, leve: leve, reste: reste, cache: cache, scene: scene, page: page,
                    ombre: ombre, ombreDos: ombreDos, ombrePortee: ombrePortee, cadre: cadre)
    }

    /// p : de 0 (à plat, du côté de départ) à 1 (posée de l'autre côté).
    private func poser(_ t: Tour, _ p: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        t.avancement = p
        t.page.transform = CATransform3DMakeRotation((t.sens > 0 ? -1 : 1) * .pi * p, 0, 1, 0)
        // La lumière : la page s'assombrit en se levant, son verso s'éclaire en se posant.
        t.ombre.opacity = Float(p < 0.5 ? 0.36 * p : 0.18)
        t.ombreDos.opacity = Float(p > 0.5 ? 0.36 * (1 - p) : 0.18)
        // Le bord libre de la page, vu d'en haut, et l'ombre qui tombe juste à côté, du côté qu'il
        // découvre (avant la moitié) ou qu'il recouvre (après). Plus la page est levée, plus
        // l'ombre est large et soutenue.
        let w = t.cadre.width, levee = sin(.pi * p)
        let charniere = t.sens > 0 ? t.cadre.minX : t.cadre.maxX
        let bord = charniere + (t.sens > 0 ? 1 : -1) * w * cos(.pi * p)
        let largeur = 24 + 90 * levee
        // Vers où l'ombre s'étend depuis le bord : loin de la charnière avant la moitié, vers elle après.
        let versLaDroite = (t.sens > 0) == (p < 0.5)
        t.ombrePortee.frame = CGRect(x: versLaDroite ? bord : bord - largeur, y: t.cadre.minY,
                                     width: largeur, height: t.cadre.height)
        let fonce = UIColor.black.withAlphaComponent(0.45).cgColor, clair = UIColor.clear.cgColor
        t.ombrePortee.colors = versLaDroite ? [fonce, clair] : [clair, fonce]
        t.ombrePortee.opacity = Float(levee)
        CATransaction.commit()
    }

    private func finir(_ t: Tour, valider: Bool) {
        let depart = t.avancement, cible: CGFloat = valider ? 1 : 0
        let duree = max(0.18, 0.5 * Double(abs(cible - depart)))
        let debut = CACurrentMediaTime()
        // Une horloge d'affichage plutôt qu'une animation implicite : la page part d'où le doigt
        // l'a laissée, et l'ombre suit la même courbe.
        let horloge = CADisplayLink(target: Pas { lien in
            let x = min(1, (CACurrentMediaTime() - debut) / duree)
            let lisse = CGFloat(1 - pow(1 - x, 3))
            self.poser(t, depart + (cible - depart) * lisse)
            if x >= 1 {
                lien.invalidate()
                self.conclure(t, valide: valider)
            }
        }, selector: #selector(Pas.tic(_:)))
        horloge.add(to: .main, forMode: .common)
    }

    private func conclure(_ t: Tour, valide: Bool) {
        if valide {
            t.scene.removeFromSuperlayer()
            t.cache.removeFromSuperview()
            tour = nil
        } else {
            // Reposée : on revient à la double page d'avant, puis on retire la page.
            planche -= t.sens
            afficher(anime: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                t.scene.removeFromSuperlayer()
                t.cache.removeFromSuperview()
                self.tour = nil
            }
        }
    }
}

/// La cible d'une horloge d'affichage : CADisplayLink veut un objet et un sélecteur.
private final class Pas: NSObject {
    let action: (CADisplayLink) -> Void
    init(_ action: @escaping (CADisplayLink) -> Void) { self.action = action }
    @objc func tic(_ lien: CADisplayLink) { action(lien) }
}
