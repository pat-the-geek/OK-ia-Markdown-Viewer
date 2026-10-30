import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var showImporter = false
    /// Which kind of item the single importer is currently picking.
    /// SwiftUI does not reliably support two `.fileImporter`s on one view, so we
    /// drive both the file-open and the vault-folder pickers through one importer.
    @State private var importFolder = false
    /// Le même sélecteur, pour un document Word, PDF ou PowerPoint à importer (option Analytic).
    @State private var importOffice = false
    /// L'analyse de tout le coffre (option Analytic, 1.4).
    @State private var analyseCoffre = false
    /// La recherche dans tout le coffre (option Analytic, 1.4), et la requête qu'elle reçoit en
    /// s'ouvrant. Une feuille `item` : avec `isPresented`, la feuille gardait la requête d'avant.
    @State private var rechercheCoffre: DemandeRecherche?
    private struct DemandeRecherche: Identifiable {
        let id = UUID()
        let requete: String
    }
    /// Le dossier d'import surveillé (option Analytic, Mac) : son réglage, puis le choix du dossier.
    @State private var reglageSurveille = false
    @State private var choisirSurveille = false
    @ObservedObject private var surveille = DossierSurveille.partage
    @ObservedObject private var achat = AchatAnalytic.partage

    /// UTTypes we accept in the in-app importer.
    static let importedTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let md = UTType("net.daringfireball.markdown") { types.insert(md, at: 0) }
        if let mdAlt = UTType(filenameExtension: "md") { types.append(mdAlt) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        return types
    }()

    var body: some View {
        Group {
            if let doc = store.document {
                ReaderView(document: doc,
                           onOpen: { importFolder = false; importOffice = false; showImporter = true },
                           onHome: { store.document = nil })
            } else {
                EmptyStateView(
                    recentsStore: store.recents,
                    vault: store.vault,
                    onOpen: { importFolder = false; importOffice = false; showImporter = true },
                    onSample: { store.openSample() },
                    onRecent: { store.openRecent($0) },
                    onPickVault: { importFolder = true; importOffice = false; showImporter = true },
                    onOpenVault: { store.openVaultReport($0) },
                    onOpenAnalyse: { store.open(url: $0) }
                )
            }
        }
        // One importer for both modes — `importFolder` selects file vs. vault folder.
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importFolder ? [.folder] : importOffice ? ImportEnCours.types + [.folder] : RootView.importedTypes,
            // L'import (1.4) : plusieurs fichiers d'un coup, ou un dossier entier.
            allowsMultipleSelection: importOffice
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if choisirSurveille { choisirSurveille = false; surveille.choisir(url) }
                else if importFolder { store.vault.setFolder(url) }
                else if importOffice { store.importerLot(urls) }
                else { store.open(url: url) }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .alert(tr("Erreur"),
               isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        // macOS: File ▸ Open (⌘O) menu command.
        .onReceive(NotificationCenter.default.publisher(for: .okiaOpenFile)) { n in
            guard n.estPour(store) else { return }
            importFolder = false
            importOffice = false
            showImporter = true
        }
        // Importer Word, PDF ou PowerPoint, réservé à l'option Analytic : Fichier ▸ Importer (⇧⌘I)
        // sur Mac, le menu « … » et l'accueil sur iPhone et iPad.
        .onReceive(NotificationCenter.default.publisher(for: .okiaImporter)) { n in
            guard n.estPour(store) else { return }
            store.avecOption {
                importFolder = false
                importOffice = true
                showImporter = true
            }
        }
        // Le dossier d'import surveillé : le choisir, ou arrêter.
        .onReceive(NotificationCenter.default.publisher(for: .okiaDossierSurveille)) { n in
            guard n.estPour(store) else { return }
            store.avecOption { reglageSurveille = true }
        }
        .confirmationDialog(surveille.nom.map { tr("Dossier surveillé : « %@ »", $0) } ?? tr("Aucun dossier surveillé"),
                            isPresented: $reglageSurveille, titleVisibility: .visible) {
            Button(surveille.nom == nil ? tr("Choisir un dossier…") : tr("Choisir un autre dossier…")) {
                importFolder = true; importOffice = false; choisirSurveille = true; showImporter = true
            }
            if surveille.nom != nil {
                Button(tr("Arrêter la surveillance"), role: .destructive) { surveille.arreter() }
            }
        } message: {
            Text(tr("Chaque Word, PDF ou PowerPoint qui arrive dans ce dossier est importé et rangé, tant que md Viewer est ouvert. Ce qui s’y trouve déjà n’est pas importé."))
        }
        // Un rapport du coffre demandé par la fiche d'une entité.
        .onReceive(NotificationCenter.default.publisher(for: .okiaOuvrirRapport)) { note in
            guard note.estPour(store) else { return }
            guard let id = note.userInfo?["id"] as? String else { return }
            // Un document analysé (importé, fiche d'une page web) : il n'est pas dans le coffre.
            if id.hasPrefix("analyse:") { store.ouvrirTrouve(id); return }
            // La liste du coffre ne se charge qu'à l'accueil : ouvert directement sur un document,
            // elle est encore vide.
            if !store.vault.reports.contains(where: { $0.id == id }) { store.vault.refresh() }
            guard let r = store.vault.reports.first(where: { $0.id == id }) else { return }
            store.openVaultReport(r)
        }
        // L'analyse de tout le coffre (option Analytic).
        .onReceive(NotificationCenter.default.publisher(for: .okiaAnalyseCoffre)) { n in
            guard n.estPour(store) else { return }
            store.avecOption { analyseCoffre = true }
        }
        // La recherche dans tout le coffre (option Analytic).
        .onReceive(NotificationCenter.default.publisher(for: .okiaRechercheCoffre)) { note in
            guard note.estPour(store) else { return }
            let requete = note.userInfo?["requete"] as? String ?? ""
            store.avecOption { rechercheCoffre = DemandeRecherche(requete: requete) }
        }
        .sheet(item: $rechercheCoffre) { demande in
            RechercheCoffreView(ouvrir: { r in store.ouvrirTrouve(r.id, chercher: r.aChercher) },
                                requete: demande.requete)
                // Une page entière sur iPad : les extraits ont besoin de largeur.
                .presentationSizing(.page)
        }
        // Spotlight suit le coffre et l'option : un rapport arrivé, l'option achetée ou perdue.
        .onChange(of: store.vault.reports) { _, _ in RechercheCoffre.partage.indexerSpotlight() }
        .onChange(of: achat.acces) { _, _ in RechercheCoffre.partage.indexerSpotlight() }
        // Sur Mac, toute la fenêtre, par-dessus l'accueil (Patrick, 28/10/2026 : « de la même taille que
        // l'écran d'en dessous, et se superposer ») ; ailleurs, une page entière.
        .feuilleOuFenetreEntiere(isPresented: $analyseCoffre) {
            AnalyseCoffreView(vault: store.vault, ouvrir: { store.ouvrirTrouve($0) })
        }
        // Le bilan d'un import par lot.
        .alert(tr("Import terminé"),
               isPresented: Binding(get: { store.bilanLot != nil }, set: { if !$0 { store.bilanLot = nil } })) {
            Button("OK", role: .cancel) { store.bilanLot = nil }
        } message: {
            Text(store.bilanLot ?? "")
        }
        .sheet(item: $store.importEnCours) { i in
            ImportView(import_: i, annuler: { store.annulerImport() })
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $store.vitrineImport, onDismiss: { store.repriseApresVitrine() }) {
            // Un bouton pour la refermer (Patrick, 27/10/2026, sur l'iPhone : « je ne peux pas
            // quitter ») : glisser vers le bas s'y confondait avec le défilement, et le Mac n'a pas
            // ce geste. La barre de navigation la décolle aussi du haut de l'écran.
            NavigationStack {
                ScrollView { OptionAnalyticView().padding(24) }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("Fermer")) { store.vitrineImport = false }
                                .tint(Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255))
                        }
                    }
            }
            // Dix apports depuis le 27/10 : la feuille de taille ordinaire coupait le bouton d'achat.
            .presentationSizing(.page)
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 460, minHeight: 680)
            #endif
        }
        .modifier(RepriseApresAchat(store: store, achat: achat))
        // macOS: auto-open new reports landing in the vault folder.
        .task {
            store.startVaultWatch()
            // Spotlight : ce qui a changé depuis le dernier lancement.
            store.vault.refresh()
            RechercheCoffre.partage.indexerSpotlight()
            #if targetEnvironment(macCatalyst)
            // Le dossier d'import surveillé : ses nouveaux fichiers rejoignent la file d'import.
            surveille.demarrer { urls in if AchatAnalytic.partage.acces { store.importerLot(urls) } }
            #endif
        }
        .onChange(of: store.vault.folderName) { _, _ in store.startVaultWatch() }
        // Drag a .md from Finder onto the window to open it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            // Des Word, PDF, PowerPoint déposés — ou un dossier qui en contient — s'importent, à la
            // suite, avec l'option.
            let estDossier = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if estDossier || urls.contains(where: ImportEnCours.estImportable) {
                store.avecOption { store.importerLot(urls) }
                return true
            }
            store.open(url: url)
            return true
        }
        .onAppear(perform: configureMacWindow)
    }

    private func configureMacWindow() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                windowScene.sizeRestrictions?.minimumSize = CGSize(width: 480, height: 600)
                windowScene.title = "md Viewer"
                #if DEBUG
                // Harnais de capture : fenêtre figée, pour une capture aux pixels près.
                // La valeur donne la taille en points, « 1660x1036 » — l'écran de capture
                // décide de ce qui tient, et un point ne vaut pas partout le même nombre de
                // pixels. Sans valeur lisible, on garde l'ancienne taille.
                if let demande = ProcessInfo.processInfo.environment["OKIA_SHOT_SIZE"] {
                    let parts = demande.split(separator: "x").compactMap { Double($0) }
                    let fixed = parts.count == 2 ? CGSize(width: parts[0], height: parts[1])
                                                 : CGSize(width: 1360, height: 860)
                    windowScene.sizeRestrictions?.minimumSize = fixed
                    windowScene.sizeRestrictions?.maximumSize = fixed
                }
                #endif
            }
        }
        #endif
    }
}

/// L'option achetée depuis la vitrine : elle se referme, et ce qui était demandé se fait une fois la
/// feuille partie (`DocumentStore.repriseApresVitrine`). À part : le corps de `RootView` dépassait ce
/// que le compilateur vérifie en un temps raisonnable.
private struct RepriseApresAchat: ViewModifier {
    @ObservedObject var store: DocumentStore
    @ObservedObject var achat: AchatAnalytic

    func body(content: Content) -> some View {
        content
            .onChange(of: achat.acces) { _, ouverte in
                guard ouverte, store.vitrineImport, store.actionApresAchat != nil else { return }
                store.vitrineImport = false
            }
    }
}

extension View {
    /// Sur Mac (l'app Mac comme l'app iPad sur Mac), une présentation qui couvre toute la fenêtre ;
    /// ailleurs, une feuille au format page.
    @ViewBuilder func feuilleOuFenetreEntiere<Contenu: View>(isPresented: Binding<Bool>,
                                                            @ViewBuilder contenu: @escaping () -> Contenu) -> some View {
        if AchatAnalytic.surMac || ProcessInfo.processInfo.isiOSAppOnMac {
            fullScreenCover(isPresented: isPresented, content: contenu)
        } else {
            sheet(isPresented: isPresented) { contenu().presentationSizing(.page) }
        }
    }
}
