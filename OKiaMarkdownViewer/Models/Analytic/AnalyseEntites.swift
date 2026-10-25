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
        self.fichier = fichier ?? dossier.appendingPathComponent("Analytic/entites.json")
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

    /// Deux types qui ne se contredisent pas : le même, deux lieux (fornews ne départage pas une
    /// ville d'une région, cf. `doitCorriger`), ou une organisation et un produit — une enseigne est
    /// l'un et l'autre, et Wikidata rangeait Leroy Merlin en marque.
    static func compatibles(_ a: TypeEntite, _ b: TypeEntite) -> Bool {
        let familles: [Set<TypeEntite>] = [[.loc, .gpe], [.org, .product]]
        return a == b || familles.contains { $0.contains(a) && $0.contains(b) }
    }

    /// La même suite que `WikimediaService.enrichirInterne` dans fornews, sans le modèle SwiftData.
    /// `typeFiable` : le type vient du document (le genre d'un rapport fornews), pas d'une
    /// détection. Un candidat dont la nature Wikidata le contredit cède alors la place au suivant —
    /// sans cette règle, « la CIA » rendait l'aéroport de Rome-Ciampino (code IATA CIA), essai du
    /// 25/10/2026. Pour une détection, le type de Wikidata corrige au contraire celui de `NLTagger`.
    func resoudre(_ nomDuDocument: String, type: TypeEntite, typeFiable: Bool = false,
                  langue: String) async throws -> ResolutionEntite {
        let nom = EntiteDocument.sansArticle(nomDuDocument)
        let client = service.client
        let candidats = try await client.rechercher(nom, langue: langue)
        var choix: WikidataCandidat?
        var restants = candidats
        for _ in 0..<3 {
            guard let c = WikimediaService.choisir(restants, valeur: nom, type: type) else { break }
            var natures = c.instanceOf
            if natures.isEmpty { natures = (try? await client.classes(pour: c.id)) ?? [] }
            let parents = natures.isEmpty ? ((try? await client.superClasses(pour: c.id)) ?? []) : []
            let contredit = typeFiable && WikimediaService.typeDepuisP31(natures).map { !Self.compatibles(type, $0) } == true
            if !contredit, WikimediaService.natureImpossible(type: type, p31: natures, p279: parents,
                                                             noms: [nom], libelles: [c.label], alias: [c.label]) == nil {
                choix = c
                break
            }
            restants.removeAll { $0.id == c.id }
        }
        guard let choix else {
            return ResolutionEntite(type: WikimediaService.typeSansRattachement(candidats, valeur: nom, type: type),
                                    date: Date())
        }
        let estLieu = type == .loc || type == .gpe
        async let descAsync = client.description(pour: choix.id, langue: langue)
        async let imageAsync = client.vignette(pour: choix.id)
        async let coordsAsync = estLieu ? client.coordonnees(pour: choix.id) : nil
        let longue = try? await descAsync
        let image = try? await imageAsync
        let coords = (try? await coordsAsync) ?? nil
        let typeRetenu = WikimediaService.typeDepuisP31(choix.instanceOf).flatMap {
            WikimediaService.doitCorriger(de: type, vers: $0) ? $0 : nil
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
    private let resolveur = ResolveurWikidata()

    /// Les types qu'on montre, et qu'on peut résoudre : ni dates ni montants (fornews les balise
    /// dans la prose, ce ne sont pas des fiches).
    static let typesMontres: [TypeEntite] = [.person, .org, .gpe, .loc, .product, .event, .work, .maladie, .autre]

    var parType: [(type: TypeEntite, entites: [EntiteDocument])] {
        Self.typesMontres.compactMap { t in
            let l = entites.filter { $0.type == t }
            return l.isEmpty ? nil : (t, l)
        }
    }

    /// Les entités situées, pour la carte.
    var situees: [EntiteDocument] { entites.filter(\.aDesCoordonnees) }

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
            toutes = DetecteurEntites.absorberFormesCourtes(toutes)
            toutes = toutes.filter { $0.mentions > 0 || $0.origine == .rapport }
            toutes.sort { ($0.mentions, $1.nom) > ($1.mentions, $0.nom) }
            self.langue = langue
            self.methode = methode
            self.depuisRapport = !duRapport.isEmpty
            self.entites = toutes.map { self.appliquerCache($0) }
            if wikidata == .accepte { self.completerParWikidata() } else { self.etat = .fini }
        }
    }

    private var isMuet: Bool { if case .wikidataMuet = etat { return true }; return false }

    private func appliquerCache(_ e: EntiteDocument) -> EntiteDocument {
        guard let r = CacheEntites.partage.resolution(e.nom, type: e.type, langue: langue) else { return e }
        return Self.appliquer(r, a: e)
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
            e.qid == nil && CacheEntites.partage.resolution(e.nom, type: e.type, langue: langue) == nil
        }
    }

    private func completerParWikidata() {
        let liste = aResoudre
        guard !liste.isEmpty else { etat = .fini; return }
        tache?.cancel()
        etat = .resolution(fait: 0, total: liste.count)
        let langue = self.langue, resolveur = self.resolveur
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
                            let r = try await resolveur.resoudre(e.nom, type: e.type, typeFiable: e.origine == .rapport,
                                                                 langue: langue)
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
                self.etat = .fini
            }
        }
    }
}
