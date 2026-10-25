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
@MainActor
final class CalqueAnnotation: NSObject, PKCanvasViewDelegate {
    private weak var webView: WKWebView?
    private let canvas = PKCanvasView()
    private let annotations: AnnotationsDocument
    private let web: ReaderWebController
    private var suiviDefilement: NSKeyValueObservation?
    private var minuterie: Timer?
    private var traitsConnus = 0
    private var retouche = false
    private var toucherMinimal = 1

    init(annotations: AnnotationsDocument, web: ReaderWebController) {
        self.annotations = annotations
        self.web = web
        super.init()
    }

    /// Le crayon seul dessine quand l'utilisateur l'a choisi dans les réglages du système (et
    /// qu'un crayon est jumelé) ; sinon, le doigt ou la souris.
    private static var crayonSeul: Bool {
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
        var pts = points(trait)
        guard let premier = pts.first, let dernier = pts.last else { return }
        // On souligne SOUS la ligne : le texte visé est juste au-dessus du trait.
        if annotations.outil == .souligner { pts = [premier, dernier].map { CGPoint(x: $0.x, y: $0.y - 9) } }
        else { pts = [premier, dernier] }
        guard let ancre = await web.ancrerTexte(de: pts[0], a: pts[1]) else { return }
        let genre: Annotation.Genre = annotations.outil == .souligner ? .souligne : .surligne
        annotations.ajouter(Annotation(type: genre, couleur: annotations.couleur, ancre: ancre))
    }

    private func gommer(_ trait: PKStroke) async {
        let pts = points(trait)
        // Un point sur six suffit : un trait de gomme est dense.
        var vus = Set<String>()
        for (i, p) in pts.enumerated() where i % 6 == 0 || i == pts.count - 1 {
            if let id = await web.annotationSous(p), vus.insert(id).inserted { annotations.supprimer(id) }
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
        let cadre = dessin.bounds.insetBy(dx: -6, dy: -6)
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = dessin.image(from: cadre, scale: 3)
        }
        guard let png = image.pngData() else { return }
        let dansLaVue = canvas.convert(cadre, to: vue)
        let couleur = annotations.couleur
        Task {
            guard let ancre = await web.ancrerEncre(dansLaVue) else { return }
            annotations.ajouter(Annotation(type: .encre, couleur: couleur, ancre: ancre,
                                           image: png.base64EncodedString(), trace: dessin.dataRepresentation()))
        }
    }
}

/// La palette du mode « Annoter » : l'outil, la couleur, et Terminé.
struct PaletteAnnotation: View {
    @ObservedObject var annotations: AnnotationsDocument
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationsDocument.Outil.allCases) { o in
                Button { annotations.outil = o } label: {
                    Image(systemName: o.symbole)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(annotations.outil == o ? orange.opacity(0.22) : .clear))
                }
                .tint(annotations.outil == o ? orange : .primary)
                .accessibilityLabel(o.libelle)
                .accessibilityAddTraits(annotations.outil == o ? .isSelected : [])
            }
            Divider().frame(height: 26).padding(.horizontal, 4)
            ForEach(Annotation.Couleur.allCases, id: \.self) { c in
                Button { annotations.couleur = c } label: {
                    Circle()
                        .fill(Color(uiColor: CalqueAnnotation.encre(c)))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.primary, lineWidth: annotations.couleur == c ? 2.5 : 0).padding(-4))
                        .frame(width: 34, height: 40)
                }
                .disabled(annotations.outil == .gomme)
                .accessibilityLabel(nomCouleur(c))
                .accessibilityAddTraits(annotations.couleur == c ? .isSelected : [])
            }
            Divider().frame(height: 26).padding(.horizontal, 4)
            Button { annotations.actif = false } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .tint(orange)
            .accessibilityLabel(tr("Terminé"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
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
