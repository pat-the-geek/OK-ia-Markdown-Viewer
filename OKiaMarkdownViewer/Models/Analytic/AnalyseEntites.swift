import Foundation
import SwiftUI

// Option Analytic (1.4) — l'analyse d'un document, dans l'ordre voulu par Patrick : ce que le
// document donne d'abord (rapport fornews), puis la détection dans le texte, puis — seulement si
// l'utilisateur l'a accepté — Wikidata pour ce qui manque. Le cache des réponses évite de
// redemander deux fois la même entité.

/// L'identité que md Viewer présente à Wikimedia. Le nom est celui qu'attend la copie de
/// `URLSessionWikimediaClient` (fornews) ; la valeur est la nôtre. Wikimedia exige un User-Agent
/// qui nomme l'application et un contact : sans lui, l'API répond 403.
let fornewsUserAgent = "md Viewer/1.4 (https://ok-ia.ch/mdviewer/; patrick@ok-ia.ch)"

/// Le choix de l'utilisateur sur Wikidata — décision de Patrick du 25/10/2026 : proposée, jamais
/// imposée. Tant qu'il n'a pas répondu, rien ne part.
enum ConsentementWikidata: String {
    case jamaisDemande = ""
    case accepte = "oui"
    case refuse = "non"

    static let cle = "okia.analytic.wikidata"
}

/// Ce que Wikidata a répondu pour un nom. `qid == nil` : rien de fiable — on le retient aussi, pour
/// ne pas redemander à chaque ouverture ; la réponse vieillit au bout de 30 jours.
struct ResolutionEntite: Codable, Sendable, Equatable {
    var qid: String?
    var libelle: String?
    var description: String?
    var image: String?
    var latitude: Double?
    var longitude: Double?
    var type: TypeEntite?
    var date: Date

    static let duree: TimeInterval = 30 * 24 * 3600
    var perimee: Bool { Date().timeIntervalSince(date) > Self.duree }
}

/// Le cache des résolutions, sur l'appareil. Clé : langue, type et nom plié.
/// ⚠️ La synchronisation iCloud entre appareils est une tâche du lot ① encore ouverte
/// (TACHES-1.4.md) : elle demande une capacité iCloud que l'app n'a pas encore.
@MainActor
final class CacheEntites {
    static let partage = CacheEntites()

    private var entrees: [String: ResolutionEntite] = [:]
    private let fichier: URL
    private var aEcrire = false

    init(fichier: URL? = nil) {
        let dossier = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        // « v2 » : le choix de fiche a changé le 25/10/2026 (B90) — les réponses de l'ancien choix
        // (NASA → filiale de Saxe-Anhalt) seraient restées trente jours.
        self.fichier = fichier ?? dossier.appendingPathComponent("Analytic/entites-v2.json")
        if let data = try? Data(contentsOf: self.fichier),
           let lues = try? JSONDecoder().decode([String: ResolutionEntite].self, from: data) {
            entrees = lues
        }
    }

    static func cle(_ nom: String, type: TypeEntite, langue: String) -> String {
        "\(langue)|\(type.rawValue)|\(EntiteDocument.cle(nom))"
    }

    func resolution(_ nom: String, type: TypeEntite, langue: String) -> ResolutionEntite? {
        guard let r = entrees[Self.cle(nom, type: type, langue: langue)], !r.perimee else { return nil }
        return r
    }

    func retenir(_ r: ResolutionEntite, nom: String, type: TypeEntite, langue: String) {
        entrees[Self.cle(nom, type: type, langue: langue)] = r
        guard !aEcrire else { return }
        aEcrire = true
        // Une écriture par salve, pas une par entité.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.ecrire() }
    }

    func vider() {
        entrees = [:]
        try? FileManager.default.removeItem(at: fichier)
    }

    var nombre: Int { entrees.count }

    private func ecrire() {
        aEcrire = false
        try? FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entrees) { try? data.write(to: fichier, options: .atomic) }
    }
}

/// La résolution d'un nom par Wikidata, avec les règles de choix de fornews (`WikimediaService`,
/// copié dans `Fornews/`) : on écarte un candidat de nature impossible (« Nasa » → un genre de
/// plantes), on n'épingle pas un pays sur sa moyenne, et l'on s'abstient plutôt que de se tromper.
/// Seul le NOM part, jamais le document, ni son titre, ni le contexte de la phrase.
struct ResolveurWikidata: Sendable {
    let service = WikimediaService(client: URLSessionWikimediaClient())

    /// Une description qui n'en est pas une : le résumé Wikipédia rend parfois une adresse.
    static func descriptionLisible(_ d: String?) -> String? {
        guard let d = d?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty,
              d.range(of: #"^(?:https?://|www\.)\S*$"#, options: .regularExpression) == nil else { return nil }
        return d
    }

    /// La suite de `WikimediaService.enrichirInterne` dans fornews (description, image, position,
    /// genre corrigé), sans le modèle SwiftData, et avec un choix fait pour le nom seul.
    /// `typeFiable` : le type vient du document (le genre d'un rapport fornews) — « la CIA » ne
    /// rend plus l'aéroport de Rome-Ciampino. Pour une détection, le type de Wikidata corrige au
    /// contraire celui de `NLTagger`.
    /// `refuses` : les fiches que l'utilisateur a écartées pour ce nom (« ce n'est pas la bonne »).
    func resoudre(_ nomDuDocument: String, type: TypeEntite, typeFiable: Bool = false,
                  refuses: Set<String> = [], langue: String) async throws -> ResolutionEntite {
        let nom = EntiteDocument.sansArticle(nomDuDocument)
        let candidats = try await service.client.rechercher(nom, langue: langue).filter { !refuses.contains($0.id) }
        // Le nom seul : la fiche la plus ancienne dont le nom correspond et dont le genre tient
        // (`ChoixWikidata`) ; sinon, on s'abstient. Le choix de fornews, fait pour des articles
        // avec leur contexte, prenait l'homonyme obscur (NASA → une filiale de Saxe-Anhalt).
        guard let choix = ChoixWikidata.candidats(candidats, nom: nom, type: type, typeFiable: typeFiable).first else {
            return ResolutionEntite(type: WikimediaService.typeSansRattachement(candidats, valeur: nom, type: type),
                                    date: Date())
        }
        return try await fiche(choix, type: type, langue: langue)
    }

    /// Les fiches que Wikidata propose pour un nom, pour que l'utilisateur choisisse lui-même : TOUTES
    /// celles que la recherche rend, sans les règles de choix — c'est justement qu'elles se sont
    /// trompées. Les plus anciennes d'abord.
    func propositions(_ nomDuDocument: String, langue: String) async throws -> [WikidataCandidat] {
        let nom = EntiteDocument.sansArticle(nomDuDocument)
        return try await service.client.rechercher(nom, langue: langue)
            .sorted { ChoixWikidata.numero($0) < ChoixWikidata.numero($1) }
    }

    /// La fiche complète d'un candidat : description, photo, et position pour un lieu.
    func fiche(_ choix: WikidataCandidat, type: TypeEntite, langue: String) async throws -> ResolutionEntite {
        let client = service.client
        let estLieu = type == .loc || type == .gpe || WikimediaService.typeDepuisP31(choix.instanceOf).map { $0 == .loc || $0 == .gpe } == true
        async let descAsync = client.description(pour: choix.id, langue: langue)
        async let imageAsync = client.vignette(pour: choix.id)
        async let coordsAsync = estLieu ? client.coordonnees(pour: choix.id) : nil
        let longue = try? await descAsync
        let image = try? await imageAsync
        let coords = (try? await coordsAsync) ?? nil
        // Le genre de la fiche, retenu aussi quand il confirme celui qu'on avait : une fiche choisie
        // par l'utilisateur doit porter son genre, sinon l'entité retombe sur celui de la détection
        // (« autre » pour le repli par majuscules).
        let typeRetenu = WikimediaService.typeDepuisP31(choix.instanceOf).flatMap {
            $0 == type || WikimediaService.doitCorriger(de: type, vers: $0) ? $0 : nil
        }
        let courte = Self.descriptionLisible(WikimediaService.descriptionDansLaLangue(choix, langue: langue))
        var r = ResolutionEntite(qid: choix.id, libelle: choix.label,
                                 description: Self.descriptionLisible(longue) ?? courte,
                                 image: image, type: typeRetenu, date: Date())
        // ⛔ Pas d'épingle sur un pays, un continent, une mer : leur coordonnée est une moyenne.
        if let coords, WikimediaService.coordonneeALeSens(choix.instanceOf) {
            r.latitude = coords.latitude
            r.longitude = coords.longitude
        }
        return r
    }
}

/// L'analyse d'un document, tenue par le lecteur : la liste, la galerie et la carte la partagent,
/// et elle survit à la fermeture du panneau tant que le document reste ouvert.
@MainActor
final class AnalyseEntites: ObservableObject {
    enum Etat: Equatable {
        case inactif
        case lecture
        /// La résolution Wikidata : combien de noms sont faits, sur combien.
        case resolution(fait: Int, total: Int)
        case fini
        /// Wikidata a refusé ou ne répond pas : la liste reste, sans ce qui manquait.
        case wikidataMuet(String)
    }

    @Published private(set) var entites: [EntiteDocument] = []
    @Published private(set) var etat: Etat = .inactif
    /// Le document est un rapport fornews : sa section `## Entités` a été lue.
    @Published private(set) var depuisRapport = false
    @Published private(set) var langue = "fr"
    /// Le moyen de détection qui a servi (NLTagger, Apple Intelligence, majuscules).
    @Published private(set) var methode: DetecteurEntites.Methode?

    /// Le diagnostic n'est montré que dans les builds de test (Xcode, TestFlight sur iPhone et
    /// iPad), pour que Patrick puisse le lire et le recopier : jamais dans l'App Store.
    static var diagnosticVisible: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// Une ligne à recopier : moyen de détection, langue, nombre d'entités.
    var diagnostic: String {
        "Détection : \(methode?.rawValue ?? "—") · langue \(langue) · \(entites.count) entités"
            + (depuisRapport ? " · rapport fornews" : "")
    }

    private var documentAnalyse: UUID?
    private var tache: Task<Void, Never>?
    /// Les entités telles que le document et la détection les donnent, avant les corrections de
    /// l'utilisateur et le cache : une correction se rejoue à partir d'elles, sans relire le texte.
    private var brutes: [EntiteDocument] = []
    private var wikidata: ConsentementWikidata = .refuse
    private let resolveur = ResolveurWikidata()

    /// Les types qu'on montre, et qu'on peut résoudre : ni dates ni montants (fornews les balise
    /// dans la prose, ce ne sont pas des fiches).
    static let typesMontres: [TypeEntite] = [.person, .org, .gpe, .loc, .product, .event, .work, .maladie, .autre]

    var parType: [(type: TypeEntite, entites: [EntiteDocument])] {
        Self.typesMontres.compactMap { t in
            let l = entites.filter { $0.type == t && !$0.source }
            return l.isEmpty ? nil : (t, l)
        }
    }

    /// Les entités situées, pour la carte.
    var situees: [EntiteDocument] { entites.filter { $0.aDesCoordonnees && !$0.source } }

    /// Les sources que le document cite, à part des entités de son texte.
    var sources: [EntiteDocument] { entites.filter(\.source) }

    /// L'entité qu'un marqueur de la carte désigne (son lien `[[nom]]`).
    func entite(nommee nom: String) -> EntiteDocument? {
        let cle = EntiteDocument.cle(nom)
        return entites.first { $0.id == cle }
    }

    /// La configuration d'une carte, au format que `render.js` lit (`parseLeafletBlock`), en base64 :
    /// un marqueur par entité située, son nom en lien pour qu'un toucher ouvre sa fiche. Sans centre
    /// ni zoom, la carte s'ajuste aux marqueurs.
    static func configurationCarte(_ entites: [EntiteDocument]) -> String {
        let marqueurs: [[String: Any]] = entites.compactMap { e in
            guard let lat = e.latitude, let lon = e.longitude else { return nil }
            return ["lat": lat, "lng": lon, "label": e.nom, "link": e.nom]
        }
        let cfg: [String: Any] = ["markers": marqueurs, "lat": NSNull(), "lng": NSNull(), "zoom": NSNull(),
                                  "minZoom": 1, "maxZoom": 18, "height": "420px", "defaultTiles": NSNull()]
        let data = (try? JSONSerialization.data(withJSONObject: cfg)) ?? Data()
        return data.base64EncodedString()
    }

    var enCours: Bool {
        switch etat {
        case .lecture, .resolution: return true
        default: return false
        }
    }

    func annuler() {
        tache?.cancel()
        tache = nil
        documentAnalyse = nil
        entites = []
        etat = .inactif
    }

    /// Lance l'analyse du document, une fois par document. `wikidata` : le choix de l'utilisateur.
    func analyser(_ document: MarkdownDocument, wikidata: ConsentementWikidata, force: Bool = false) {
        guard force || documentAnalyse != document.id else {
            self.wikidata = wikidata
            // Le même document, mais l'utilisateur vient d'accepter Wikidata : on complète.
            if wikidata == .accepte, etat == .fini || isMuet { completerParWikidata() }
            // …ou de le refuser en pleine résolution : plus un nom ne part.
            if wikidata != .accepte, case .resolution = etat {
                tache?.cancel()
                etat = .fini
            }
            return
        }
        tache?.cancel()
        documentAnalyse = document.id
        self.wikidata = wikidata
        brutes = []
        etat = .lecture
        let texte = document.text
        tache = Task { [weak self] in
            let langue = TexteAnalysable.langue(texte) ?? Localization.shared.code
            let duRapport = LecteurRapportFornews.lire(texte)
            let (detectees, methode) = await DetecteurEntites.detecter(texte, langue: langue)
            guard let self, !Task.isCancelled else { return }
            // Le document d'abord : une entité du rapport garde son genre et ses coordonnées ; la
            // détection n'ajoute que ce qu'il ne nommait pas.
            // Une entité par nom : la détection rend parfois le même nom sous deux genres (« United
            // States » lieu et organisation) ou avec son article (« l'Iran », « Iran »). Deux lignes
            // au même identifiant, SwiftUI en perdait à l'affichage. Le premier lu l'emporte.
            var toutes = LecteurRapportFornews.dedoublonner(duRapport + detectees)
            DetecteurEntites.compterMentions(&toutes, dans: texte)
            let sources = SourcesDocument.lire(texte)
            for i in toutes.indices where sources.contient(toutes[i]) { toutes[i].source = true }
            toutes = DetecteurEntites.absorberFormesCourtes(toutes)
            toutes = toutes.filter { $0.mentions > 0 || $0.origine == .rapport }
            toutes.sort { ($0.mentions, $1.nom) > ($1.mentions, $0.nom) }
            self.langue = langue
            self.methode = methode
            self.depuisRapport = !duRapport.isEmpty
            self.brutes = toutes
            self.assembler()
            if wikidata == .accepte { self.completerParWikidata() } else { self.etat = .fini }
        }
    }

    /// La liste montrée : les entités brutes, corrigées par l'utilisateur, complétées par le cache,
    /// puis réunies quand elles désignent la même fiche.
    private func assembler() {
        entites = CorrectionsEntites.partage.appliquer(brutes)
            .map { appliquerCache($0) }
            .sorted { ($0.mentions, $1.nom) > ($1.mentions, $0.nom) }
        fusionnerParQID()
        reunirVariantes()
    }

    // MARK: Corrections de l'utilisateur

    /// L'utilisateur signale une erreur : la correction est retenue pour tous les documents, et la
    /// liste se refait aussitôt. Un nom à qui l'on a retiré sa fiche, ou changé le genre, repart
    /// vers Wikidata si l'utilisateur l'a accepté.
    func corriger(_ e: EntiteDocument, _ changement: (inout CorrectionEntite) -> Void) {
        CorrectionsEntites.partage.modifier(e.nom, changement)
        guard etat != .lecture else { return }
        assembler()
        if wikidata == .accepte { completerParWikidata() }
    }

    func correction(_ e: EntiteDocument) -> CorrectionEntite? { CorrectionsEntites.partage.correction(e.nom) }

    var wikidataAccepte: Bool { wikidata == .accepte }

    /// Les corrections d'un nom oubliées : il redevient ce que la détection et Wikidata en disent.
    func oublierCorrections(_ e: EntiteDocument) {
        CorrectionsEntites.partage.oublier(e.nom)
        guard etat != .lecture else { return }
        assembler()
        if wikidata == .accepte { completerParWikidata() }
    }

    func oublierToutesLesCorrections() {
        CorrectionsEntites.partage.toutOublier()
        guard etat != .lecture else { return }
        assembler()
        if wikidata == .accepte { completerParWikidata() }
    }

    var nombreDeCorrections: Int { CorrectionsEntites.partage.nombre }

    /// Les fiches entre lesquelles l'utilisateur choisit.
    func propositions(pour e: EntiteDocument, terme: String? = nil) async throws -> [WikidataCandidat] {
        try await resolveur.propositions(terme ?? e.nom, langue: langue)
    }

    /// L'utilisateur a choisi une fiche : elle est complétée (description, photo, position) puis
    /// retenue ; l'ancienne fiche passe parmi les refusées.
    func choisirFiche(_ choix: WikidataCandidat, pour e: EntiteDocument) async throws {
        var r = try await resolveur.fiche(choix, type: e.type, langue: langue)
        // La description que l'utilisateur a lue pour choisir, même dans une autre langue, plutôt
        // que rien.
        if r.description == nil { r.description = ResolveurWikidata.descriptionLisible(choix.description) }
        corriger(e) { c in
            if let ancienne = e.qid, ancienne != choix.id, !c.qidsRefuses.contains(ancienne) { c.qidsRefuses.append(ancienne) }
            c.qidsRefuses.removeAll { $0 == choix.id }
            c.fiche = r
            c.sansFiche = false
        }
    }

    /// « Aucune fiche ne convient » : le nom reste, sans fiche, et ne repart plus vers Wikidata.
    func retirerFiche(_ e: EntiteDocument) {
        corriger(e) { c in
            if let q = e.qid, !c.qidsRefuses.contains(q) { c.qidsRefuses.append(q) }
            c.fiche = nil
            c.sansFiche = true
        }
    }

    /// Deux entités rattachées à la même fiche n'en font qu'une : deux graphies (« Riyad »,
    /// « Riyadh »), une forme courte que rien n'avait réunie. Elle garde le nom le plus cité et
    /// l'origine du document s'il en vient ; les mentions s'additionnent (Patrick, B89).
    private func fusionnerParQID() {
        var vus: [String: Int] = [:]
        var garde: [EntiteDocument] = []
        for e in entites {
            guard let q = e.qid else { garde.append(e); continue }
            if let i = vus[q] {
                var a = garde[i]
                let principale = (e.mentions > a.mentions || (e.origine == .rapport && a.origine != .rapport)) ? e : a
                let autre = principale == e ? a : e
                a = principale
                a.mentions = principale.mentions + autre.mentions
                a.genre = a.genre ?? autre.genre
                if !a.aDesCoordonnees { a.latitude = autre.latitude; a.longitude = autre.longitude }
                garde[i] = a
            } else {
                vus[q] = garde.count
                garde.append(e)
            }
        }
        if garde.count != entites.count { entites = garde.sorted { ($0.mentions, $1.nom) > ($1.mentions, $0.nom) } }
    }

    /// Une variante d'orthographe restée sans fiche (« Ryad ») rejoint le nom à une lettre près qui
    /// en a une (« Riyad »), du même genre. Seulement APRÈS Wikidata : sans fiches, « Iran » et
    /// « Irak » se ressemblent tout autant (Patrick, B90).
    private func reunirVariantes() {
        var retirees = Set<String>()
        var liste = entites
        // Un nom que l'utilisateur a corrigé n'est pas réuni à sa place : il a dit ce qu'il voulait.
        for e in entites where e.qid == nil && !e.source && e.id.count >= 4
            && CorrectionsEntites.partage.correction(e.nom) == nil {
            guard let j = liste.firstIndex(where: { f in
                f.qid != nil && !f.source && f.id != e.id && !retirees.contains(f.id)
                    && ChoixWikidata.compatibles(e.type, f.type)
                    && DetecteurEntites.distance(e.id, f.id) <= (max(e.id.count, f.id.count) >= 8 ? 2 : 1)
            }) else { continue }
            retirees.insert(e.id)
            liste[j].mentions += e.mentions
        }
        if !retirees.isEmpty { entites = liste.filter { !retirees.contains($0.id) } }
    }

    private var isMuet: Bool { if case .wikidataMuet = etat { return true }; return false }

    private func appliquerCache(_ e: EntiteDocument) -> EntiteDocument {
        var e = completer(e)
        if CorrectionsEntites.partage.correction(e.nom)?.sansImage == true { e.image = nil }
        return e
    }

    private func completer(_ e: EntiteDocument) -> EntiteDocument {
        if let c = CorrectionsEntites.partage.correction(e.nom) {
            if c.sansFiche { return e }
            // La fiche choisie par l'utilisateur l'emporte sur ce que le document en disait.
            if let f = c.fiche {
                var e = e
                e.qid = f.qid
                e.description = f.description ?? e.description
                e.image = f.image ?? e.image
                if let lat = f.latitude, let lon = f.longitude { e.latitude = lat; e.longitude = lon }
                if c.type == nil, let t = f.type { e.type = t }
                return e
            }
        }
        guard let r = resolutionEnCache(e) else { return e }
        return Self.appliquer(r, a: e)
    }

    /// La réponse du cache, sauf si elle désigne une fiche que l'utilisateur a refusée.
    private func resolutionEnCache(_ e: EntiteDocument) -> ResolutionEntite? {
        guard let r = CacheEntites.partage.resolution(e.nom, type: e.type, langue: langue) else { return nil }
        if let q = r.qid, CorrectionsEntites.partage.correction(e.nom)?.qidsRefuses.contains(q) == true { return nil }
        return r
    }

    /// Ce que Wikidata apprend s'ajoute à ce que le document donne, sans jamais l'écraser : les
    /// coordonnées d'un rapport fornews restent les siennes, son genre aussi.
    static func appliquer(_ r: ResolutionEntite, a e: EntiteDocument) -> EntiteDocument {
        var e = e
        guard r.qid != nil else { return e }
        e.qid = r.qid
        e.description = e.description ?? r.description
        e.image = e.image ?? r.image
        if !e.aDesCoordonnees, let lat = r.latitude, let lon = r.longitude {
            e.latitude = lat; e.longitude = lon
        }
        if e.origine == .detection, let t = r.type { e.type = t }
        return e
    }

    /// Les noms à demander : ceux qui n'ont ni fiche ni réponse en cache, les plus cités d'abord.
    private var aResoudre: [EntiteDocument] {
        entites.filter { e in
            // Deux lettres ou moins : trop ambigu pour le nom seul (« IA » rendait Internet Archive).
            let c = CorrectionsEntites.partage.correction(e.nom)
            return e.qid == nil && !e.source && EntiteDocument.sansArticle(e.nom).count > 2
                && c?.sansFiche != true && c?.fiche == nil && resolutionEnCache(e) == nil
        }
    }

    private func completerParWikidata() {
        let liste = aResoudre
        guard !liste.isEmpty else { etat = .fini; return }
        tache?.cancel()
        etat = .resolution(fait: 0, total: liste.count)
        let langue = self.langue, resolveur = self.resolveur
        // Un genre donné par l'utilisateur vaut celui d'un rapport : Wikidata ne le contredit pas.
        let corrections = Dictionary(liste.map { ($0.id, CorrectionsEntites.partage.correction($0.nom)) },
                                     uniquingKeysWith: { a, _ in a })
        tache = Task { [weak self] in
            var fait = 0
            // Trois noms à la fois : assez pour ne pas faire attendre, assez peu pour rester poli
            // envers un service public et gratuit.
            await withTaskGroup(of: (EntiteDocument, Result<ResolutionEntite, Error>).self) { groupe in
                var suivant = 0
                func lancer() {
                    guard suivant < liste.count else { return }
                    let e = liste[suivant]; suivant += 1
                    groupe.addTask {
                        do {
                            let c = corrections[e.id] ?? nil
                            let r = try await resolveur.resoudre(e.nom, type: e.type,
                                                                 typeFiable: e.origine == .rapport || c?.type != nil,
                                                                 refuses: Set(c?.qidsRefuses ?? []), langue: langue)
                            return (e, .success(r))
                        }
                        catch { return (e, .failure(error)) }
                    }
                }
                for _ in 0..<3 { lancer() }
                var echecs = 0, derniere: Error?
                while let (e, issue) = await groupe.next() {
                    guard let self, !Task.isCancelled else { groupe.cancelAll(); return }
                    fait += 1
                    switch issue {
                    case .success(let r):
                        CacheEntites.partage.retenir(r, nom: e.nom, type: e.type, langue: langue)
                        if let i = self.entites.firstIndex(where: { $0.id == e.id }) {
                            self.entites[i] = Self.appliquer(r, a: self.entites[i])
                            if corrections[e.id]??.sansImage == true { self.entites[i].image = nil }
                        }
                    case .failure(let erreur):
                        echecs += 1; derniere = erreur
                    }
                    // Wikidata muet dès le début (hors ligne, quota) : on s'arrête net plutôt que
                    // d'user le réseau pour rien.
                    if echecs >= 5, echecs == fait {
                        groupe.cancelAll()
                        self.etat = .wikidataMuet(derniere?.localizedDescription ?? "")
                        return
                    }
                    self.etat = .resolution(fait: fait, total: liste.count)
                    lancer()
                }
                guard let self else { return }
                self.fusionnerParQID()
                self.reunirVariantes()
                self.etat = .fini
            }
        }
    }
}
