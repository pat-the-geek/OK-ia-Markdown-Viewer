import SwiftUI
import PencilKit
import WebKit

/// Option Analytic (1.4) — le calque PencilKit du mode « Annoter », posé sur la vue web du lecteur.
///
/// Il ne garde rien : chaque trait devient une annotation ancrée au texte (Web/annotations.js),
/// puis quitte le calque. Surligner et souligner : le début et la fin du trait désignent une plage
/// de texte, aussitôt. Écrire : les traits s'accumulent, puis, après une pause ou au premier
/// défilement, deviennent une image accrochée au bloc sous lequel ils ont été tracés. La gomme :
/// ce que le trait touche disparaît.
///
/// Le calque ne couvre que la partie visible de la page et la suit au défilement. Il est dans la
/// vue de défilement de WebKit : avec le crayon, le doigt continue de faire défiler la page ; sans
/// crayon (iPhone, Mac, simulateur), on dessine d'un doigt et l'on fait défiler à deux.
///
/// Un calque par page : dans le livre, chacune des deux pages a le sien (la page de droite est une
/// copie du document, où les annotations s'ancrent au même texte).
@MainActor
final class CalqueAnnotation: NSObject, PKCanvasViewDelegate {
    private weak var webView: WKWebView?
    private let canvas = PKCanvasView()
    private let annotations: AnnotationsDocument
    private var suiviDefilement: NSKeyValueObservation?
    private var minuterie: Timer?
    private var traitsConnus = 0
    private var retouche = false
    private var toucherMinimal = 1

    init(annotations: AnnotationsDocument) {
        self.annotations = annotations
        super.init()
    }

    /// Le crayon seul dessine quand l'utilisateur l'a choisi dans les réglages du système (et
    /// qu'un crayon est jumelé) ; sinon, le doigt ou la souris.
    static var crayonSeul: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIPencilInteraction.prefersPencilOnlyDrawing
        #endif
    }

    func installer(sur vue: WKWebView) {
        webView = vue
        let defilement = vue.scrollView
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.delegate = self
        canvas.drawingPolicy = Self.crayonSeul ? .pencilOnly : .anyInput
        canvas.overrideUserInterfaceStyle = .light   // les couleurs choisies, de jour comme de nuit
        canvas.accessibilityLabel = tr("Annoter")
        defilement.addSubview(canvas)
        caler()
        toucherMinimal = defilement.panGestureRecognizer.minimumNumberOfTouches
        if !Self.crayonSeul { defilement.panGestureRecognizer.minimumNumberOfTouches = 2 }
        suiviDefilement = defilement.observe(\.contentOffset) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Une note en cours d'écriture ne suit pas le texte : on la fixe avant de bouger.
                if !self.canvas.drawing.strokes.isEmpty, self.annotations.outil == .ecrire { self.fixerEcriture() }
                self.caler()
            }
        }
        outilChange()
    }

    func retirer() {
        fixerEcriture()
        minuterie?.invalidate()
        suiviDefilement = nil
        webView?.scrollView.panGestureRecognizer.minimumNumberOfTouches = toucherMinimal
        canvas.removeFromSuperview()
    }

    private func caler() {
        guard let s = webView?.scrollView else { return }
        canvas.frame = CGRect(origin: s.contentOffset, size: s.bounds.size)
    }

    func outilChange() {
        fixerEcriture()
        let c = annotations.couleur
        switch annotations.outil {
        case .surligner: canvas.tool = PKInkingTool(.marker, color: Self.fond(c), width: 24)
        case .souligner: canvas.tool = PKInkingTool(.pen, color: Self.encre(c), width: 3)
        case .ecrire:    canvas.tool = PKInkingTool(.pen, color: Self.encre(c), width: 3)
        case .gomme:     canvas.tool = PKInkingTool(.pen, color: UIColor.systemGray.withAlphaComponent(0.35), width: 14)
        }
    }

    // MARK: Couleurs — les mêmes que Web/annotations.css

    static func fond(_ c: Annotation.Couleur) -> UIColor {
        switch c {
        case .jaune: return UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 0.5)
        case .vert:  return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0.4)
        case .rose:  return UIColor(red: 1, green: 0.22, blue: 0.53, alpha: 0.35)
        case .bleu:  return UIColor(red: 0.04, green: 0.52, blue: 1, alpha: 0.35)
        }
    }

    static func encre(_ c: Annotation.Couleur) -> UIColor {
        switch c {
        case .jaune: return UIColor(red: 0.91, green: 0.59, blue: 0.18, alpha: 1)   // l'orange d'OK-ia
        case .vert:  return UIColor(red: 0.14, green: 0.63, blue: 0.28, alpha: 1)
        case .rose:  return UIColor(red: 0.90, green: 0.16, blue: 0.47, alpha: 1)
        case .bleu:  return UIColor(red: 0.04, green: 0.43, blue: 0.90, alpha: 1)
        }
    }

    // MARK: Les traits

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        minuterie?.invalidate()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !retouche else { return }
        let traits = canvas.drawing.strokes
        defer { traitsConnus = canvas.drawing.strokes.count }
        guard traits.count > traitsConnus, let trait = traits.last else { return }
        switch annotations.outil {
        case .ecrire:
            // Une pause, et la note est fixée.
            minuterie?.invalidate()
            minuterie = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.fixerEcriture() }
            }
        case .surligner, .souligner:
            effacerDernier()
            Task { await ancrerTexte(trait) }
        case .gomme:
            effacerDernier()
            Task { await gommer(trait) }
        }
    }

    private func effacerDernier() {
        retouche = true
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes.dropLast())
        retouche = false
    }

    /// Les points d'un trait, dans la vue web.
    private func points(_ trait: PKStroke) -> [CGPoint] {
        guard let vue = webView else { return [] }
        return trait.path.map { canvas.convert($0.location.applying(trait.transform), to: vue) }
    }

    private func ancrerTexte(_ trait: PKStroke) async {
        if await poserSurMedia(trait) { return }
        var pts = points(trait)
        guard let premier = pts.first, let dernier = pts.last else { return }
        // On souligne SOUS la ligne : le texte visé est juste au-dessus du trait.
        if annotations.outil == .souligner { pts = [premier, dernier].map { CGPoint(x: $0.x, y: $0.y - 9) } }
        else { pts = [premier, dernier] }
        guard let vue = webView, let ancre = await PontAnnotations.ancrerTexte(vue, de: pts[0], a: pts[1]) else { return }
        let genre: Annotation.Genre = annotations.outil == .souligner ? .souligne : .surligne
        annotations.ajouter(Annotation(type: genre, couleur: annotations.couleur, ancre: ancre))
    }

    /// Un diagramme, une image ou une carte n'ont pas de texte à surligner : le trait du stabilo (ou
    /// du soulignement) y devient une note, ancrée au dessin comme l'écriture (Patrick, 30/10/2026 :
    /// « le dessin sur diagramme fonctionne mais pas le stabilo »). Sur une image, chercher le texte
    /// d'abord l'aurait accroché au paragraphe voisin.
    private func poserSurMedia(_ trait: PKStroke) async -> Bool {
        guard let vue = webView else { return false }
        let dessin = PKDrawing(strokes: [trait])
        let cadre = dessin.bounds.insetBy(dx: -6, dy: -6)
        let dansLaVue = canvas.convert(cadre, to: vue)
        let couleur = annotations.couleur
        guard let ancre = await PontAnnotations.ancrerEncre(vue, dansLaVue), ancre.media != nil else { return false }
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = dessin.image(from: cadre, scale: 3)
        }
        guard let png = image.pngData() else { return false }
        annotations.ajouter(Annotation(type: .encre, couleur: couleur, ancre: ancre,
                                       image: png.base64EncodedString(), trace: dessin.dataRepresentation()))
        return true
    }

    private func gommer(_ trait: PKStroke) async {
        let pts = points(trait)
        // Un point sur six suffit : un trait de gomme est dense.
        var vus = Set<String>()
        guard let vue = webView else { return }
        for (i, p) in pts.enumerated() where i % 6 == 0 || i == pts.count - 1 {
            if let id = await PontAnnotations.annotationSous(vue, p), vus.insert(id).inserted { annotations.supprimer(id) }
        }
    }

    /// Les traits d'écriture deviennent une note : l'image, et son bloc.
    func fixerEcriture() {
        minuterie?.invalidate()
        let dessin = canvas.drawing
        guard !dessin.strokes.isEmpty, let vue = webView else { return }
        retouche = true
        canvas.drawing = PKDrawing()
        traitsConnus = 0
        retouche = false
        // Le calque suit le défilement : sa place dans la vue web se prend maintenant, pas après
        // les questions à la page.
        let decalage = canvas.convert(CGPoint.zero, to: vue)
        let couleur = annotations.couleur
        Task {
            // Des traits tracés d'affilée sur des médias différents (un tableau puis une carte)
            // font des notes distinctes : réunis, la note s'accrochait au média sous leur centre, et
            // la carte coupait le reste (30/10/2026). Sur le texte, ils restent ensemble.
            var groupes: [String: [PKStroke]] = [:], ordre: [String] = []
            for trait in dessin.strokes {
                let b = trait.renderBounds
                let centre = CGPoint(x: b.midX + decalage.x, y: b.midY + decalage.y)
                let cle = await PontAnnotations.mediaNomme(vue, centre) ?? "texte"
                if groupes[cle] == nil { ordre.append(cle) }
                groupes[cle, default: []].append(trait)
            }
            for cle in ordre {
                await poserEcriture(PKDrawing(strokes: groupes[cle] ?? []), decalage: decalage,
                                    vue: vue, couleur: couleur)
            }
        }
    }

    /// Une note manuscrite : l'image de ses traits, et son ancre.
    private func poserEcriture(_ dessin: PKDrawing, decalage: CGPoint, vue: WKWebView,
                               couleur: Annotation.Couleur) async {
        guard !dessin.strokes.isEmpty else { return }
        let cadre = dessin.bounds.insetBy(dx: -6, dy: -6)
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = dessin.image(from: cadre, scale: 3)
        }
        guard let png = image.pngData(),
              let ancre = await PontAnnotations.ancrerEncre(vue, cadre.offsetBy(dx: decalage.x, dy: decalage.y))
        else { return }
        annotations.ajouter(Annotation(type: .encre, couleur: couleur, ancre: ancre,
                                       image: png.base64EncodedString(), trace: dessin.dataRepresentation()))
    }
}

/// Les questions que le calque pose à la page (Web/annotations.js) : la plage de texte sous un
/// trait, le bloc sous une note, l'annotation sous la gomme. Pour n'importe quelle page du lecteur.
@MainActor
enum PontAnnotations {
    /// Un point de la vue web (ses coordonnées) en point de la page : le défilement compris, le
    /// zoom retiré. C'est ce que `annotations.js` attend.
    static func pointPage(_ vue: WKWebView, _ p: CGPoint) -> CGPoint {
        let s = vue.scrollView
        let contenu = vue.convert(p, to: s)
        let z = max(s.zoomScale, 0.01)
        return CGPoint(x: contenu.x / z, y: contenu.y / z)
    }

    private static func objet<T: Decodable>(_ vue: WKWebView, _ js: String, _ type: T.Type) async -> T? {
        await withCheckedContinuation { suite in
            vue.evaluateJavaScript(js) { valeur, _ in
                guard let s = valeur as? String, let data = s.data(using: .utf8) else { suite.resume(returning: nil); return }
                suite.resume(returning: try? JSONDecoder().decode(T.self, from: data))
            }
        }
    }

    /// La plage de texte qu'un trait couvre, de `debut` à `fin` (points de la vue web).
    static func ancrerTexte(_ vue: WKWebView, de debut: CGPoint, a fin: CGPoint) async -> AncreAnnotation? {
        let a = pointPage(vue, debut), b = pointPage(vue, fin)
        return await objet(vue, "JSON.stringify(window.OKIA_ANNOT ? window.OKIA_ANNOT.ancrerTexte(\(a.x), \(a.y), \(b.x), \(b.y)) : null)",
                           AncreAnnotation.self)
    }

    /// Le bloc sous un tracé (rectangle de la vue web) et sa place dans ce bloc.
    static func ancrerEncre(_ vue: WKWebView, _ r: CGRect) async -> AncreAnnotation? {
        let o = pointPage(vue, r.origin), c = pointPage(vue, CGPoint(x: r.maxX, y: r.maxY))
        return await objet(vue, "JSON.stringify(window.OKIA_ANNOT ? window.OKIA_ANNOT.ancrerEncre(\(o.x), \(o.y), \(c.x - o.x), \(c.y - o.y)) : null)",
                           AncreAnnotation.self)
    }

    /// Le média sous un point de la vue web (« carte:0 »), ou nil sur le texte.
    static func mediaNomme(_ vue: WKWebView, _ p: CGPoint) async -> String? {
        let q = pointPage(vue, p)
        struct Reponse: Decodable { let nom: String? }
        return await objet(vue, "JSON.stringify({ nom: window.OKIA_ANNOT && window.OKIA_ANNOT.mediaNomme ? window.OKIA_ANNOT.mediaNomme(\(q.x), \(q.y)) : null })",
                           Reponse.self)?.nom
    }

    /// L'annotation sous un point de la vue web (la gomme).
    static func annotationSous(_ vue: WKWebView, _ p: CGPoint) async -> String? {
        let q = pointPage(vue, p)
        // Enveloppé dans un objet : une chaîne seule n'est pas un document JSON que le décodeur rende.
        struct Reponse: Decodable { let id: String? }
        return await objet(vue, "JSON.stringify({ id: window.OKIA_ANNOT ? window.OKIA_ANNOT.sousLePoint(\(q.x), \(q.y)) : null })",
                           Reponse.self)?.id
    }
}

/// La palette du mode « Annoter » : l'outil, la couleur, et Terminé. Dans le diaporama, deux
/// flèches de plus : le calque prend le doigt, la diapositive ne se balaie plus.
struct PaletteAnnotation: View {
    @ObservedObject var annotations: AnnotationsDocument
    /// Terminé ; par défaut, le mode « Annoter » du lecteur se referme.
    var terminer: (() -> Void)?
    var precedente: (() -> Void)?
    var suivante: (() -> Void)?
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    /// Trois mises en page, la première qui tient : en ligne ; en ligne resserrée ; sur deux
    /// rangées (Patrick, 28/10/2026 : sur le Duo replié, la palette était coupée à gauche).
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { flecheGauche(36); outils(40); separateur(4); couleurs(34, 24); flecheDroite(36); separateur(4); boutonTermine(40) }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .glassEffect(.regular.interactive(), in: .capsule)
            HStack(spacing: 2) { flecheGauche(30); outils(34); separateur(2); couleurs(28, 20); flecheDroite(30); separateur(2); boutonTermine(34) }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .glassEffect(.regular.interactive(), in: .capsule)
            VStack(spacing: 0) {
                HStack(spacing: 2) { flecheGauche(30); outils(34); separateur(2); boutonTermine(34) }
                HStack(spacing: 2) { couleurs(30, 22); flecheDroite(30) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
    }

    @ViewBuilder private func flecheGauche(_ cote: CGFloat) -> some View {
        if let precedente {
            Button(action: precedente) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: cote, height: 40)
            }
            .tint(.primary)
            .accessibilityLabel(tr("Diapositive précédente"))
        }
    }

    @ViewBuilder private func flecheDroite(_ cote: CGFloat) -> some View {
        if let suivante {
            separateur(2)
            Button(action: suivante) {
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).frame(width: cote, height: 40)
            }
            .tint(.primary)
            .accessibilityLabel(tr("Diapositive suivante"))
        }
    }

    private func outils(_ cote: CGFloat) -> some View {
        ForEach(AnnotationsDocument.Outil.allCases) { o in
            Button { annotations.outil = o } label: {
                Image(systemName: o.symbole)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: cote, height: 40)
                    .background(Circle().fill(annotations.outil == o ? orange.opacity(0.22) : .clear))
            }
            .tint(annotations.outil == o ? orange : .primary)
            .accessibilityLabel(o.libelle)
            .accessibilityAddTraits(annotations.outil == o ? .isSelected : [])
        }
    }

    private func couleurs(_ cote: CGFloat, _ pastille: CGFloat) -> some View {
        ForEach(Annotation.Couleur.allCases, id: \.self) { c in
            Button { annotations.couleur = c } label: {
                Circle()
                    .fill(Color(uiColor: CalqueAnnotation.encre(c)))
                    .frame(width: pastille, height: pastille)
                    .overlay(Circle().stroke(Color.primary, lineWidth: annotations.couleur == c ? 2.5 : 0).padding(-4))
                    .frame(width: cote, height: 40)
            }
            .disabled(annotations.outil == .gomme)
            .accessibilityLabel(nomCouleur(c))
            .accessibilityAddTraits(annotations.couleur == c ? .isSelected : [])
        }
    }

    private func separateur(_ marge: CGFloat) -> some View {
        Divider().frame(height: 26).padding(.horizontal, marge)
    }

    private func boutonTermine(_ cote: CGFloat) -> some View {
        Button { if let terminer { terminer() } else { annotations.actif = false } } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
                .frame(width: cote, height: 40)
        }
        .tint(orange)
        .accessibilityLabel(tr("Terminé"))
    }

    private func nomCouleur(_ c: Annotation.Couleur) -> String {
        switch c {
        case .jaune: return tr("Jaune")
        case .vert:  return tr("Vert")
        case .rose:  return tr("Rose")
        case .bleu:  return tr("Bleu")
        }
    }
}
