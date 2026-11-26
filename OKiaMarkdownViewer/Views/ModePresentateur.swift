import SwiftUI
import Combine
import WebKit

// Option Analytic (1.4) — le mode présentateur sur deux écrans (Patrick, 27/10/2026 : « commence
// par le mode présentateur sur deux écrans »). La diapositive sur l'écran du public ; sur l'appareil,
// la diapositive en cours (le diaporama habituel, qui se pilote), la suivante, les notes de
// l'orateur, un chronomètre et l'heure.
//
// - iPad et iPhone : un écran branché (câble ou AirPlay, hors recopie) devient l'écran du public,
//   par une scène « écran externe » (`EcranExterneDelegate`). Sans présentation en cours, sa fenêtre
//   reste cachée : le système recopie l'écran de l'appareil, comme sans md Viewer.
// - Mac : le bouton « Présenter sur un second écran » du diaporama ouvre une fenêtre « public », à
//   poser sur le projecteur et à mettre en plein écran.
//
// Les notes : les commentaires HTML de chaque diapositive — là où l'import PowerPoint range les notes
// de l'orateur (`<!-- … -->`).

/// La séance en cours : ce que les trois vues (présentateur, aperçu, public) partagent.
@MainActor
final class SeancePresentation: ObservableObject {
    static let partage = SeancePresentation()

    /// Le document présenté ; nil hors présentation.
    @Published var document: MarkdownDocument?
    @Published var index = 0
    @Published var total = 0
    /// La transition et le thème choisis par le présentateur.
    @Published var choix: [String: String] = [:]
    /// La traduction du diaporama (texte d'origine → traduction), pour le public aussi.
    @Published var traduction: [String: String] = [:]
    @Published var traductionActive = false
    /// Les notes de la diapositive en cours.
    @Published var notes = ""
    /// Un écran externe est branché (scène « écran externe », iPad et iPhone).
    @Published var ecranExterne = false
    /// La fenêtre du public est ouverte (Mac).
    @Published var fenetrePublique = false
    /// Les annotations du document présenté, pour les poser aussi sur l'écran du public.
    weak var annotations: AnnotationsDocument?

    // La couleur du temps (option Analytic, 26/11/2026, reprise d'iA Presenter) : le temps prévu de
    // chaque diapositive, et les chronomètres que la colonne du présentateur et la télécommande
    // comparent à lui.
    /// Le temps prévu de chaque diapositive, en secondes ; vide quand rien ne permet de le prévoir
    /// (ni notes de l'orateur, ni répétition de ce document).
    @Published var prevus: [TimeInterval] = []
    @Published private(set) var debut = Date()
    @Published private(set) var debutDiapo = Date()
    @Published private(set) var pause: Date?
    private var cumulPause: TimeInterval = 0
    private var pauseDiapo: TimeInterval = 0

    var prevuTotal: TimeInterval { prevus.reduce(0, +) }
    func prevu(_ i: Int) -> TimeInterval? { i >= 0 && i < prevus.count ? prevus[i] : nil }

    func ecoule(_ maintenant: Date = Date()) -> TimeInterval {
        max(0, (pause ?? maintenant).timeIntervalSince(debut) - cumulPause)
    }

    func ecouleDiapo(_ maintenant: Date = Date()) -> TimeInterval {
        max(0, (pause ?? maintenant).timeIntervalSince(debutDiapo) - pauseDiapo)
    }

    func basculerPause() {
        if let p = pause {
            let d = Date().timeIntervalSince(p)
            cumulPause += d; pauseDiapo += d; pause = nil
        } else { pause = Date() }
    }

    func remettreAZero() {
        debut = Date(); debutDiapo = debut; cumulPause = 0; pauseDiapo = 0; pause = nil
    }

    /// Une autre diapositive : son chronomètre repart.
    func changerDiapo(_ i: Int) {
        guard i != index else { return }
        index = i
        debutDiapo = pause ?? Date()
        pauseDiapo = 0
    }

    /// Le temps prévu : la durée visée de la dernière répétition de ce document, répartie selon les
    /// notes de chaque diapositive ; sinon l'estimation tirée des notes (130 mots par minute).
    func prevoir(estimation: [TimeInterval], avecNotes: Bool, visee: TimeInterval?) {
        let somme = estimation.reduce(0, +)
        if let v = visee, v > 0, somme > 0 {
            prevus = estimation.map { $0 * v / somme }
        } else {
            prevus = avecNotes ? estimation : []
        }
    }

    /// La durée visée de la dernière répétition, par document.
    static func cleVisee(_ document: MarkdownDocument) -> String {
        "okia.repetition.visee." + (document.sourceURL?.lastPathComponent ?? document.filename)
    }

    /// La vue du présentateur s'affiche : une présentation, un second écran, et l'option.
    var presentateur: Bool {
        document != nil && (ecranExterne || fenetrePublique) && AchatAnalytic.partage.acces
    }

    /// L'écran du public a quelque chose à montrer.
    var publicActif: Bool { document != nil && AchatAnalytic.partage.acces }

    func commencer(_ document: MarkdownDocument) {
        self.document = document
        index = 0
        total = 0
        notes = ""
        traduction = [:]
        traductionActive = false
        prevus = []
        remettreAZero()
    }

    func terminer() {
        document = nil
        notes = ""
    }

    /// Le bouton « Présenter sur un second écran » : sur Mac seulement. Sur iPad, la fenêtre du public
    /// s'ouvrait par-dessus le présentateur (simulateur, 27/10/2026) ; l'iPad et l'iPhone passent par
    /// l'écran externe, qui prend la diapositive de lui-même.
    static var fenetrePossible: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }
}

/// L'écran du public : la diapositive seule, qui suit le présentateur. Noir hors présentation.
struct VuePublic: View {
    @ObservedObject var seance: SeancePresentation

    var body: some View {
        ZStack {
            Color.black
            if let d = seance.document, seance.publicActif {
                PresentationWebView(document: d,
                                    translator: DocumentTranslator(),
                                    langueSource: nil,
                                    traduire: false,
                                    annotations: seance.annotations ?? AnnotationsDocument(),
                                    mode: .public,
                                    cible: seance.index,
                                    choix: seance.choix,
                                    tableTraduction: seance.traductionActive ? seance.traduction : nil,
                                    onExit: {}, onDiagram: { _ in }, onImage: { _ in },
                                    onExportReady: { _ in }, onAnnoter: {})
                    .id(d.id)
                    // Les traits et le pointeur de la télécommande (1.6), pour le public aussi.
                    .overlay { CalqueTelecommande() }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

/// La fenêtre du public (Mac). Le système la restaure au lancement, sans présentation en cours : elle
/// se referme aussitôt. Seule restaurée (iPad, au simulateur), elle rouvre d'abord la fenêtre
/// principale — elle restait noire, sans issue ; à côté de la principale (Mac), en rouvrir une en
/// faisait deux.
struct FenetrePublique: View {
    @ObservedObject private var seance = SeancePresentation.partage
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VuePublic(seance: seance)
            .onAppear {
                // Restaurée sans présentation : elle s'efface sans se compter comme ouverte (une
                // fenêtre détruite ne passe pas toujours par `onDisappear`).
                guard seance.document != nil else {
                    let autres = UIApplication.shared.connectedScenes.filter {
                        $0.session.role == .windowApplication && $0.activationState != .unattached
                    }
                    if autres.count <= 1 { openWindow(id: "principal") }
                    dismissWindow(id: "public")
                    return
                }
                seance.fenetrePublique = true
            }
            .onDisappear { seance.fenetrePublique = false }
    }
}

/// La colonne du présentateur, à droite du diaporama : l'heure et le chronomètre, la diapositive
/// suivante, les notes.
struct PanneauPresentateur: View {
    @ObservedObject var seance: SeancePresentation
    var arreter: () -> Void
    /// Écrire la note de la diapositive en cours (1.5) ; nil sans l'option ou sans fichier Markdown.
    var modifierNotes: (() -> Void)? = nil
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            entete
            tempsPrevu
            Text(tr("Diapositive suivante")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            suivante
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
            HStack {
                Text(tr("Notes de l’orateur")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let modifierNotes {
                    Button(action: modifierNotes) {
                        Label(tr("Modifier les notes"), systemImage: "square.and.pencil")
                            .labelStyle(.iconOnly)
                    }
                    .font(.callout)
                    .foregroundStyle(orange)
                    .accessibilityLabel(tr("Modifier les notes"))
                }
            }
            ScrollView {
                Text(seance.notes.isEmpty ? tr("Pas de notes pour cette diapositive.") : seance.notes)
                    .font(.title3)
                    .foregroundStyle(seance.notes.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            Button(role: .destructive, action: arreter) {
                Label(tr("Arrêter sur l’autre écran"), systemImage: "rectangle.on.rectangle.slash")
            }
            .font(.callout)
            .opacity(seance.fenetrePublique ? 1 : 0)
            .disabled(!seance.fenetrePublique)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.09))
        .environment(\.colorScheme, .dark)
    }

    /// L'heure, le chronomètre (pause, remise à zéro) et la position dans la présentation.
    private var entete: some View {
        TimelineView(.periodic(from: .now, by: 1)) { contexte in
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(chrono(contexte.date))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(seance.pause == nil ? orange : .secondary)
                Button { seance.basculerPause() } label: {
                    Image(systemName: seance.pause == nil ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(seance.pause == nil ? tr("Pause") : tr("Reprendre"))
                Button { seance.remettreAZero() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel(tr("Remettre à zéro"))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(contexte.date, style: .time).font(.title3.monospacedDigit())
                    Text("\(seance.index + 1) / \(max(seance.total, 1))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
    }

    @ViewBuilder private var suivante: some View {
        if let d = seance.document, seance.index + 1 < seance.total {
            PresentationWebView(document: d,
                                translator: DocumentTranslator(),
                                langueSource: nil,
                                traduire: false,
                                annotations: seance.annotations ?? AnnotationsDocument(),
                                mode: .apercu,
                                cible: seance.index + 1,
                                choix: seance.choix,
                                tableTraduction: seance.traductionActive ? seance.traduction : nil,
                                onExit: {}, onDiagram: { _ in }, onImage: { _ in },
                                onExportReady: { _ in }, onAnnoter: {})
                .id(d.id)
                .allowsHitTesting(false)
        } else {
            ZStack {
                Color.black
                Text(tr("Fin de la présentation")).font(.headline).foregroundStyle(.secondary)
            }
        }
    }

    private func chrono(_ maintenant: Date) -> String {
        let s = Int(seance.ecoule(maintenant))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// La couleur du temps : la diapositive, puis le total, comparés au temps prévu.
    @ViewBuilder private var tempsPrevu: some View {
        if !seance.prevus.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { c in
                VStack(alignment: .leading, spacing: 8) {
                    if let p = seance.prevu(seance.index) {
                        JaugeTemps(libelle: tr("Diapositive"), ecoule: seance.ecouleDiapo(c.date), prevu: p)
                    }
                    JaugeTemps(libelle: tr("Total"), ecoule: seance.ecoule(c.date), prevu: seance.prevuTotal, fine: true)
                }
            }
        }
    }
}

/// Le temps qui se voit sans lire le chronomètre (option Analytic, 26/11/2026, reprise d'iA
/// Presenter) : une barre qui se remplit vers le temps prévu, bleue tant qu'on a de la marge, jaune
/// à l'approche (les trois quarts), vermillon au-delà, avec le dépassement écrit. Bleu, jaune et
/// vermillon (palette d'Okabe et Ito) se distinguent aussi pour les daltoniens, et la longueur de la
/// barre dit la même chose que sa couleur. Jamais sur l'écran du public.
struct JaugeTemps: View {
    enum Phase { case calme, approche, depasse }

    var libelle: String? = nil
    let ecoule: TimeInterval
    let prevu: TimeInterval
    var fine = false
    /// Sans texte : le liseré seul (la télécommande, en largeur).
    var compacte = false

    static func phase(_ ecoule: TimeInterval, _ prevu: TimeInterval) -> Phase {
        guard prevu > 0 else { return .calme }
        let f = ecoule / prevu
        return f > 1 ? .depasse : f >= 0.75 ? .approche : .calme
    }

    static func couleur(_ p: Phase) -> Color {
        switch p {
        case .calme: return Color(red: 0x56/255, green: 0xB4/255, blue: 0xE9/255)
        case .approche: return Color(red: 0xF0/255, green: 0xE4/255, blue: 0x42/255)
        case .depasse: return Color(red: 0xD5/255, green: 0x5E/255, blue: 0x00/255)
        }
    }

    private func ligne(libelle avecLibelle: Bool, prevu avecPrevu: Bool, phase: Phase, teinte: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if avecLibelle, let libelle { Text(libelle).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            if phase == .depasse {
                Text("+" + RepetitionDiaporama.duree(ecoule - prevu)).fontWeight(.semibold).foregroundStyle(teinte)
            }
            Text(RepetitionDiaporama.duree(ecoule) + (avecPrevu ? " / " + RepetitionDiaporama.duree(prevu) : ""))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    var body: some View {
        let phase = Self.phase(ecoule, prevu)
        let teinte = Self.couleur(phase)
        let fraction = prevu > 0 ? min(1, ecoule / prevu) : 0
        VStack(alignment: .leading, spacing: 4) {
            if !compacte {
                // Une seule ligne : dans une colonne étroite, le libellé s'efface, puis le temps
                // prévu ; le dépassement reste.
                ViewThatFits(in: .horizontal) {
                    ligne(libelle: true, prevu: true, phase: phase, teinte: teinte)
                    ligne(libelle: false, prevu: true, phase: phase, teinte: teinte)
                    ligne(libelle: false, prevu: false, phase: phase, teinte: teinte)
                }
                .font((fine ? Font.caption : Font.callout).monospacedDigit())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(teinte).frame(width: max(fine ? 3 : 5, g.size.width * fraction))
                }
            }
            .frame(height: fine ? 4 : 7)
            .animation(.easeInOut(duration: 0.4), value: phase)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelle ?? tr("Temps"))
        .accessibilityValue(tr("%@ sur %@ prévues", RepetitionDiaporama.duree(ecoule), RepetitionDiaporama.duree(prevu)))
    }
}

/// La scène d'un écran externe (iPad, iPhone) : l'écran du public. Sa fenêtre ne se montre que
/// pendant une présentation ; cachée, elle laisse le système recopier l'écran de l'appareil.
final class EcranExterneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    private var abonnement: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated {
            let seance = SeancePresentation.partage
            let w = UIWindow(windowScene: ws)
            w.rootViewController = UIHostingController(rootView: VuePublic(seance: seance).modifier(LangueDeLApp()))
            w.isHidden = !seance.publicActif
            window = w
            seance.ecranExterne = true
            abonnement = seance.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.window?.isHidden = !SeancePresentation.partage.publicActif }
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        MainActor.assumeIsolated {
            SeancePresentation.partage.ecranExterne = false
            abonnement = nil
            window = nil
        }
    }
}

/// Le délégué de l'application : il donne à un écran externe sa scène (le public) ; les autres
/// scènes restent celles de SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowExternalDisplayNonInteractive {
            c.delegateClass = EcranExterneDelegate.self
        }
        return c
    }
}
