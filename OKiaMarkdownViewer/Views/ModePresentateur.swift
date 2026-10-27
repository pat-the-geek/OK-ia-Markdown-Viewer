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
    @State private var debut = Date()
    @State private var pause: Date?
    @State private var cumulPause: TimeInterval = 0
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            entete
            Text(tr("Diapositive suivante")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            suivante
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
            Text(tr("Notes de l’orateur")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                    .foregroundStyle(pause == nil ? orange : .secondary)
                Button { basculerPause() } label: {
                    Image(systemName: pause == nil ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(pause == nil ? tr("Pause") : tr("Reprendre"))
                Button { debut = Date(); cumulPause = 0; pause = nil } label: {
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
        let fin = pause ?? maintenant
        let s = max(0, Int(fin.timeIntervalSince(debut) - cumulPause))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func basculerPause() {
        if let p = pause { cumulPause += Date().timeIntervalSince(p); pause = nil } else { pause = Date() }
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
            w.rootViewController = UIHostingController(rootView: VuePublic(seance: seance))
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
