import AppIntents
import OSLog
import UniformTypeIdentifiers

// Option Analytic (1.4) — les actions de Raccourcis (fonction Mac n° 6, Patrick, 27/10/2026) :
// importer un document, faire la fiche d'une page web, analyser un document, l'exporter en PDF
// avec ses annotations. Sur Mac, iPhone et iPad : Raccourcis, Spotlight et Siri les proposent, et
// un raccourci fait d'elles devient une action rapide du Finder ou un Service.
//
// Chacune passe par le même chemin que l'interface (`DocumentStore`) : sans l'option, l'import et
// la fiche présentent l'option, l'analyse montre son aperçu, le PDF part sans annotations.

/// Un fichier reçu de Raccourcis, rendu lisible : le fichier lui-même quand le système le donne
/// (le Finder, sur Mac), sinon une copie sous son nom dans le dossier temporaire — le nom et le
/// contenu suffisent à retrouver les annotations d'un document (`SynchroICloud`).
private func fichierLisible(_ f: IntentFile) throws -> URL {
    if let url = f.fileURL, FileManager.default.isReadableFile(atPath: url.path) { return url }
    let dossier = FileManager.default.temporaryDirectory
        .appendingPathComponent("Raccourcis-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    let url = dossier.appendingPathComponent(f.filename.isEmpty ? "Document" : f.filename)
    try f.data.write(to: url)
    return url
}

/// Les fichiers qu'on peut ouvrir dans md Viewer : Markdown et texte.
private let typesMarkdown: [UTType] = [UTType("net.daringfireball.markdown"), UTType(filenameExtension: "md"),
                                       .plainText].compactMap { $0 }

enum ErreurRaccourci: Error, CustomLocalizedStringResourceConvertible {
    case aucunDocument, illisible, exportImpossible

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .aucunDocument: "Aucun document ouvert dans md Viewer."
        case .illisible: "md Viewer n’a pas pu lire ce fichier."
        case .exportImpossible: "md Viewer n’a pas pu exporter ce document en PDF."
        }
    }
}

/// Importer des documents Word, PDF ou PowerPoint : convertis en Markdown, analysés, rangés dans
/// « Documents analysés ».
struct ImporterDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Importer dans md Viewer"
    static var description = IntentDescription("Convertit des documents Word, PDF ou PowerPoint en Markdown, les analyse et les range dans « Documents analysés ».")
    static var openAppWhenRun = true

    @Parameter(title: "Documents", supportedContentTypes: ImportEnCours.types)
    var documents: [IntentFile]
    @Dependency var store: DocumentStore

    static var parameterSummary: some ParameterSummary { Summary("Importer \(\.$documents)") }

    @MainActor func perform() async throws -> some IntentResult {
        try Self.faire(documents, store: store.cible)
        return .result()
    }

    @MainActor static func faire(_ documents: [IntentFile], store: DocumentStore) throws {
        guard AchatAnalytic.partage.acces else { store.vitrineImport = true; return }
        store.importerLot(try documents.map(fichierLisible))
    }
}

/// La fiche de lecture d'une page web, comme depuis le partage de Safari.
struct FichePageWebIntent: AppIntent {
    static var title: LocalizedStringResource = "Faire la fiche d’une page web"
    static var description = IntentDescription("Lit une page web et en fait une fiche de lecture : résumé, chiffres, noms cités.")
    static var openAppWhenRun = true

    @Parameter(title: "Adresse") var adresse: URL
    @Dependency var store: DocumentStore

    static var parameterSummary: some ParameterSummary { Summary("Faire la fiche de \(\.$adresse)") }

    @MainActor func perform() async throws -> some IntentResult {
        store.cible.analyserPage(adresse.absoluteString)
        return .result()
    }
}

/// Les entités d'un document : personnes, lieux, organisations, et leur carte.
struct AnalyserDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Analyser un document"
    static var description = IntentDescription("Ouvre un document Markdown et montre les personnes, les lieux et les organisations qu’il cite. Sans document, celui qui est ouvert.")
    static var openAppWhenRun = true

    @Parameter(title: "Document", supportedContentTypes: typesMarkdown)
    var document: IntentFile?
    @Dependency var store: DocumentStore

    static var parameterSummary: some ParameterSummary { Summary("Analyser \(\.$document)") }

    @MainActor func perform() async throws -> some IntentResult {
        try Self.faire(document, store: store.cible)
        return .result()
    }

    @MainActor static func faire(_ document: IntentFile?, store: DocumentStore) throws {
        if let document {
            store.open(url: try fichierLisible(document))
        }
        guard store.document != nil else { throw ErreurRaccourci.aucunDocument }
        store.entitesDemandees = true
    }
}

/// Le PDF d'un document, avec ses surlignages, soulignements et notes.
struct ExporterPDFAnnoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Exporter en PDF avec les annotations"
    static var description = IntentDescription("Exporte un document Markdown en PDF, avec ses annotations. Sans document, celui qui est ouvert.")
    static var openAppWhenRun = true

    @Parameter(title: "Document", supportedContentTypes: typesMarkdown)
    var document: IntentFile?
    @Dependency var store: DocumentStore

    static var parameterSummary: some ParameterSummary { Summary("Exporter \(\.$document) en PDF") }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        .result(value: try await Self.faire(document, store: store.cible))
    }

    @MainActor static func faire(_ document: IntentFile?, store: DocumentStore) async throws -> IntentFile {
        if let document {
            store.open(url: try fichierLisible(document))
            if store.errorMessage != nil { throw ErreurRaccourci.illisible }
        }
        guard let doc = store.document else { throw ErreurRaccourci.aucunDocument }
        // Le lecteur exporte une fois le document rendu (`ReaderView`) ; une minute au plus.
        let url: URL? = await withCheckedContinuation { suite in
            let demande = DemandeExportPDF(document: doc.id) { suite.resume(returning: $0) }
            store.exportPDFDemande = demande
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { demande.servir(nil) }
        }
        guard let url, let data = try? Data(contentsOf: url) else { throw ErreurRaccourci.exportImpossible }
        let nom = (doc.filename as NSString).deletingPathExtension + ".pdf"
        return IntentFile(data: data, filename: nom, type: .pdf)
    }
}

/// Une demande d'export PDF faite au lecteur, servie une seule fois.
@MainActor
final class DemandeExportPDF: Identifiable {
    let id = UUID()
    /// Le document à exporter : un autre document affiché entre-temps ne l'est pas à sa place.
    let document: UUID
    private var fini: ((URL?) -> Void)?

    init(document: UUID, fini: @escaping (URL?) -> Void) {
        self.document = document
        self.fini = fini
    }

    var servie: Bool { fini == nil }

    func servir(_ url: URL?) {
        fini?(url)
        fini = nil
    }
}

// MARK: - Les Services macOS

#if targetEnvironment(macCatalyst)
extension DocumentStore {
    /// Le fournisseur des Services, chargé du module AppKit `ServicesMac` : gardé tant que l'app vit.
    private static var fournisseurServices: NSObject?

    /// Charge le module des Services (« Ouvrir dans md Viewer », « Fiche de cette page ») et reçoit
    /// ce qu'il transmet : les mêmes chemins qu'un fichier confié à l'app ou une page de Safari.
    func brancherServices() {
        Self.tracer("branchement")
        guard Self.fournisseurServices == nil,
              let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("ServicesMac.bundle"),
              let module = Bundle(url: url) else { Self.tracer("module introuvable"); return }
        do { try module.loadAndReturnError() } catch { Self.tracer("module pas chargé : \(error)"); return }
        guard let classe = module.principalClass as? NSObject.Type else { Self.tracer("classe introuvable"); return }
        Self.fournisseurServices = classe.init()
        let centre = NotificationCenter.default
        centre.addObserver(forName: Notification.Name("okia.service.fichiers"), object: nil, queue: .main) { [weak self] n in
            guard let urls = n.userInfo?["urls"] as? [URL] else { return }
            Self.tracer("fichiers \(urls.map(\.lastPathComponent))")
            MainActor.assumeIsolated { self?.cible.recevoirFichiers(urls) }
        }
        centre.addObserver(forName: Notification.Name("okia.service.texte"), object: nil, queue: .main) { [weak self] n in
            guard let texte = n.userInfo?["texte"] as? String else { return }
            Self.tracer("texte, \(texte.count) caractères")
            MainActor.assumeIsolated {
                let cible = self?.cible
                cible?.document = MarkdownDocument(filename: tr("Sélection.md"), text: texte)
                cible?.errorMessage = nil
            }
        }
        centre.addObserver(forName: Notification.Name("okia.service.page"), object: nil, queue: .main) { [weak self] n in
            guard let adresse = n.userInfo?["adresse"] as? String else { return }
            Self.tracer("page \(adresse)")
            MainActor.assumeIsolated { self?.cible.analyserPage(adresse) }
        }
        Self.tracer("module chargé")
    }

    /// Ce que les Services transmettent, dans la console (Debug).
    private nonisolated static func tracer(_ texte: String) {
        #if DEBUG
        // Dans le journal du système : la sortie d'une app lancée par le Finder ne se lit pas.
        Logger(subsystem: "ch.ok-ia.markdownviewer", category: "services").error("OKIA_SERVICE \(texte, privacy: .public)")
        #endif
    }

    /// Des fichiers du Finder : les Word, PDF et PowerPoint s'importent (avec l'option), le premier
    /// Markdown s'ouvre.
    fileprivate func recevoirFichiers(_ urls: [URL]) {
        let aImporter = urls.filter(ImportEnCours.estImportable)
        if !aImporter.isEmpty {
            if AchatAnalytic.partage.acces { importerLot(aImporter) } else { vitrineImport = true }
        } else if let premier = urls.first {
            open(url: premier)
        }
    }
}
#endif

#if DEBUG
/// OKIA_RACCOURCI=importer|fiche|analyser|pdf : lance l'action comme Raccourcis le ferait, sur
/// OKIA_RACCOURCI_FICHIER (un chemin) ou OKIA_RACCOURCI_ADRESSE ; le PDF rendu va dans les documents
/// de l'app (`raccourci.pdf`), l'issue dans la console.
enum EssaiRaccourcis {
    @MainActor static func lancer(_ action: String, _ env: [String: String], store: DocumentStore) async {
        let fichier = env["OKIA_RACCOURCI_FICHIER"].map { IntentFile(fileURL: URL(fileURLWithPath: $0)) }
        do {
            switch action {
            case "importer":
                try ImporterDocumentsIntent.faire(fichier.map { [$0] } ?? [], store: store)
            case "fiche":
                store.analyserPage(env["OKIA_RACCOURCI_ADRESSE"] ?? "https://www.apple.com")
            case "analyser":
                try AnalyserDocumentIntent.faire(fichier, store: store)
            case "pdf":
                let f = try await ExporterPDFAnnoteIntent.faire(fichier, store: store)
                if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try f.data.write(to: docs.appendingPathComponent("raccourci.pdf"))
                    print("OKIA_RACCOURCI pdf : \(f.filename), \(f.data.count) octets")
                }
            default: break
            }
            print("OKIA_RACCOURCI \(action) : fini")
        } catch {
            print("OKIA_RACCOURCI \(action) : échec \(error)")
        }
    }
}
#endif
