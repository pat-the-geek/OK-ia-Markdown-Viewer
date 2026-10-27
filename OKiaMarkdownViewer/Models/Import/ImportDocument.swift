import Foundation
import UniformTypeIdentifiers

/// Option Analytic (1.4) — l'import d'un document Word, PDF ou PowerPoint : le choix du
/// convertisseur, l'avancement pour le compte à rebours, et le fichier Markdown écrit dans le
/// dossier « Documents analysés » (`RangementDocuments`), d'où le lecteur l'ouvre comme n'importe quel document (il entre
/// dans les récents ; on peut le partager ou l'exporter).
@MainActor
final class ImportEnCours: ObservableObject, Identifiable {
    let id = UUID()
    let nomSource: String
    @Published private(set) var avancement: AvancementImport?
    @Published private(set) var debut = Date()
    /// Le document converti, en attente de la réponse de l'utilisateur : rédiger ou non, avec
    /// Apple Intelligence, ce que demandent ses commentaires, et un rapport d'analyse.
    @Published private(set) var enAttente: DocumentImporte?
    private var tache: Task<Void, Never>?
    /// La traduction d'une page web : la fenêtre d'avancement porte sa session (`TraducteurPonctuelHote`).
    let traducteur = TraducteurPonctuel()
    private var nom = ""
    private var fini: (@MainActor (Result<Resultat, Error>) -> Void)?
    /// Dans un lot (1.4) : le rang de ce document et le total, que la fenêtre d'avancement dit.
    var lot: (rang: Int, total: Int)?
    /// La réponse déjà donnée pour le lot : la question n'est posée qu'une fois.
    var reponseImposee: (consignes: Bool, rapport: Bool)?
    /// L'utilisateur vient de répondre : le lot retient sa réponse.
    var surReponse: ((Bool, Bool) -> Void)?

    /// Ce que l'import a écrit : le document, et le rapport d'analyse s'il a été demandé.
    struct Resultat {
        var document: URL
        var rapport: URL?
    }

    init(nomSource: String) { self.nomSource = nomSource }

    /// Les formats qu'on importe.
    static let types: [UTType] = [
        .pdf,
        UTType("org.openxmlformats.wordprocessingml.document") ?? UTType(filenameExtension: "docx") ?? .data,
        UTType("org.openxmlformats.presentationml.presentation") ?? UTType(filenameExtension: "pptx") ?? .data,
    ]

    /// Demande l'import : le sélecteur de fichiers s'ouvre, ou la vitrine sans l'option (RootView).
    static func demander() {
        NotificationCenter.default.post(name: .okiaImporter, object: nil)
    }

    static func estImportable(_ url: URL) -> Bool {
        ["pdf", "docx", "pptx"].contains(url.pathExtension.lowercased())
    }

    /// Le temps qui reste, d'après l'allure jusqu'ici ; nil tant qu'on n'en sait rien.
    func resteEstime(_ maintenant: Date) -> TimeInterval? {
        guard let a = avancement, a.fait >= 2, a.total > a.fait else { return nil }
        let ecoule = maintenant.timeIntervalSince(debut)
        return ecoule / Double(a.fait) * Double(a.total - a.fait)
    }

    /// Lit et convertit le document. Si Apple Intelligence est là, l'import s'arrête sur la question
    /// (`enAttente`, puis `poursuivre`) ; sinon il écrit tout de suite.
    func lancer(_ url: URL, fini: @escaping @MainActor (Result<Resultat, Error>) -> Void) {
        debut = Date()
        self.fini = fini
        self.nom = url.lastPathComponent
        tache = Task { [weak self] in
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let donnees = try Data(contentsOf: url)
                let nom = url.lastPathComponent
                let suivi: SuiviImport = { [weak self] a in self?.avancement = a }
                let doc: DocumentImporte
                switch url.pathExtension.lowercased() {
                case "docx": doc = try await ImportWord.convertir(donnees, nom: nom, suivi: suivi)
                case "pptx": doc = try await ImportPowerPoint.convertir(donnees, nom: nom, suivi: suivi)
                case "pdf":  doc = try await ImportPDF.convertir(donnees, nom: nom, suivi: suivi)
                default:     throw ErreurImport.formatInconnu(nom)
                }
                try Task.checkCancellation()
                #if DEBUG
                // OKIA_IMPORT_IA=consignes,rapport répond à la question tout seul (le Mac de test ne
                // se pilote pas) ; « aucun » importe sans rien rédiger.
                if let r = ProcessInfo.processInfo.environment["OKIA_IMPORT_IA"] {
                    self?.poursuivre(consignes: r.contains("consignes"), rapport: r.contains("rapport"), doc: doc)
                    return
                }
                #endif
                if let r = self?.reponseImposee {
                    self?.poursuivre(consignes: r.consignes, rapport: r.rapport, doc: doc)
                } else if MoteurRedaction.disponible {
                    self?.enAttente = doc
                } else {
                    self?.poursuivre(consignes: false, rapport: false, doc: doc)
                }
            } catch is CancellationError {
                return
            } catch {
                fini(.failure(error))
            }
        }
    }

    /// La réponse à la question : rédiger les consignes, le rapport, ou ni l'un ni l'autre.
    func poursuivre(consignes: Bool, rapport: Bool, doc: DocumentImporte? = nil) {
        // Sans `doc`, c'est la réponse de l'utilisateur à la question : le lot la retient.
        if doc == nil { surReponse?(consignes, rapport) }
        guard let doc = doc ?? enAttente, let fini else { return }
        enAttente = nil
        debut = Date()
        avancement = nil
        let nom = self.nom
        tache = Task { [weak self] in
            let suivi: SuiviImport = { [weak self] a in self?.avancement = a }
            var markdown = doc.markdown
            if consignes, !doc.consignes.isEmpty {
                let langue = MoteurRedaction.langue(markdown)
                let textes = await RedactionConsignes.rediger(doc.consignes, langue: langue, suivi: suivi)
                markdown = RedactionConsignes.appliquer(markdown, consignes: doc.consignes, redactions: textes)
            } else {
                markdown = RedactionConsignes.retirer(markdown, consignes: doc.consignes)
            }
            if Task.isCancelled { return }
            var rapportMD: String?
            if rapport {
                self?.debut = Date()
                rapportMD = await RapportAnalyseImport.produire(markdown: markdown, titreDocument: doc.titre,
                                                                nomSource: nom, suivi: suivi)
            }
            if Task.isCancelled { return }
            do {
                let cible = try Self.ecrire(markdown, nomSource: nom)
                let base = (nom as NSString).deletingPathExtension
                let analyse = try rapportMD.map { try Self.ecrire($0, nomSource: base + " — " + tr("analyse") + ".md") }
                fini(.success(Resultat(document: cible, rapport: analyse)))
            } catch {
                fini(.failure(error))
            }
        }
    }

    /// Une page web partagée (Safari, ou toute app qui partage un lien) : sa fiche de lecture avec
    /// l'option, son texte seul sans elle. Une page arrivée sans corps est d'abord chargée ici.
    func lancerPage(_ recue: PageWeb, analyser: Bool, wikidata: Bool,
                    fini: @escaping @MainActor (Result<Resultat, Error>) -> Void) {
        debut = Date()
        self.fini = fini
        tache = Task { [weak self] in
            do {
                var page = recue
                if !page.aUnCorps {
                    self?.avancement = AvancementImport(etape: tr("Chargement de la page"), fait: 0, total: 1, dernier: page.url)
                    let lue = try await LecteurPageWeb.lire(page.url)
                    // Les métadonnées que Safari avait déjà gardent la main.
                    page = PageWeb(url: page.url, titre: page.titre ?? lue.titre, media: page.media ?? lue.media,
                                   auteur: page.auteur ?? lue.auteur, date: page.date ?? lue.date,
                                   image: page.image ?? lue.image, logo: page.logo ?? lue.logo,
                                   langue: page.langue ?? lue.langue, description: page.description ?? lue.description,
                                   blocs: lue.blocs)
                }
                guard page.aUnCorps else { throw LecteurPageWeb.Erreur.lecture }
                let suivi: SuiviImport = { [weak self] a in self?.avancement = a }
                let (titre, md) = analyser
                    ? await FichePageWeb.produire(page, langue: Localization.shared.code, wikidata: wikidata,
                                                  traducteur: self?.traducteur, suivi: suivi)
                    : FichePageWeb.texteSeul(page)
                try Task.checkCancellation()
                // Le nom du fichier : le titre de la page, normalisé (`RangementDocuments`).
                fini(.success(Resultat(document: try Self.ecrire(md, nomSource: titre + ".md", analyse: analyser), rapport: nil)))
            } catch is CancellationError {
                return
            } catch {
                fini(.failure(error))
            }
        }
    }

    func annuler() { tache?.cancel() }

    /// Écrit le Markdown à sa place (`RangementDocuments` : iCloud Drive, dossier du jour, nom
    /// lisible), sous le nom du document d'origine, sans écraser un import précédent.
    nonisolated static func ecrire(_ markdown: String, nomSource: String, analyse: Bool = true) throws -> URL {
        try RangementDocuments.ecrire(markdown, titre: (nomSource as NSString).deletingPathExtension, analyse: analyse)
    }
}

enum ErreurImport: LocalizedError {
    case formatInconnu(String)
    var errorDescription: String? {
        switch self {
        case .formatInconnu(let nom): return tr("md Viewer n’importe pas « %@ » : Word, PDF ou PowerPoint seulement.", nom)
        }
    }
}
