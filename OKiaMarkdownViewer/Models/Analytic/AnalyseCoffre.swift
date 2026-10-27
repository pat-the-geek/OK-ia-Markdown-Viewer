import Foundation

/// Option Analytic (1.4) — l'analyse de tout le coffre (Patrick, 27/10/2026, fonction Mac n° 2) :
/// les entités croisées entre tous les documents — qui apparaît où, depuis quand, avec qui — et une
/// carte de tout le coffre.
///
/// Un index, document par document, des entités qu'on y trouve, par les mêmes moyens que l'analyse
/// d'un document : la section « Entités » d'un rapport fornews d'abord, la détection sinon ; puis
/// les corrections de l'utilisateur et le cache des fiches Wikidata (aucune requête ici : seul ce
/// que le cache sait déjà). L'index est gardé sur l'appareil (`Analytic/coffre.json`) et ne relit
/// que les documents modifiés depuis.
@MainActor
final class AnalyseCoffre: ObservableObject {
    static let partage = AnalyseCoffre()

    /// Ce que l'index garde d'un document.
    struct DocumentIndexe: Codable, Identifiable {
        let id: String              // sous-dossier/nom, comme `VaultReport.id`
        let nom: String
        let date: Date              // la date du nom (« 2026-10-27 … »), sinon de modification
        let modifie: Date
        let langue: String
        var entites: [EntiteDocument]
    }

    /// Un document où une entité apparaît.
    struct Presence: Identifiable, Hashable {
        let document: String
        let nom: String
        let date: Date
        let mentions: Int
        var id: String { document }
    }

    /// Une entité du coffre, ses documents, ses dates.
    struct EntiteCoffre: Identifiable, Hashable {
        var entite: EntiteDocument
        var presences: [Presence]
        var id: String { entite.id }
        var mentions: Int { presences.reduce(0) { $0 + $1.mentions } }
        var premiere: Date { presences.map(\.date).min() ?? .distantPast }
        var derniere: Date { presences.map(\.date).max() ?? .distantPast }
    }

    enum Etat: Equatable {
        case inactif
        case lecture(fait: Int, total: Int)
        case fini
    }

    @Published private(set) var etat: Etat = .inactif
    @Published private(set) var entites: [EntiteCoffre] = []
    @Published private(set) var nombreDocuments = 0
    /// Les documents encore dans iCloud, pas téléchargés : comptés, pas lus.
    @Published private(set) var nonTelecharges = 0

    private var index: [String: DocumentIndexe] = [:]
    private var tache: Task<Void, Never>?
    private let fichier: URL = {
        let dossier = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dossier.appendingPathComponent("Analytic/coffre.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fichier),
           let lu = try? JSONDecoder().decode([String: DocumentIndexe].self, from: data) {
            index = lu
        }
        // Les entités tout de suite : la fiche d'une entité montre ses documents du coffre sans
        // attendre qu'on ouvre l'analyse.
        rassembler()
    }

    // MARK: L'index

    /// Met l'index à jour pour les rapports du coffre : relit les documents nouveaux ou modifiés,
    /// oublie ceux qui ont disparu, puis rassemble.
    func analyser(_ vault: VaultStore) {
        tache?.cancel()
        let rapports = vault.reports
        let racine = vault.resolveFolder()
        nonTelecharges = rapports.filter { !$0.downloaded }.count
        let presents = rapports.filter(\.downloaded)
        let aLire = presents.filter { r in index[r.id].map { $0.modifie < r.modified } ?? true }
        index = index.filter { cle, _ in presents.contains { $0.id == cle } }
        guard !aLire.isEmpty, let racine else { rassembler(); etat = .fini; return }
        etat = .lecture(fait: 0, total: aLire.count)
        tache = Task { [weak self] in
            let scoped = racine.startAccessingSecurityScopedResource()
            defer { if scoped { racine.stopAccessingSecurityScopedResource() } }
            for (n, r) in aLire.enumerated() {
                guard !Task.isCancelled else { return }
                let url = racine.appendingPathComponent(r.subfolder).appendingPathComponent(r.name)
                if let texte = try? String(contentsOf: url, encoding: .utf8) {
                    let doc = await Self.indexer(texte, rapport: r)
                    self?.index[r.id] = doc
                }
                self?.etat = .lecture(fait: n + 1, total: aLire.count)
                // Le résultat s'affiche au fil de l'eau, pas seulement à la fin.
                if (n + 1) % 10 == 0 { self?.rassembler() }
            }
            guard let self, !Task.isCancelled else { return }
            self.enregistrer()
            self.rassembler()
            self.etat = .fini
        }
    }

    /// Les entités d'un document, comme l'analyse d'un document les trouve (sans Wikidata).
    nonisolated static func indexer(_ texte: String, rapport r: VaultReport) async -> DocumentIndexe {
        let langue = TexteAnalysable.langue(texte) ?? "fr"
        let duRapport = LecteurRapportFornews.lire(texte)
        // Un rapport fornews nomme déjà ses entités : la détection ne relit que les autres documents.
        let detectees = duRapport.isEmpty ? await DetecteurEntites.detecter(texte, langue: langue).entites : []
        var toutes = LecteurRapportFornews.dedoublonner(duRapport + detectees)
        DetecteurEntites.compterMentions(&toutes, dans: texte)
        let sources = SourcesDocument.lire(texte)
        for i in toutes.indices where sources.contient(toutes[i]) { toutes[i].source = true }
        toutes = DetecteurEntites.absorberFormesCourtes(toutes)
            .filter { $0.mentions > 0 || $0.origine == .rapport }
        return DocumentIndexe(id: r.id, nom: (r.name as NSString).deletingPathExtension,
                              date: dateDuNom(r.name) ?? r.modified, modifie: r.modified,
                              langue: langue, entites: toutes)
    }

    /// « 2026-10-27 rapport.md » → le 27 octobre 2026.
    nonisolated static func dateDuNom(_ nom: String) -> Date? {
        guard let r = nom.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(nom[r]))
    }

    private func enregistrer() {
        try? FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: fichier, options: .atomic) }
    }

    /// L'index oublié : tout sera relu à la prochaine analyse.
    func oublier() {
        tache?.cancel()
        index = [:]
        try? FileManager.default.removeItem(at: fichier)
        entites = []
        etat = .inactif
    }

    // MARK: Le rassemblement

    /// Les entités de tous les documents, une par nom : corrigées par l'utilisateur, complétées par
    /// le cache, les plus répandues d'abord (nombre de documents, puis de mentions). Les sources
    /// citées (médias) sont laissées de côté : elles sont partout et ne disent rien du sujet.
    func rassembler() {
        var parNom: [String: EntiteCoffre] = [:]
        for doc in index.values {
            let corrigees = CorrectionsEntites.partage.appliquer(doc.entites).filter { !$0.source }
            for var e in corrigees {
                if let r = CacheEntites.partage.resolution(e.nom, type: e.type, langue: doc.langue) {
                    e = AnalyseEntites.appliquer(r, a: e)
                }
                let p = Presence(document: doc.id, nom: doc.nom, date: doc.date, mentions: max(e.mentions, 1))
                if var deja = parNom[e.id] {
                    if !deja.presences.contains(where: { $0.document == doc.id }) { deja.presences.append(p) }
                    // Ce qu'un document sait de plus (position, fiche, photo) profite à l'entité.
                    if !deja.entite.aDesCoordonnees, e.aDesCoordonnees {
                        deja.entite.latitude = e.latitude; deja.entite.longitude = e.longitude
                    }
                    deja.entite.qid = deja.entite.qid ?? e.qid
                    deja.entite.image = deja.entite.image ?? e.image
                    deja.entite.description = deja.entite.description ?? e.description
                    parNom[e.id] = deja
                } else {
                    parNom[e.id] = EntiteCoffre(entite: e, presences: [p])
                }
            }
        }
        nombreDocuments = index.count
        entites = parNom.values
            .map { var x = $0; x.presences.sort { $0.date > $1.date }; return x }
            .sorted { ($0.presences.count, $0.mentions, $1.entite.nom) > ($1.presences.count, $1.mentions, $0.entite.nom) }
    }

    /// Les noms qui apparaissent le plus souvent dans les mêmes documents qu'une entité.
    func compagnons(de e: EntiteCoffre, limite: Int = 8) -> [(EntiteCoffre, Int)] {
        let siens = Set(e.presences.map(\.document))
        return entites.compactMap { autre -> (EntiteCoffre, Int)? in
            guard autre.id != e.id else { return nil }
            let communs = autre.presences.filter { siens.contains($0.document) }.count
            return communs > 0 ? (autre, communs) : nil
        }
        .sorted { ($0.1, $0.0.presences.count) > ($1.1, $1.0.presences.count) }
        .prefix(limite).map { $0 }
    }

    /// Les entités situées, pour la carte.
    var situees: [EntiteDocument] { entites.map(\.entite).filter(\.aDesCoordonnees) }

    func entite(nommee nom: String) -> EntiteCoffre? {
        entites.first { $0.entite.nom == nom || $0.id == EntiteDocument.cle(nom) }
    }
}
