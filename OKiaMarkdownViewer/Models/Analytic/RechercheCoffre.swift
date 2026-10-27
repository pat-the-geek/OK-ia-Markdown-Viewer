import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Option Analytic (1.4) — la recherche dans tout le coffre et les documents analysés, et
/// Spotlight (Patrick, 27/10/2026, fonction Mac n° 5).
///
/// - **La recherche** lit le texte des documents (la prose, sans la syntaxe Markdown :
///   `TexteAnalysable`) et le garde en mémoire tant que l'app est ouverte ; seuls les documents
///   nouveaux ou modifiés sont relus. Plusieurs mots : chacun doit y être, où que ce soit ; entre
///   guillemets, l'expression exacte. Sans tenir compte de la casse ni des accents.
/// - **Spotlight** reçoit chaque document — titre, début, texte entier, et les entités que
///   l'analyse du coffre y a trouvées en mots-clés —, et le retrouve depuis le Mac, l'iPhone ou
///   l'iPad ; le toucher l'ouvre dans md Viewer. Seuls les documents nouveaux ou modifiés sont
///   renvoyés (`Analytic/spotlight.json`). Sans l'option, l'index est vidé.
///
/// Un document s'identifie par sa source : `coffre:` et l'identifiant du rapport
/// (`VaultReport.id`), ou `analyse:` et son chemin dans « Documents analysés ».
@MainActor
final class RechercheCoffre: ObservableObject {
    static let partage = RechercheCoffre()

    enum Source: String, Sendable { case coffre, analyse }

    /// Un document, tel que la recherche le garde.
    struct Document: Sendable {
        let id: String
        let source: Source
        let titre: String
        let date: Date
        let modifie: Date
        let texte: String
    }

    /// Un document trouvé.
    struct Resultat: Identifiable, Sendable {
        let id: String
        let source: Source
        let titre: String
        let date: Date
        let occurrences: Int
        /// Le passage autour de la première occurrence, « … » aux bords coupés.
        let extrait: String
        /// Ce que le document cherchera une fois ouvert : la requête entière si elle s'y trouve
        /// telle quelle, sinon son premier terme.
        let aChercher: String
    }

    /// Un document à lire : où il est, et sa date de modification.
    private struct Fichier: Sendable {
        let id: String
        let source: Source
        let url: URL
        let titre: String
        let date: Date
        let modifie: Date
    }

    enum Etat: Equatable {
        case inactif
        case lecture(fait: Int, total: Int)
        case pret
    }

    @Published private(set) var etat: Etat = .inactif
    @Published private(set) var documents: [String: Document] = [:]

    private weak var vault: VaultStore?
    private var lecture: Task<Void, Never>?
    private var spotlight: Task<Void, Never>?

    /// Ce que Spotlight a déjà reçu : identifiant → date de modification.
    private var indexes: [String: Date] = [:]
    private let fichierSpotlight: URL = {
        let dossier = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dossier.appendingPathComponent("Analytic/spotlight.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fichierSpotlight),
           let lu = try? JSONDecoder().decode([String: Date].self, from: data) {
            indexes = lu
        }
    }

    /// Le coffre de l'app — à brancher une fois, au lancement.
    func brancher(_ vault: VaultStore) {
        self.vault = vault
    }

    // MARK: Les sources

    /// Les rapports du coffre et les documents analysés (sans l'option : aucun).
    private func fichiers() async -> [Fichier] {
        guard AchatAnalytic.partage.acces else { return [] }
        var liste: [Fichier] = []
        if let vault, let racine = vault.resolveFolder() {
            for r in vault.reports where r.downloaded {
                liste.append(Fichier(id: "coffre:" + r.id, source: .coffre,
                                     url: racine.appendingPathComponent(r.subfolder).appendingPathComponent(r.name),
                                     titre: (r.name as NSString).deletingPathExtension,
                                     date: AnalyseCoffre.dateDuNom(r.name) ?? r.modified, modifie: r.modified))
            }
        }
        // Le conteneur iCloud se lit hors du fil principal.
        let analyses = await Task.detached { () -> [Fichier] in
            let racine = RangementDocuments.dossierAnalyses().path
            return RangementDocuments.documents().map { d in
                let modifie = (try? d.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? d.date
                let chemin = d.url.path.hasPrefix(racine) ? String(d.url.path.dropFirst(racine.count)) : d.url.lastPathComponent
                return Fichier(id: "analyse:" + chemin, source: .analyse, url: d.url, titre: d.nom,
                               date: d.date, modifie: modifie)
            }
        }.value
        return liste + analyses
    }

    /// Lit le texte d'un fichier du coffre ou des documents analysés.
    private nonisolated static func lire(_ f: Fichier, racineCoffre: URL?) -> String? {
        let scoped = f.source == .coffre && (racineCoffre?.startAccessingSecurityScopedResource() ?? false)
        defer { if scoped { racineCoffre?.stopAccessingSecurityScopedResource() } }
        return try? String(contentsOf: f.url, encoding: .utf8)
    }

    // MARK: La recherche

    /// Met les textes à jour : relit les documents nouveaux ou modifiés, oublie ceux qui ont disparu.
    func actualiser() {
        lecture?.cancel()
        lecture = Task { [weak self] in
            guard let self else { return }
            let tous = await self.fichiers()
            let presents = Set(tous.map(\.id))
            self.documents = self.documents.filter { presents.contains($0.key) }
            let aLire = tous.filter { f in self.documents[f.id].map { $0.modifie < f.modifie } ?? true }
            guard !aLire.isEmpty else { self.etat = .pret; return }
            let racine = self.vault?.resolveFolder()
            self.etat = .lecture(fait: 0, total: aLire.count)
            var lus: [Document] = []
            for (n, f) in aLire.enumerated() {
                guard !Task.isCancelled else { return }
                let doc = await Task.detached { () -> Document? in
                    guard let brut = Self.lire(f, racineCoffre: racine) else { return nil }
                    return Document(id: f.id, source: f.source, titre: f.titre, date: f.date, modifie: f.modifie,
                                    texte: TexteAnalysable.depuis(brut))
                }.value
                if let doc { lus.append(doc) }
                // Par paquets : la liste se met à jour au fil de la lecture, sans republier à chaque document.
                if lus.count >= 25 || n == aLire.count - 1 {
                    for d in lus { self.documents[d.id] = d }
                    lus.removeAll()
                }
                self.etat = .lecture(fait: n + 1, total: aLire.count)
            }
            self.etat = .pret
        }
    }

    /// Les termes d'une requête : les mots, et les expressions entre guillemets.
    nonisolated static func termes(_ requete: String) -> [String] {
        var termes: [String] = []
        var reste = requete
        let guillemets = #"[«"“]\s*([^»"”]+?)\s*[»"”]"#
        while let r = reste.range(of: guillemets, options: .regularExpression) {
            let expression = reste[r].trimmingCharacters(in: CharacterSet(charactersIn: "«»\"“” "))
            if !expression.isEmpty { termes.append(expression) }
            reste.replaceSubrange(r, with: " ")
        }
        termes += reste.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        return termes
    }

    /// Les documents qui portent tous les termes, les plus pertinents d'abord : le titre compte
    /// beaucoup, puis le nombre d'occurrences ; à égalité, le plus récent.
    nonisolated static func chercher(_ requete: String, dans documents: [Document]) -> [Resultat] {
        let termes = termes(requete)
        guard !termes.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let entiere = requete.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "«»\"“” "))
        var trouves: [(Resultat, Int)] = []
        for d in documents {
            var occurrences = 0, score = 0
            var premiere: Range<String.Index>?
            var manque = false
            for t in termes {
                let dansTitre = d.titre.range(of: t, options: options) != nil
                var n = 0
                var debut = d.texte.startIndex
                while n < 200, let r = d.texte.range(of: t, options: options, range: debut..<d.texte.endIndex) {
                    // L'extrait part de l'occurrence la plus haute dans le document, tous termes confondus.
                    if n == 0, premiere.map({ r.lowerBound < $0.lowerBound }) ?? true { premiere = r }
                    n += 1; debut = r.upperBound
                }
                if n == 0 && !dansTitre { manque = true; break }
                occurrences += n
                score += n + (dansTitre ? 50 : 0)
            }
            guard !manque else { continue }
            let tel = termes.count > 1 && d.texte.range(of: entiere, options: options) != nil
            trouves.append((Resultat(id: d.id, source: d.source, titre: d.titre, date: d.date,
                                     occurrences: occurrences,
                                     extrait: premiere.map { extrait(d.texte, autour: $0) } ?? String(d.texte.prefix(160)),
                                     aChercher: tel ? entiere : termes[0]),
                            score + (tel ? 30 : 0)))
        }
        return trouves.sorted { ($0.1, $0.0.date) > ($1.1, $1.0.date) }.map(\.0)
    }

    /// Le passage autour d'une occurrence, coupé aux mots, sur une ligne.
    nonisolated static func extrait(_ texte: String, autour r: Range<String.Index>) -> String {
        let avant = texte.index(r.lowerBound, offsetBy: -70, limitedBy: texte.startIndex) ?? texte.startIndex
        let apres = texte.index(r.upperBound, offsetBy: 130, limitedBy: texte.endIndex) ?? texte.endIndex
        var s = String(texte[avant..<apres])
        if avant > texte.startIndex, let espace = s.firstIndex(where: \.isWhitespace) { s = "…" + s[s.index(after: espace)...] }
        if apres < texte.endIndex, let espace = s.lastIndex(where: \.isWhitespace) { s = s[..<espace] + "…" }
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Spotlight

    nonisolated static let domaines = ["coffre", "analyse"]

    /// Envoie à Spotlight les documents nouveaux ou modifiés, retire ceux qui ont disparu. Sans
    /// l'option, vide l'index. Peu après l'appel : un lot d'imports n'envoie qu'une fois.
    func indexerSpotlight() {
        spotlight?.cancel()
        spotlight = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            let index = CSSearchableIndex.default()
            guard AchatAnalytic.partage.acces else {
                // Au lancement, l'option paraît fermée tant que l'App Store n'a pas répondu.
                if AchatAnalytic.partage.accesConnu, !self.indexes.isEmpty {
                    try? await index.deleteSearchableItems(withDomainIdentifiers: Self.domaines)
                    self.indexes = [:]; self.enregistrerSpotlight()
                }
                return
            }
            let tous = await self.fichiers()
            let presents = Set(tous.map(\.id))
            let partis = self.indexes.keys.filter { !presents.contains($0) }
            if !partis.isEmpty {
                try? await index.deleteSearchableItems(withIdentifiers: Array(partis))
                for id in partis { self.indexes[id] = nil }
            }
            let aEnvoyer = tous.filter { f in self.indexes[f.id].map { $0 < f.modifie } ?? true }
            let racine = self.vault?.resolveFolder()
            // Par paquets de 50 : la mémoire reste basse sur un grand coffre.
            for debut in stride(from: 0, to: aEnvoyer.count, by: 50) {
                guard !Task.isCancelled else { break }
                let paquet = Array(aEnvoyer[debut..<min(debut + 50, aEnvoyer.count)])
                let motsCles = Dictionary(uniqueKeysWithValues: paquet.map { f in
                    (f.id, f.source == .coffre ? AnalyseCoffre.partage.motsCles(String(f.id.dropFirst("coffre:".count))) : [])
                })
                let elements = await Task.detached { () -> [CSSearchableItem] in
                    paquet.compactMap { f in
                        guard let brut = Self.lire(f, racineCoffre: racine) else { return nil }
                        return Self.element(f, texte: TexteAnalysable.depuis(brut), motsCles: motsCles[f.id] ?? [])
                    }
                }.value
                do {
                    try await index.indexSearchableItems(elements)
                    for f in paquet { self.indexes[f.id] = f.modifie }
                } catch {
                    break
                }
            }
            self.enregistrerSpotlight()
        }
    }

    private nonisolated static func element(_ f: Fichier, texte: String, motsCles: [String]) -> CSSearchableItem {
        let a = CSSearchableItemAttributeSet(contentType: .text)
        a.title = f.titre
        a.displayName = f.titre
        a.contentDescription = String(texte.prefix(300))
        a.textContent = String(texte.prefix(200_000))
        a.contentCreationDate = f.date
        a.contentModificationDate = f.modifie
        if !motsCles.isEmpty { a.keywords = motsCles }
        let item = CSSearchableItem(uniqueIdentifier: f.id, domainIdentifier: f.source.rawValue, attributeSet: a)
        // Sans date, Spotlight oublie l'élément au bout d'un mois.
        item.expirationDate = .distantFuture
        return item
    }

    private func enregistrerSpotlight() {
        try? FileManager.default.createDirectory(at: fichierSpotlight.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(indexes) { try? data.write(to: fichierSpotlight, options: .atomic) }
    }

    // MARK: Ouvrir

    /// Le fichier d'un document des documents analysés, d'après son identifiant.
    nonisolated static func urlAnalyse(_ id: String) -> URL? {
        guard id.hasPrefix("analyse:") else { return nil }
        let chemin = String(id.dropFirst("analyse:".count))
        return RangementDocuments.dossierAnalyses().appendingPathComponent(chemin)
    }
}
