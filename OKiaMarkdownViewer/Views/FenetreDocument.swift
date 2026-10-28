import SwiftUI
import CoreSpotlight
import OSLog

// 1.4 — plusieurs fenêtres, pour comparer (fonction Mac n° 7, Patrick, 27/10/2026) : deux documents
// côte à côte, ou deux versions d'un même document, chacun avec ses annotations (une version
// modifiée est un autre document, `IdentiteDocument`).
//
// Chaque fenêtre a son `DocumentStore` : son document, ses feuilles, ses imports. Le coffre, les
// récents, l'option et les annotations sont partagés. Avant, toutes les fenêtres partageaient le même
// store et montraient le même document (sur iPad, depuis les scènes multiples du mode présentateur).
// La première fenêtre prend le store de l'app (`DocumentStore.principal`) ; les actions de
// Raccourcis, les Services et les commandes du menu vont à la fenêtre clé (`DocumentStore.actif`).

/// Ce qu'une fenêtre ouvre : un fichier (son signet), un rapport en ligne, ou un texte qui n'a pas de
/// fichier. Gardé par le système avec la fenêtre : une fenêtre restaurée rouvre son document.
struct DocumentAOuvrir: Codable, Hashable {
    var nom: String
    var signet: Data?
    var adresse: String?
    var texte: String?
    /// Chaque demande ouvre une nouvelle fenêtre : sans lui, SwiftUI ramènerait au premier plan celle
    /// qui a été ouverte avec la même valeur, même si elle montre depuis un autre document.
    var jeton = UUID()
}

extension DocumentStore {
    /// Le document affiché, de quoi le rouvrir dans une autre fenêtre.
    func reference() -> DocumentAOuvrir? {
        guard let doc = document else { return nil }
        if let url = doc.sourceURL, url.isFileURL {
            // Un rapport du coffre : l'accès passe par le dossier, le temps de faire le signet.
            let dossier = vault.resolveFolder()
            let scoped = dossier?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { dossier?.stopAccessingSecurityScopedResource() } }
            if let signet = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                return DocumentAOuvrir(nom: doc.filename, signet: signet)
            }
        } else if let url = doc.sourceURL {
            return DocumentAOuvrir(nom: doc.filename, adresse: url.absoluteString)
        }
        return DocumentAOuvrir(nom: doc.filename, texte: doc.text)
    }

    /// Ouvre ce qu'une fenêtre a reçu.
    func ouvrir(_ d: DocumentAOuvrir) {
        if let signet = d.signet {
            var perime = false
            guard let url = try? URL(resolvingBookmarkData: signet, options: [], relativeTo: nil, bookmarkDataIsStale: &perime) else {
                errorMessage = tr("Ce fichier n’est plus accessible."); return
            }
            // Un rapport du coffre s'ouvre par le coffre, qui en détient l'accès.
            if let dossier = vault.resolveFolder(), url.standardizedFileURL.path.hasPrefix(dossier.standardizedFileURL.path + "/"),
               let r = vault.reports.first(where: { dossier.appendingPathComponent($0.subfolder).appendingPathComponent($0.name).standardizedFileURL.path == url.standardizedFileURL.path }) {
                openVaultReport(r)
            } else {
                open(url: url)
            }
        } else if let adresse = d.adresse, let url = URL(string: adresse) {
            openRemote(url)
        } else if let texte = d.texte {
            document = MarkdownDocument(filename: d.nom, text: texte)
            errorMessage = nil
        }
    }
}

/// Une fenêtre de documents : l'accueil ou un document, avec son propre store.
struct FenetreDocument: View {
    let aOuvrir: DocumentAOuvrir?
    @StateObject private var store: DocumentStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.openWindow) private var openWindow

    init(aOuvrir: DocumentAOuvrir?, principal: DocumentStore) {
        self.aOuvrir = aOuvrir
        _store = StateObject(wrappedValue: Self.store(principal))
    }

    /// La première fenêtre prend le store de l'app ; les suivantes, un store à elles.
    private static var principalPris = false
    private static func store(_ principal: DocumentStore) -> DocumentStore {
        guard principalPris else { principalPris = true; return principal }
        return DocumentStore()
    }

    var body: some View {
        RootView()
            .environmentObject(store)
            // Les fichiers et les liens confiés à l'app vont à la fenêtre ouverte : depuis que l'app
            // déclare plusieurs scènes (1.4, fenêtre du public), chacun en ouvrait une nouvelle, et
            // des imports d'un lot s'y perdaient (Mac, 27/10/2026).
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            // Handles file URLs (cold + warm "Open in…") and the mdviewer:// scheme.
            .onOpenURL { url in store.handleIncoming(url) }
            // Option Analytic (1.4) : un document du coffre ou des documents analysés, touché dans Spotlight.
            .onContinueUserActivity(CSSearchableItemActionType) { activite in
                guard let id = activite.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                store.ouvrirTrouve(id)
            }
            .onChange(of: phase) { _, p in
                guard p == .active else { return }
                if DocumentStore.actif == nil { DocumentStore.actif = store }
                // Les pages partagées depuis Safari pendant que md Viewer était en arrière-plan.
                store.releverPages()
                // Option Analytic (1.4) : annotations, corrections et cache des autres appareils.
                Task { await SynchroICloud.partage.synchroniser() }
                // Les entités que fornews a résolues, s'il a réécrit son cache entre-temps.
                Task { await EntitesDeFornews.partage.actualiser() }
            }
            .background(SondeFenetre { DocumentStore.actif = store })
            .task {
                if let aOuvrir, store.document == nil { store.ouvrir(aOuvrir) }
                // Les pages partagées avant le lancement : sur Mac, l'app démarre déjà au premier plan,
                // sans le passage à `.active` qui les relève (Patrick, 28/10/2026).
                if aOuvrir == nil { store.releverPages() }
                await EntitesDeFornews.partage.actualiser()
                #if DEBUG
                // OKIA_FENETRE=<chemin> : la fenêtre de l'app en ouvre une seconde sur ce fichier.
                if store === DocumentStore.principal, let chemin = ProcessInfo.processInfo.environment["OKIA_FENETRE"] {
                    try? await Task.sleep(for: .seconds(3))
                    let url = URL(fileURLWithPath: chemin)
                    if let signet = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        openWindow(id: "principal", value: DocumentAOuvrir(nom: url.lastPathComponent, signet: signet))
                    }
                }
                #endif
            }
            #if DEBUG
            // Quelle fenêtre montre quoi : le journal le dit (la fenêtre ne se pilote pas d'ici).
            .onChange(of: store.document?.id, initial: true) { _, _ in
                let qui = store === DocumentStore.principal ? "principale" : "autre"
                Logger(subsystem: "ch.ok-ia.markdownviewer", category: "fenetres")
                    .error("OKIA_FENETRE \(qui, privacy: .public) \(ObjectIdentifier(store).hashValue, privacy: .public) : \(store.document?.filename ?? "accueil", privacy: .public)")
            }
            #endif
            .onDisappear {
                // La fenêtre de l'app fermée (iPad, Mac), la prochaine fenêtre reprend son store.
                if store === DocumentStore.principal { Self.principalPris = false }
                if DocumentStore.actif === store { DocumentStore.actif = nil }
            }
    }
}

/// Dit quand la fenêtre qui la contient devient la fenêtre clé : touchée sur iPad, au premier plan
/// sur Mac. `scenePhase` n'y suffit pas : deux fenêtres côte à côte sont actives ensemble.
private struct SondeFenetre: UIViewRepresentable {
    var devientCle: () -> Void

    func makeUIView(context: Context) -> Sonde { Sonde(devientCle: devientCle) }
    func updateUIView(_ vue: Sonde, context: Context) { vue.devientCle = devientCle }

    final class Sonde: UIView {
        var devientCle: () -> Void
        private var observateur: NSObjectProtocol?

        init(devientCle: @escaping () -> Void) {
            self.devientCle = devientCle
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let o = observateur { NotificationCenter.default.removeObserver(o) }
            observateur = nil
            guard let fenetre = window else { return }
            observateur = NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification,
                                                                 object: fenetre, queue: .main) { [weak self] _ in
                self?.devientCle()
            }
            if fenetre.isKeyWindow { devientCle() }
        }

        deinit { if let o = observateur { NotificationCenter.default.removeObserver(o) } }
    }
}

extension Notification {
    /// Une demande (commande, bouton) est-elle pour ce store ? Un bouton d'une fenêtre désigne son
    /// store (`object`) ; une commande du menu, sans destinataire, va à la fenêtre clé.
    @MainActor func estPour(_ store: DocumentStore) -> Bool {
        if let destinataire = object as? DocumentStore { return destinataire === store }
        return store.cible === store
    }
}

/// « Ouvrir dans une nouvelle fenêtre » (menu du lecteur, récents) : réservé à l'option ; sans elle,
/// la vitrine. Absent de l'iPhone, qui n'a qu'une fenêtre.
struct BoutonNouvelleFenetre: View {
    let aOuvrir: () -> DocumentAOuvrir?
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var plusieursFenetres
    @ObservedObject private var achat = AchatAnalytic.partage

    var body: some View {
        if plusieursFenetres {
            Button {
                guard achat.acces else { store.vitrineImport = true; return }
                if let d = aOuvrir() { openWindow(id: "principal", value: d) }
            } label: {
                Label(tr("Ouvrir dans une nouvelle fenêtre"), systemImage: "macwindow.badge.plus")
            }
        }
    }
}

/// Fichier ▸ Nouvelle fenêtre (⌘N, Mac) : l'accueil dans une autre fenêtre ; Fichier ▸ Ouvrir dans
/// une nouvelle fenêtre (⌥⌘N) : le document de la fenêtre clé, dans une autre. Réservés à l'option.
struct CommandeNouvelleFenetre: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Nouvelle fenêtre")) {
            guard AchatAnalytic.partage.acces else {
                DocumentStore.actif?.vitrineImport = true; return
            }
            openWindow(id: "principal")
        }
        .keyboardShortcut("n", modifiers: .command)
        Button(tr("Ouvrir dans une nouvelle fenêtre")) {
            guard let store = DocumentStore.actif else { return }
            guard AchatAnalytic.partage.acces else { store.vitrineImport = true; return }
            if let d = store.reference() { openWindow(id: "principal", value: d) }
        }
        .keyboardShortcut("n", modifiers: [.command, .option])
    }
}
