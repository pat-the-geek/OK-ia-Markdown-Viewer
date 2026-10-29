import SwiftUI
import AppIntents
import CoreSpotlight

extension Notification.Name {
    /// Posted by the macOS File ▸ Open menu command; observed by RootView.
    static let okiaOpenFile = Notification.Name("okia.openFile")
    /// Importer Word, PDF ou PowerPoint (option Analytic) : Fichier ▸ Importer sur Mac, menu « … »
    /// et accueil ailleurs.
    static let okiaImporter = Notification.Name("okia.importer")
    /// L'analyse de tout le coffre (option Analytic) : Fichier ▸ Analyser le coffre sur Mac, l'en-tête
    /// du coffre ailleurs.
    static let okiaAnalyseCoffre = Notification.Name("okia.analyseCoffre")
    /// Ouvre un rapport du coffre par son identifiant (`VaultReport.id`) — depuis la fiche d'une
    /// entité, « Dans le coffre ».
    static let okiaOuvrirRapport = Notification.Name("okia.ouvrirRapport")
    /// Le dossier d'import surveillé (option Analytic, Mac) : Fichier ▸ Dossier d'import surveillé…
    static let okiaDossierSurveille = Notification.Name("okia.dossierSurveille")
    /// La recherche dans tout le coffre (option Analytic) : Fichier ▸ Rechercher dans le coffre… sur
    /// Mac, l'en-tête du coffre ailleurs.
    static let okiaRechercheCoffre = Notification.Name("okia.rechercheCoffre")
}

/// Holds the currently displayed document and any load error.
@MainActor
final class DocumentStore: ObservableObject {
    @Published var document: MarkdownDocument?
    @Published var errorMessage: String?
    /// Set by an App Intent to ask the reader to present the Apple Intelligence summary.
    @Published var summaryRequested = false
    /// L'import d'un document Word, PDF ou PowerPoint en cours (option Analytic).
    @Published var importEnCours: ImportEnCours?
    /// Un import demandé sans l'option : la vitrine de l'option s'ouvre.
    @Published var vitrineImport = false
    /// Ce qui était demandé quand la vitrine s'est ouverte : fait dès l'achat, la vitrine refermée
    /// (Patrick, 28/10/2026 : acheté depuis un PowerPoint ouvert, l'import ne partait pas). Oublié
    /// si la vitrine se ferme sans achat.
    var actionApresAchat: (@MainActor () -> Void)?

    /// Fait `action` si l'option Analytic est achetée, montre sa vitrine sinon — une fois les achats
    /// lus (`AchatAnalytic.accesSur`), jamais sur l'ignorance du lancement.
    func avecOption(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor [weak self] in
            if await AchatAnalytic.partage.accesSur() { action() }
            else { self?.actionApresAchat = action; self?.vitrineImport = true }
        }
    }
    /// Ce que le document qui s'ouvre doit chercher : un document trouvé par la recherche du coffre.
    @Published var rechercheDemandee: String?
    /// Une action de Raccourcis (1.4) demande au lecteur d'ouvrir les entités du document.
    @Published var entitesDemandees = false
    /// Une action de Raccourcis (1.4) attend le PDF du document : le lecteur l'exporte une fois rendu.
    @Published var exportPDFDemande: DemandeExportPDF?

    // Partagés par toutes les fenêtres (1.4, fonction 7) : chacune a son document, pas son coffre.
    let recents = RecentFilesStore.partage
    let vault = VaultStore.partage

    /// La fenêtre de l'app (fonction 7) : celle des actions de Raccourcis, des Services, du coffre
    /// surveillé. Les autres fenêtres ont chacune leur `DocumentStore`.
    static weak var principal: DocumentStore?
    /// Le store de la fenêtre clé — la dernière touchée, celle au premier plan sur Mac : c'est à elle
    /// que vont les commandes du menu, les actions de Raccourcis et les Services.
    static weak var actif: DocumentStore?
    /// Où une demande venue d'ailleurs que la fenêtre doit aller.
    var cible: DocumentStore { Self.actif ?? Self.principal ?? self }

    #if targetEnvironment(macCatalyst)
    private lazy var vaultWatcher = VaultWatcher(vault: vault) { [weak self] report in
        self?.openVaultReport(report)
    }
    /// macOS: begin (or restart) watching the vault folder for newly arrived reports.
    func startVaultWatch() {
        // Une seule surveillance du coffre, celle de la fenêtre de l'app : chaque fenêtre ouvrirait
        // sinon le rapport qui arrive.
        guard Self.principal == nil || Self.principal === self else { return }
        vaultWatcher.start()
    }
    #else
    func startVaultWatch() {}
    #endif

    /// Entry point for every incoming URL: custom scheme (mdviewer://) or a file URL.
    func handleIncoming(_ url: URL) {
        if url.scheme?.lowercased() == "mdviewer" {
            handleScheme(url)
        } else if url.isFileURL, ImportEnCours.estImportable(url) {
            // Un Word, un PDF, un PowerPoint confié à md Viewer (« Ouvrir avec », partage, dépôt sur
            // l'icône) s'importe avec l'option Analytic — sur Mac, iPhone et iPad depuis le 26/10 ;
            // sans elle, l'option se présente.
            avecOption { [weak self] in self?.importer(url: url) }
        } else {
            open(url: url)
        }
    }

    /// mdviewer://open?url=<https .md>   — fetch a remote report and render it
    /// mdviewer://render?name=<f>&content=<percent-encoded markdown>  — render inline
    /// mdviewer://fichier?nom=<f>          — read a drop from the shared mailbox (see BoiteAuxLettres)
    private func handleScheme(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            errorMessage = tr("Lien invalide."); return
        }
        let action = (comps.host ?? "").lowercased()
        func value(_ names: String...) -> String? {
            for n in names { if let v = comps.queryItems?.first(where: { $0.name == n })?.value { return v } }
            return nil
        }
        switch action {
        // Option Analytic (1.4) : l'extension de partage a déposé une page — ou l'on confie une adresse.
        case "pages":
            releverPages()
        case "page":
            if let s = value("url", "u") { analyserPage(s) } else { releverPages() }
        case "open", "url":
            if let s = value("url", "u"), let remote = URL(string: s), remote.scheme?.hasPrefix("http") == true {
                openRemote(remote)
            } else {
                errorMessage = tr("URL du rapport manquante ou invalide (https requis).")
            }
        // Boîte aux lettres partagée avec fornews.ai. Demandée par Patrick le 11/09 : sur iOS,
        // aucune application ne peut remettre un FICHIER à une autre application nommée, et le
        // contenu ne tient pas dans une URL — un rapport mesuré à 272 037 caractères une fois
        // encodé. fornews dépose donc le document dans le conteneur du groupe et n'envoie que son
        // NOM. Cf. `BoiteAuxLettres`, dont ce fichier partage la définition mot pour mot.
        case "fichier", "file":
            let nom = value("nom", "name", "f") ?? ""
            if let contenu = BoiteAuxLettres.relire(nom), !contenu.isEmpty {
                document = MarkdownDocument(filename: sanitize(nom), text: contenu)
                errorMessage = nil
            } else {
                // ⚠️ Dire ce qui manque, et non « lien invalide » : le dépôt peut avoir été effacé
                // par le plafond de la boîte, ou le groupe d'applications mal signé. Deux causes
                // bien distinctes, toutes deux invisibles sans ce message.
                errorMessage = tr("Document introuvable dans le dossier partagé : « %@ ».", nom)
            }
        case "render", "content":
            let name = value("name", "title") ?? tr("Rapport.md")
            if let content = value("content", "text"), !content.isEmpty {
                document = MarkdownDocument(filename: sanitize(name), text: content)
                errorMessage = nil
            } else {
                errorMessage = tr("Contenu du rapport manquant.")
            }
        default:
            errorMessage = tr("Action inconnue : « %@ ».", action)
        }
    }

    /// Downloads a remote Markdown report (HTTPS) and renders it.
    func openRemote(_ url: URL) {
        let name = url.lastPathComponent.isEmpty ? tr("Rapport.md") : url.lastPathComponent
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.errorMessage = tr("Le serveur a répondu %lld pour le rapport.", http.statusCode)
                    return
                }
                if let data, error == nil {
                    let safeName = self.sanitize(name)
                    self.document = MarkdownDocument(filename: safeName,
                                                     text: MarkdownLoader.decode(data),
                                                     sourceURL: url)
                    self.recents.addRemote(url: url, name: safeName)
                    self.errorMessage = nil
                } else {
                    self.errorMessage = tr("Impossible de télécharger le rapport (%@).",
                                           error?.localizedDescription ?? tr("réseau"))
                }
            }
        }.resume()
    }

    private func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? tr("Rapport.md") : cleaned
    }

    /// Opens a user-selected file (importer / open-in / cold launch) and remembers it.
    func open(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            document = try MarkdownLoader.load(from: url)
            recents.add(url: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Option Analytic (1.4) : ouvre un document trouvé par la recherche du coffre ou par Spotlight
    /// (`RechercheCoffre`), et y cherche `chercher`.
    func ouvrirTrouve(_ id: String, chercher: String? = nil) {
        if id.hasPrefix("coffre:") {
            let rapport = String(id.dropFirst("coffre:".count))
            if !vault.reports.contains(where: { $0.id == rapport }) { vault.refresh() }
            guard let r = vault.reports.first(where: { $0.id == rapport }) else {
                errorMessage = tr("Ce fichier n’est plus accessible."); return
            }
            openVaultReport(r)
            if errorMessage == nil { rechercheDemandee = chercher }
        } else if id.hasPrefix("analyse:") {
            // Le conteneur iCloud se demande hors du fil principal.
            Task {
                guard let url = await Task.detached(operation: { RechercheCoffre.urlAnalyse(id) }).value else { return }
                open(url: url)
                if errorMessage == nil { rechercheDemandee = chercher }
            }
        }
    }

    /// Option Analytic : convertit un document Word, PDF ou PowerPoint en Markdown, le range
    /// (`RangementDocuments`) et l'ouvre.
    func importer(url: URL) { importerLot([url]) }

    // MARK: Import par lot (option Analytic, 1.4)

    /// Les fichiers à importer, l'un après l'autre : plusieurs fichiers choisis d'un coup, un dossier,
    /// un dépôt, « Ouvrir avec », le dossier surveillé — une seule file.
    private var fichiersEnAttente: [URL] = []
    /// Les dossiers dont on importe le contenu : ouverts (accès du bac à sable) le temps du lot.
    private var dossiersOuverts: [URL] = []
    private struct Lot {
        var total = 0
        var faits = 0
        var importes = 0
        var dernier: URL?
        var echecs: [String] = []
        var choix: (consignes: Bool, rapport: Bool)?
    }
    private var lot: Lot?
    /// Le bilan d'un lot, montré à la fin.
    @Published var bilanLot: String?

    /// Importe des fichiers et des dossiers (leurs Word, PDF et PowerPoint, sous-dossiers compris).
    /// Un seul fichier : l'import habituel, qui s'ouvre à la fin ; plusieurs : à la suite, la
    /// question d'Apple Intelligence posée une fois, un bilan à la fin.
    func importerLot(_ urls: [URL]) {
        var fichiers: [URL] = []
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if scoped { dossiersOuverts.append(u) }
                fichiers += Self.importables(dans: u)
            } else {
                if scoped { u.stopAccessingSecurityScopedResource() }
                if ImportEnCours.estImportable(u) { fichiers.append(u) }
            }
        }
        guard !fichiers.isEmpty else {
            if lot == nil { fermerDossiers() }
            errorMessage = tr("Aucun document Word, PDF ou PowerPoint à importer.")
            return
        }
        if lot == nil { lot = Lot() }
        lot?.total += fichiers.count
        fichiersEnAttente += fichiers
        fichierSuivant()
    }

    /// Les Word, PDF et PowerPoint d'un dossier et de ses sous-dossiers, dans l'ordre des noms.
    nonisolated static func importables(dans dossier: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return e.compactMap { $0 as? URL }.filter(ImportEnCours.estImportable)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func fichierSuivant() {
        guard importEnCours == nil else { return }
        guard !fichiersEnAttente.isEmpty else { terminerLot(); return }
        let url = fichiersEnAttente.removeFirst()
        let i = ImportEnCours(nomSource: url.lastPathComponent)
        if let l = lot, l.total > 1 {
            i.lot = (l.faits + 1, l.total)
            i.reponseImposee = l.choix
            i.surReponse = { [weak self] c, r in self?.lot?.choix = (c, r) }
        }
        importEnCours = i
        i.lancer(url) { [weak self] issue in self?.finImportLot(i, issue) }
    }

    private func finImportLot(_ i: ImportEnCours, _ issue: Result<ImportEnCours.Resultat, Error>) {
        guard importEnCours === i else { return }
        guard var l = lot, l.total > 1 else {
            // Un seul document : il s'ouvre, comme avant.
            lot = nil
            fermerDossiers()
            finImport(i, issue)
            pageSuivante()
            return
        }
        importEnCours = nil
        l.faits += 1
        switch issue {
        case .success(let r):
            l.importes += 1
            recents.add(url: r.document)
            if let a = r.rapport { recents.add(url: a) }
            l.dernier = r.rapport ?? r.document
        case .failure:
            l.echecs.append(i.nomSource)
        }
        lot = l
        // La fenêtre d'avancement se referme, la suivante s'ouvre.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.fichierSuivant() }
    }

    private func terminerLot() {
        guard let l = lot else { return }
        lot = nil
        fermerDossiers()
        if let dernier = l.dernier { open(url: dernier) }
        var bilan = tr("%d documents importés", l.importes) + " — " + tr("rangés dans « Documents analysés », au dossier du jour.")
        if !l.echecs.isEmpty { bilan += "\n\n" + tr("Pas importés : %@", l.echecs.joined(separator: ", ")) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.bilanLot = bilan }
        pageSuivante()
    }

    private func fermerDossiers() {
        dossiersOuverts.forEach { $0.stopAccessingSecurityScopedResource() }
        dossiersOuverts = []
    }

    private func finImport(_ i: ImportEnCours, _ issue: Result<ImportEnCours.Resultat, Error>) {
            guard importEnCours === i else { return }
            importEnCours = nil
            switch issue {
            case .success(let r):
                // Le rapport d'analyse s'ouvre s'il y en a un ; le document importé entre dans les
                // récents, à un geste.
                if let rapport = r.rapport {
                    recents.add(url: r.document)
                    open(url: rapport)
                } else {
                    open(url: r.document)
                }
            case .failure(let e):
                // L'alerte attend que la fenêtre d'avancement soit refermée : présentée pendant
                // qu'elle se retire, SwiftUI l'abandonnait, et l'échec passait sans un mot (Patrick,
                // PDF scanné, 26/10/2026).
                let message = e.localizedDescription
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.errorMessage = message }
            }
    }

    // MARK: Pages web (option Analytic, 1.4)

    /// Les pages partagées depuis Safari, en attente d'être traitées une à une.
    private var pagesEnAttente: [PageWeb] = []

    /// Relève la boîte de réception des pages partagées (au retour au premier plan, ou par
    /// `mdviewer://pages`) et les traite l'une après l'autre.
    func releverPages() {
        pagesEnAttente += BoitePages.relever()
        pageSuivante()
    }

    /// Une adresse confiée directement (`mdviewer://page?url=…`, un raccourci).
    func analyserPage(_ adresse: String) {
        pagesEnAttente.append(PageWeb(url: adresse))
        pageSuivante()
    }

    private func pageSuivante() {
        guard importEnCours == nil, !pagesEnAttente.isEmpty else { return }
        let page = pagesEnAttente.removeFirst()
        let wikidata = UserDefaults.standard.string(forKey: ConsentementWikidata.cle) == ConsentementWikidata.accepte.rawValue
        let i = ImportEnCours(nomSource: page.titre ?? page.url)
        importEnCours = i
        // Avec l'option, la fiche de lecture ; sans elle, le texte de la page, puis l'option se
        // présente. Les achats lus d'abord : une page partagée lance souvent l'app.
        Task { @MainActor in
            let acces = await AchatAnalytic.partage.accesSur()
            i.lancerPage(page, analyser: acces, wikidata: wikidata) { [weak self] issue in
                guard let self else { return }
                self.finImport(i, issue)
                if !acces, case .success = issue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.vitrineImport = true }
                }
                // Un lien vers un PDF, sans l'option : elle se présente, et l'import reprend une fois achetée.
                if case .failure(ErreurImport.pdfSansOption) = issue {
                    self.actionApresAchat = { [weak self] in self?.analyserPage(page.url) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.vitrineImport = true }
                }
                self.pageSuivante()
                self.fichierSuivant()
            }
        }
    }

    func annulerImport() {
        importEnCours?.annuler()
        importEnCours = nil
        // Annuler un document d'un lot arrête le lot : ce qui est déjà importé reste.
        fichiersEnAttente = []
        if lot != nil { terminerLot() }
    }

    /// Reopens a previously stored recent entry (local file or remote report).
    func openRecent(_ item: RecentFile) {
        if let remote = item.remoteURLString, let url = URL(string: remote) {
            openRemote(url)
            return
        }
        guard let url = recents.resolve(item) else {
            errorMessage = tr("Ce fichier n’est plus accessible.")
            recents.remove(item)
            return
        }
        open(url: url)
    }

    /// Opens a report from the watched vault folder (downloading from iCloud if needed).
    func openVaultReport(_ report: VaultReport) {
        guard let folder = vault.resolveFolder() else {
            errorMessage = tr("Le dossier du coffre n’est plus accessible."); return
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let fileURL = folder.appendingPathComponent(report.subfolder).appendingPathComponent(report.name)
        // Materialise an iCloud placeholder if needed (NSFileCoordinator in the loader also handles this).
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        }
        do {
            document = try MarkdownLoader.load(from: fileURL)
            recents.add(url: fileURL)
            errorMessage = nil
        } catch {
            errorMessage = tr("Impossible d’ouvrir « %@ » (synchronisation iCloud en cours ?).", report.name)
        }
    }

    // MARK: - App Intents support

    /// Open a vault report by its entity id ("subfolder/name").
    func openReport(id: String) {
        vault.refresh()
        if let report = vault.reports.first(where: { $0.id == id }) {
            openVaultReport(report)
        } else {
            errorMessage = tr("Rapport introuvable dans le coffre.")
        }
    }

    /// Open the most recent vault report.
    func openLatestReport() {
        vault.refresh()
        if let report = vault.reports.first {
            openVaultReport(report)
        } else {
            errorMessage = tr("Aucun rapport dans le coffre.")
        }
    }

    /// Open a report then ask the reader to summarise it with Apple Intelligence.
    func openReportAndSummarize(id: String) {
        openReport(id: id)
        if document != nil { summaryRequested = true }
    }

    func openSample() {
        guard let url = Bundle.main.url(forResource: "Demo", withExtension: "md", subdirectory: "Samples")
            ?? Bundle.main.url(forResource: "Demo", withExtension: "md") else {
            errorMessage = tr("Exemple introuvable dans le bundle.")
            return
        }
        // Don't pollute recents with the bundled sample.
        do {
            document = try MarkdownLoader.load(from: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@main
struct OKiaMarkdownViewerApp: App {
    @StateObject private var store: DocumentStore
    /// L'écran externe (1.4, mode présentateur) : sa scène est celle du public.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let store = DocumentStore()
        _store = StateObject(wrappedValue: store)
        DocumentStore.principal = store
        // Share the running store with App Intents (Siri / Spotlight / Shortcuts).
        AppDependencyManager.shared.add(dependency: store)
        // Option Analytic (1.4) : ce qui est acheté, et les achats qui arrivent d'ailleurs.
        AchatAnalytic.partage.demarrer()
        // La recherche dans le coffre et Spotlight lisent le coffre de l'app.
        RechercheCoffre.partage.brancher(store.vault)
        // Une page partagée depuis Safari pendant que md Viewer est à l'écran : la fenêtre active la
        // prend tout de suite (sinon, au prochain passage au premier plan).
        BoitePages.ecouter { MainActor.assumeIsolated { (DocumentStore.actif ?? DocumentStore.principal)?.releverPages() } }
        #if targetEnvironment(macCatalyst)
        // Les Services macOS (1.4), une fois l'app lancée : `NSApplication` doit exister.
        DispatchQueue.main.async { store.brancherServices() }
        #endif
        #if DEBUG
        // Seed du schéma CloudKit (`-OKIASeedSchema YES`) : écrit les types en Développement, puis quitte.
        Task { @MainActor in if await SynchroICloud.amorcerSchemaSiDemande() { exit(0) } }
        #endif
        #if DEBUG
        // Screenshot harness (Debug/simulator only): render a document handed in via
        // environment so App Store captures can be scripted headlessly.
        let env = ProcessInfo.processInfo.environment
        if let content = env["OKIA_RENDER_CONTENT"], !content.isEmpty {
            let name = env["OKIA_RENDER_NAME"] ?? "Demo.md"
            store.document = MarkdownDocument(filename: name, text: content)
        }
        // OKIA_RENDER_FILE=<chemin> : de même pour un document trop gros pour l'environnement (un
        // import aux images embarquées : 3 Mo, quand une variable n'en passe qu'un).
        if let chemin = env["OKIA_RENDER_FILE"], !chemin.isEmpty,
           let texte = try? String(contentsOfFile: chemin, encoding: .utf8) {
            let name = env["OKIA_RENDER_NAME"] ?? (chemin as NSString).lastPathComponent
            store.document = MarkdownDocument(filename: name, text: texte)
        }
        // OKIA_COFFRE=<dossier> : le coffre, sans le sélecteur (un dossier du conteneur au simulateur) ;
        // OKIA_ANALYSE_COFFRE : ouvre l'analyse de tout le coffre au lancement.
        if let dossier = env["OKIA_COFFRE"], !dossier.isEmpty {
            store.vault.setFolder(URL(fileURLWithPath: dossier, isDirectory: true))
        }
        // OKIA_LOT=<dossier> : importe un dossier entier, comme un dossier choisi ou déposé.
        if let dossier = env["OKIA_LOT"], !dossier.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                store.importerLot([URL(fileURLWithPath: dossier, isDirectory: true)])
            }
        }
        // OKIA_SURVEILLE=<dossier> : le dossier d'import surveillé, sans le sélecteur ; « arreter » l'oublie.
        if let dossier = env["OKIA_SURVEILLE"], !dossier.isEmpty {
            if dossier == "arreter" { DossierSurveille.partage.arreter() }
            else { DossierSurveille.partage.choisir(URL(fileURLWithPath: dossier, isDirectory: true)) }
        }
        // OKIA_RECHERCHE=<requête> : ouvre la recherche dans le coffre, la requête posée ;
        // OKIA_TROUVE=<identifiant> : ouvre un document comme depuis Spotlight.
        if let q = env["OKIA_RECHERCHE"], !q.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(name: .okiaRechercheCoffre, object: nil, userInfo: ["requete": q])
            }
        }
        if let id = env["OKIA_TROUVE"], !id.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { store.ouvrirTrouve(id) }
        }
        if env["OKIA_ANALYSE_COFFRE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(name: .okiaAnalyseCoffre, object: nil)
            }
        }
        // OKIA_RACCOURCI=<action> : une action de Raccourcis, lancée comme Raccourcis le ferait.
        if let action = env["OKIA_RACCOURCI"], !action.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Task { @MainActor in await EssaiRaccourcis.lancer(action, env, store: store) }
            }
        }
        // OKIA_PAGE=<adresse> : analyse une page web au lancement, comme un partage depuis Safari.
        if let page = env["OKIA_PAGE"], !page.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { store.analyserPage(page) }
        }
        #endif
    }

    var body: some Scene {
        // Une fenêtre par document (1.4, fonction 7) : la valeur dit ce qu'elle ouvre, rien pour
        // l'accueil. Chaque fenêtre a son store (`FenetreDocument`).
        WindowGroup(id: "principal", for: DocumentAOuvrir.self) { $aOuvrir in
            FenetreDocument(aOuvrir: aOuvrir, principal: store)
                .modifier(ApparenceDeCapture())
        }
        .commands {
            // macOS: replace the default "New" with "Ouvrir…" / "Open…" (⌘O).
            CommandGroup(replacing: .newItem) {
                Button(tr("Ouvrir…")) {
                    NotificationCenter.default.post(name: .okiaOpenFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                #if targetEnvironment(macCatalyst)
                // Pour comparer (1.4) : une autre fenêtre, avec son propre document.
                CommandeNouvelleFenetre()
                Button(tr("Importer Word, PDF ou PowerPoint…")) {
                    NotificationCenter.default.post(name: .okiaImporter, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Button(tr("Dossier d’import surveillé…")) {
                    NotificationCenter.default.post(name: .okiaDossierSurveille, object: nil)
                }
                Button(tr("Analyser le coffre…")) {
                    NotificationCenter.default.post(name: .okiaAnalyseCoffre, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                Button(tr("Rechercher dans le coffre…")) {
                    NotificationCenter.default.post(name: .okiaRechercheCoffre, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                #endif
            }
        }

        // Le mode présentateur (1.4) : la fenêtre du public, à poser sur le projecteur (Mac). Elle ne reçoit jamais de fichier ni de lien : tout va à la fenêtre principale.
        WindowGroup(id: "public") {
            FenetrePublique()
        }
        .handlesExternalEvents(matching: [])
    }
}

/// Captures App Store (Debug) : OKIA_CLAIR force l'apparence claire de l'app, sans toucher au
/// réglage du Mac — les simulateurs se mettent en clair d'eux-mêmes, le Mac non.
private struct ApparenceDeCapture: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OKIA_CLAIR"] != nil {
            content.preferredColorScheme(.light)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - App Intents (Siri · Spotlight · Raccourcis · Apple Intelligence)

/// A vault report exposed to Shortcuts/Siri so it can be picked as a parameter.
struct VaultReportEntity: AppEntity, Identifiable {
    let id: String          // "subfolder/name"
    let name: String
    let subfolder: String

    init(_ r: VaultReport) { id = r.id; name = r.name; subfolder = r.subfolder }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Rapport" }
    static var defaultQuery = VaultReportQuery()

    var displayRepresentation: DisplayRepresentation {
        let title = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        return DisplayRepresentation(title: "\(title)", subtitle: "\(subfolder)")
    }
}

/// Lists/searches vault reports for the entity picker. Reads the vault directly
/// (from the shared bookmark) so it also works while configuring a shortcut.
struct VaultReportQuery: EntityQuery, EntityStringQuery {
    @MainActor private func allReports() -> [VaultReport] {
        let vault = VaultStore()
        vault.refresh()
        return vault.reports
    }

    func entities(for identifiers: [String]) async throws -> [VaultReportEntity] {
        let reports = await allReports()
        return reports.filter { identifiers.contains($0.id) }.map(VaultReportEntity.init)
    }

    func suggestedEntities() async throws -> [VaultReportEntity] {
        let reports = await allReports()
        return reports.prefix(30).map(VaultReportEntity.init)
    }

    func entities(matching string: String) async throws -> [VaultReportEntity] {
        let needle = string.lowercased()
        let reports = await allReports()
        return reports.filter { $0.name.lowercased().contains(needle) }.map(VaultReportEntity.init)
    }
}

/// Open a chosen report in md Viewer.
struct OpenReportIntent: AppIntent {
    // App Intents metadata must be compile-time static; the English translations
    // live in Localizable.xcstrings (resolved by the system language).
    static var title: LocalizedStringResource = "Ouvrir un rapport"
    static var description = IntentDescription("Ouvre un rapport du coffre dans md Viewer.")
    static var openAppWhenRun = true

    @Parameter(title: "Rapport") var report: VaultReportEntity
    @Dependency var store: DocumentStore

    static var parameterSummary: some ParameterSummary { Summary("Ouvrir \(\.$report)") }

    @MainActor func perform() async throws -> some IntentResult {
        store.cible.openReport(id: report.id)
        return .result()
    }
}

/// Open the most recent report.
struct OpenLatestReportIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir le dernier rapport"
    static var description = IntentDescription("Ouvre le rapport le plus récent du coffre.")
    static var openAppWhenRun = true

    @Dependency var store: DocumentStore

    @MainActor func perform() async throws -> some IntentResult {
        store.cible.openLatestReport()
        return .result()
    }
}

/// Open a report and present its Apple Intelligence summary (gracefully degrades
/// when Apple Intelligence is unavailable).
struct SummarizeReportIntent: AppIntent {
    static var title: LocalizedStringResource = "Résumer un rapport"
    static var description = IntentDescription("Ouvre un rapport et génère son résumé sur l’appareil.")
    static var openAppWhenRun = true

    @Parameter(title: "Rapport") var report: VaultReportEntity
    @Dependency var store: DocumentStore

    static var parameterSummary: some ParameterSummary { Summary("Résumer \(\.$report)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if DocumentSummarizer.isAvailable {
            store.cible.openReportAndSummarize(id: report.id)
            return .result(dialog: "Résumé de « \(report.name) » dans md Viewer.")
        } else {
            store.cible.openReport(id: report.id)
            return .result(dialog: "Le résumé n’est pas disponible sur cet appareil ; j’ouvre le rapport.")
        }
    }
}

/// Auto-registers spoken phrases in Siri / Spotlight / the Shortcuts app.
struct MdViewerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenLatestReportIntent(),
                    phrases: ["Ouvre le dernier rapport dans \(.applicationName)",
                              "Dernier rapport \(.applicationName)",
                              "Open the latest report in \(.applicationName)",
                              "Latest report \(.applicationName)"],
                    shortTitle: "Dernier rapport",
                    systemImageName: "doc.text")
        AppShortcut(intent: SummarizeReportIntent(),
                    phrases: ["Résume un rapport dans \(.applicationName)",
                              "Résumé \(.applicationName)",
                              "Summarise a report in \(.applicationName)",
                              "Summarize a report in \(.applicationName)"],
                    shortTitle: "Résumer un rapport",
                    systemImageName: "sparkles")
        AppShortcut(intent: OpenReportIntent(),
                    phrases: ["Ouvre un rapport dans \(.applicationName)",
                              "Open a report in \(.applicationName)"],
                    shortTitle: "Ouvrir un rapport",
                    systemImageName: "folder")
        // Option Analytic (1.4, fonction Mac n° 6).
        AppShortcut(intent: ImporterDocumentsIntent(),
                    phrases: ["Importe dans \(.applicationName)",
                              "Import into \(.applicationName)"],
                    shortTitle: "Importer",
                    systemImageName: "square.and.arrow.down.on.square")
        AppShortcut(intent: FichePageWebIntent(),
                    phrases: ["Fais la fiche d’une page avec \(.applicationName)",
                              "Fiche de page \(.applicationName)",
                              "Make a web page brief with \(.applicationName)"],
                    shortTitle: "Fiche d’une page",
                    systemImageName: "safari")
        AppShortcut(intent: AnalyserDocumentIntent(),
                    phrases: ["Analyse le document dans \(.applicationName)",
                              "Analyze the document in \(.applicationName)"],
                    shortTitle: "Analyser",
                    systemImageName: "person.2")
        AppShortcut(intent: ExporterPDFAnnoteIntent(),
                    phrases: ["Exporte en PDF avec \(.applicationName)",
                              "Export to PDF with \(.applicationName)"],
                    shortTitle: "PDF annoté",
                    systemImageName: "doc.richtext")
    }
}
