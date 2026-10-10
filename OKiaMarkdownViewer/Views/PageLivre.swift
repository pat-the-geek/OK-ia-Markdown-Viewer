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
    /// Un diagramme, un bloc ou une image touché : il s'ouvre en plein écran, comme à gauche.
    var surDiagramme: (TappedDiagram) -> Void = { _ in }
    var surImage: (TappedImage) -> Void = { _ in }
    var surCarte: (TappedCarte) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "ready")
        controller.add(context.coordinator, name: "tapPage")
        controller.add(context.coordinator, name: "diagramTapped")
        controller.add(context.coordinator, name: "imageTapped")
        controller.add(context.coordinator, name: "carteTapped")
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
            if message.name == "diagramTapped", let d = message.body as? [String: Any], let svg = d["svg"] as? String {
                parent.surDiagramme(TappedDiagram(svg: svg, title: (d["title"] as? String) ?? "")); return
            }
            if message.name == "carteTapped", let d = message.body as? [String: Any], let cfg = d["cfg"] as? String {
                parent.surCarte(TappedCarte(cfg: cfg)); return
            }
            if message.name == "imageTapped", let d = message.body as? [String: Any], let src = d["src"] as? String {
                parent.surImage(TappedImage(src: src)); return
            }
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
    /// Un peu d'air au-dessus de la première ligne de chaque page (Patrick).
    static let margeHaut: CGFloat = 14
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
        #if DEBUG
        lancerDemo()
        #endif
    }

    #if DEBUG
    /// Film du livre (OKIA_DEMO_LIVRE = secondes avant le début) : le livre tourne ses pages
    /// lui-même, au pas d'un doigt lent — page suivante, page soulevée puis reposée, page
    /// suivante, retour, page suivante. Les gestes injectés dans le simulateur arrivaient avec
    /// des dizaines de secondes de retard pendant l'enregistrement.
    private var demoLancee = false

    private func lancerDemo() {
        guard !demoLancee, let v = ProcessInfo.processInfo.environment["OKIA_DEMO_LIVRE"],
              let attente = Double(v) else { return }
        demoLancee = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(attente))
            let etapes: [(sens: Int, jusqua: CGFloat, valider: Bool)] =
                [(1, 0.72, true), (1, 0.4, false), (1, 0.72, true), (-1, 0.72, true), (1, 0.72, true)]
            for e in etapes {
                await self?.glisser(sens: e.sens, jusqua: e.jusqua, valider: e.valider)
                try? await Task.sleep(for: .seconds(3.5))
            }
        }
    }

    /// Un doigt qui soulève la page jusqu'à `jusqua` en 2,4 s, puis la lâche : elle retombe sous
    /// son poids, comme sous un vrai doigt.
    private func glisser(sens: Int, jusqua: CGFloat, valider: Bool) async {
        guard tour == nil, !enPreparation else { return }
        decisionEnAttente = nil
        dernierAvancement = 0
        preparer(sens)
        for _ in 0..<60 where tour == nil { try? await Task.sleep(for: .milliseconds(50)) }
        guard let t = tour else { return }
        let duree = 2.4, debut = Date()
        while true {
            let x = min(1, Date().timeIntervalSince(debut) / duree)
            let e = x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
            poser(t, jusqua * CGFloat(e))
            if x >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        if !valider { try? await Task.sleep(for: .milliseconds(500)) }
        finir(t, valider: valider)
    }
    #endif

    func delier() {
        attente?.cancel()
        for (vue, g) in gestes { vue.removeGestureRecognizer(g) }
        gestes = []
        for vue in [gauche, droite].compactMap({ $0 }) {
            vue.scrollView.isScrollEnabled = true
            vue.scrollView.backgroundColor = .clear
            // La largeur du livre pouvait dépasser la page devenue plus étroite : le texte gardait
            // un décalage horizontal et sortait coupé à gauche.
            vue.scrollView.contentOffset.x = 0
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
        // Pendant qu'une page tourne, les deux vues montrent les pages du tour : les replacer
        // maintenant décalait la page de droite (vide, ou la gauche en double). Après le tour.
        if tour != nil || enPreparation { recalculerPlusTard(); return }
        // La page commence un peu sous le haut de l'écran : sa hauteur utile en est d'autant réduite.
        let h = floor(min(visible(g), visible(d))) - Self.margeHaut
        guard h > 100 else { return }
        let lu = debut(2 * planche)
        teindreFond(g, d)
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

    /// Le fond du livre, celui de la page (thème, jour ou nuit) : au-dessus du début du document,
    /// la vue web transparente laissait voir le noir de la fenêtre — une bande noire sous la barre
    /// de l'heure sur iPad.
    private func teindreFond(_ g: WKWebView, _ d: WKWebView) {
        g.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") { r, _ in
            guard let css = r as? String else { return }
            let n = css.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
            guard n.count >= 3 else { return }
            let a = n.count >= 4 ? n[3] : 1
            guard a > 0.5 else { return }
            let c = UIColor(red: n[0] / 255, green: n[1] / 255, blue: n[2] / 255, alpha: 1)
            g.scrollView.backgroundColor = c
            d.scrollView.backgroundColor = c
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
        let m = Int(Self.margeHaut)
        // Un séparateur à gauche : pas de second à droite, sur la même double page.
        let sepGauche = debut(pg) + hauteur - cacheG >= 140
        g.evaluateJavaScript("window.OKIA && window.OKIA.cacheLivre(\(Int(cacheG)), \(Int(hauteur)), \(Int(debut(pg))), \(m), false)")
        d.evaluateJavaScript("window.OKIA && window.OKIA.cacheLivre(\(Int(cacheD)), \(Int(hauteur)), \(Int(debut(pd))), \(m), \(sepGauche))")
        g.scrollView.contentOffset.y = debut(pg) - g.scrollView.adjustedContentInset.top - Self.margeHaut
        d.scrollView.contentOffset.y = debut(pd) - d.scrollView.adjustedContentInset.top - Self.margeHaut
    }

    // MARK: La page qui tourne

    /// Une page qui tourne, comme un livre, et qui suit le doigt : en avant, la page de droite se
    /// soulève autour de la pliure et découvre dessous la nouvelle page de droite ; son verso
    /// montre la nouvelle page de gauche. Son bord libre reste sous le doigt ; lâchée, elle retombe
    /// du côté où elle penche le plus. Les images des pages viennent de
    /// WebKit (`takeSnapshot`) ; la page qui tourne vit dans la fenêtre, pour franchir la pliure.
    private final class Tour {
        let sens: Int
        let leve: WKWebView
        let reste: WKWebView
        let cache: UIView
        let scene: CALayer
        let page: CATransformLayer
        /// La page en bandes verticales, chacune articulée sur la précédente : de la charnière au
        /// bord libre. Elles se courbent l'une après l'autre, et la page plie comme une feuille.
        let bandes: [Bande]
        /// L'ombre que la page levée jette sur la page qu'elle découvre, ou sur celle où elle va se poser.
        let ombrePortee: CAGradientLayer
        let cadre: CGRect
        var avancement: CGFloat = 0
        init(sens: Int, leve: WKWebView, reste: WKWebView, cache: UIView, scene: CALayer,
             page: CATransformLayer, bandes: [Bande],
             ombrePortee: CAGradientLayer, cadre: CGRect) {
            self.sens = sens; self.leve = leve; self.reste = reste; self.cache = cache
            self.scene = scene; self.page = page; self.bandes = bandes
            self.ombrePortee = ombrePortee; self.cadre = cadre
        }
    }

    private struct Bande {
        let couche: CATransformLayer
        let ombre: CALayer
        let ombreDos: CALayer
    }
    private static let nombreDeBandes = 14

    private var tour: Tour?
    private var enPreparation = false
    /// Le doigt a lâché pendant la préparation : la décision attend que la page soit prête.
    private var decisionEnAttente: Bool?
    private var dernierAvancement: CGFloat = 0

    private func image(_ vue: WKWebView, _ fin: @escaping (UIImage?) -> Void) {
        vue.takeSnapshot(with: nil) { image, _ in fin(image) }
    }

    private func apresPeinture(_ vue: WKWebView, _ fin: @escaping () -> Void) {
        vue.callAsyncJavaScript(
            "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(r, 30))));",
            arguments: [:], in: nil, in: .page) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: fin)
        }
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

    /// L'avancement de la page pour un déplacement du doigt : le bord libre de la page reste sous
    /// le doigt. Vu d'en haut, ce bord est à w·cos(πp) de la charnière ; parti du bord extérieur,
    /// il atteint la pliure quand le doigt a parcouru une largeur de page (p = ½), et se pose de
    /// l'autre côté après deux.
    private func avancement(dx: CGFloat, sens: Int, largeur: CGFloat) -> CGFloat {
        let parcouru = (sens > 0 ? -dx : dx) / largeur
        return acos(min(1, max(-1, 1 - parcouru))) / .pi
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
            let sens = tour?.sens ?? (dx < 0 ? 1 : -1)
            let p = avancement(dx: dx, sens: sens, largeur: largeur)
            if let t = tour { poser(t, p) } else { dernierAvancement = p }
        case .ended, .cancelled, .failed:
            // Lâchée, la page retombe du côté où elle penche le plus : au-delà de la verticale, elle
            // se pose de l'autre côté ; en deçà, elle revient là où on était.
            let sens = tour?.sens ?? (dx < 0 ? 1 : -1)
            let p = tour?.avancement ?? avancement(dx: dx, sens: sens, largeur: largeur)
            let valider = pan.state == .ended && p > 0.5
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
                // Posée à côté de la vue web, pas dedans : sa capture la reprenait, et le verso
                // montrait l'ancienne page au lieu de la nouvelle.
                let cache = UIImageView(image: ancienne)
                if let parent = reste.superview {
                    cache.frame = reste.frame
                    parent.insertSubview(cache, aboveSubview: reste)
                } else {
                    cache.frame = reste.bounds
                    reste.addSubview(cache)
                }
                // La page qui va se lever garde son image le temps de la préparation : sans elle,
                // elle passait au blanc pendant que WebKit peignait la page suivante dessous.
                let attente = UIImageView(image: recto)
                attente.frame = leve.frame
                leve.superview?.insertSubview(attente, aboveSubview: leve)
                self.planche = k
                self.afficher(anime: false)
                // Le verso est la nouvelle page : on attend que WebKit l'ait peinte (deux images
                // d'affichage dans la page), sans quoi l'image reprenait l'ancienne.
                self.apresPeinture(reste) {
                    self.image(reste) { verso in
                        let t = self.construire(recto: recto, verso: verso ?? ancienne, leve: leve,
                                                reste: reste, cache: cache, sens: sens, fenetre: fenetre)
                        attente.removeFromSuperview()
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

        // Les bandes, de la charnière vers le bord libre. Chacune porte sa part du recto et, au dos,
        // sa part du verso — retournée, puisque la page se posera de l'autre côté de la pliure.
        let n = Self.nombreDeBandes, largeur = cadre.width / CGFloat(n), h = cadre.height
        var bandes: [Bande] = []
        var parent: CALayer = page
        for i in 0..<n {
            let b = CATransformLayer()
            b.bounds = CGRect(x: 0, y: 0, width: largeur, height: h)
            b.anchorPoint = CGPoint(x: sens > 0 ? 0 : 1, y: 0.5)
            if i == 0 {
                b.position = CGPoint(x: sens > 0 ? 0 : cadre.width, y: h / 2)
            } else {
                b.position = CGPoint(x: sens > 0 ? largeur : 0, y: h / 2)
            }
            // La part de l'image : en avant, la i-ième bande depuis la gauche du recto ; en
            // arrière, depuis sa droite. Le verso, lui, se lit dans l'autre sens.
            let x0 = CGFloat(i) / CGFloat(n), x1 = CGFloat(i + 1) / CGFloat(n)
            let partRecto = sens > 0 ? CGRect(x: x0, y: 0, width: x1 - x0, height: 1)
                                     : CGRect(x: 1 - x1, y: 0, width: x1 - x0, height: 1)
            let partVerso = sens > 0 ? CGRect(x: 1 - x1, y: 0, width: x1 - x0, height: 1)
                                     : CGRect(x: x0, y: 0, width: x1 - x0, height: 1)
            func face(_ image: UIImage, _ part: CGRect, retournee: Bool) -> CALayer {
                let f = CALayer()
                // Un demi-point de recouvrement : sans lui, un fil de jour passait entre deux bandes.
                f.frame = b.bounds.insetBy(dx: -0.5, dy: 0)
                f.contents = image.cgImage
                f.contentsRect = part
                f.contentsGravity = .resize
                f.isDoubleSided = false
                if retournee { f.transform = CATransform3DMakeRotation(.pi, 0, 1, 0) }
                let o = CALayer()
                o.frame = f.bounds
                o.backgroundColor = UIColor.black.cgColor
                o.opacity = 0
                f.addSublayer(o)
                b.addSublayer(f)
                return o
            }
            let ombre = face(recto, partRecto, retournee: false)
            let ombreDos = face(verso, partVerso, retournee: true)
            parent.addSublayer(b)
            bandes.append(Bande(couche: b, ombre: ombre, ombreDos: ombreDos))
            parent = b
        }
        // L'ombre portée : une bande dégradée au pied du bord libre de la page, sous elle.
        let ombrePortee = CAGradientLayer()
        ombrePortee.startPoint = CGPoint(x: 0, y: 0.5)
        ombrePortee.endPoint = CGPoint(x: 1, y: 0.5)
        ombrePortee.opacity = 0
        scene.addSublayer(ombrePortee)
        scene.addSublayer(page)
        fenetre.layer.addSublayer(scene)
        return Tour(sens: sens, leve: leve, reste: reste, cache: cache, scene: scene, page: page,
                    bandes: bandes, ombrePortee: ombrePortee, cadre: cadre)
    }

    /// p : de 0 (à plat, du côté de départ) à 1 (posée de l'autre côté).
    private func poser(_ t: Tour, _ p: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        t.avancement = p
        // La courbure : nulle à plat, plus forte page dressée. Le bord libre, qu'on tient, va devant ;
        // la partie près de la pliure suit — la feuille se plie au lieu de pivoter d'un bloc. Les
        // angles des bandes vont de θ − c/2 à θ + c/2, bornés à [0, π].
        let n = t.bandes.count, theta = CGFloat.pi * p
        let c = 1.25 * sin(.pi * p)
        let signe: CGFloat = t.sens > 0 ? -1 : 1
        var precedent: CGFloat = 0
        var bordX: CGFloat = 0
        let pas = t.cadre.width / CGFloat(n)
        for (i, b) in t.bandes.enumerated() {
            let f = (CGFloat(i) + 0.5) / CGFloat(n) - 0.5
            let phi = min(.pi, max(0, theta + c * f))
            b.couche.transform = CATransform3DMakeRotation(signe * (phi - precedent), 0, 1, 0)
            precedent = phi
            // La lumière suit la pente de chaque bande : le recto s'assombrit en se détournant, le
            // verso s'éclaire en se posant.
            b.ombre.opacity = Float(0.34 * (1 - cos(phi)) / 2)
            b.ombreDos.opacity = Float(0.34 * (1 + cos(phi)) / 2)
            bordX += pas * cos(phi)
        }
        // Le bord libre de la page, vu d'en haut, et l'ombre qui tombe juste à côté, du côté qu'il
        // découvre (avant la moitié) ou qu'il recouvre (après). Plus la page est levée, plus
        // l'ombre est large et soutenue.
        let levee = sin(.pi * p)
        let charniere = t.sens > 0 ? t.cadre.minX : t.cadre.maxX
        let bord = charniere + (t.sens > 0 ? 1 : -1) * bordX
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

    /// La chute de la page, sous la pesanteur. Mesurée depuis la verticale (φ = 0, la page dressée
    /// au-dessus de la pliure), la page lâchée accélère vers le côté où elle penche — φ'' = k·sin φ,
    /// comme une feuille qui bascule —, se pose à plat (φ = ±π/2) et rebondit un peu, puis se tait.
    /// Tournée d'un coup (balayage vertical), elle reçoit juste l'élan qu'il faut pour passer la
    /// verticale, et tombe ensuite d'elle-même.
    private func finir(_ t: Tour, valider: Bool) {
        let k: CGFloat = 34                       // rad/s² : la pesanteur, à l'échelle d'une page
        let cible: CGFloat = valider ? .pi / 2 : -.pi / 2
        var phi = CGFloat.pi * t.avancement - .pi / 2
        // L'élan de départ : un petit coup vers le côté choisi ; s'il faut d'abord remonter jusqu'à
        // la verticale, juste assez d'énergie pour la franchir (½ω² + k·cos φ > k).
        let doitRemonter = valider ? phi < 0 : phi > 0
        var omega: CGFloat = doitRemonter ? sqrt(2 * k * (1 - cos(phi))) * 1.12 + 0.6 : 1.2
        if !valider { omega = -omega }
        var rebonds = 0
        var avant = CACurrentMediaTime()
        let horloge = CADisplayLink(target: Pas { lien in
            let maintenant = CACurrentMediaTime()
            var reste = min(0.05, maintenant - avant)
            avant = maintenant
            // Petits pas d'intégration : la chute reste juste même si une image saute.
            while reste > 0 {
                let dt = CGFloat(min(reste, 1.0 / 240))
                reste -= Double(dt)
                omega += k * sin(phi) * dt
                phi += omega * dt
                // À plat : la page touche, rebondit un peu, puis s'arrête.
                if (valider && phi >= cible) || (!valider && phi <= cible) {
                    phi = cible
                    omega = -omega * 0.18
                    rebonds += 1
                    if abs(omega) < 0.7 || rebonds > 1 { omega = 0 }
                }
            }
            self.poser(t, (phi + .pi / 2) / .pi)
            if omega == 0 && phi == cible {
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
