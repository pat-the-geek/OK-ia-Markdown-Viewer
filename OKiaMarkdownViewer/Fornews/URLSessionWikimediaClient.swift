// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsServices/Wikimedia/URLSessionWikimediaClient.swift (commit 58fb14e9, 25/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Pourquoi une erreur nommée plutôt qu'un tableau vide.**
///
/// ⛔ `rechercher` jetait l'état HTTP (`let (data, _) = …`) et avalait l'échec de décodage
/// (`try? … ?? []`). Trois pannes très différentes — quota dépassé, User-Agent refusé, réponse
/// illisible — arrivaient toutes à l'écran sous la même forme : « Aucun résultat ». Un utilisateur
/// lisait « Wikidata ne connaît pas cette entité » là où la vraie phrase était « Wikidata nous a
/// répondu 429 ».
///
/// ⚠️ Éprouvé le 01/09/2026 : la recherche restait muette sur « Gemini » et « Maison Blanche »
/// alors que la MÊME requête, avec le MÊME User-Agent, depuis la MÊME machine, rendait sept
/// résultats en 0,3 s. Six hypothèses ont été écartées une à une sans jamais atteindre la cause —
/// parce que le seul témoin, l'app, ne disait rien. Ce type existe pour qu'une septième panne se
/// nomme elle-même.
public enum ErreurWikidata: Error, LocalizedError {
    /// L'API a répondu, mais pas 200 — quota (429), User-Agent refusé (403), panne (5xx).
    case statut(Int)
    /// L'API a répondu 200 avec une enveloppe d'erreur de l'Action API.
    case api(code: String, info: String)
    /// 200, mais le corps n'est pas la réponse attendue.
    case reponseIllisible(octets: Int)

    public var errorDescription: String? {
        switch self {
        case .statut(429):
            return String(localized: "Wikidata a refusé la requête : quota dépassé (429). Réessayez dans un instant.")
        case .statut(403):
            return String(localized: "Wikidata a refusé la requête (403).")
        case .statut(let c):
            return String(localized: "Wikidata a répondu \(c).")
        case .api(let code, let info):
            return String(localized: "Wikidata a signalé une erreur (\(code)) : \(info)")
        case .reponseIllisible(let n):
            return String(localized: "Réponse de Wikidata illisible (\(n) octets).")
        }
    }
}

/// Client Wikimedia réel sur l'API REST publique de Wikidata.
///
/// `rechercher` : `wbsearchentities` puis un appel `wbgetentities` groupé pour récupérer P31.
/// `vignette` : P18 → Commons `Special:FilePath`. Best-effort, tolérant aux pannes réseau.
public struct URLSessionWikimediaClient: WikimediaClient {
    private let session: URLSession
    private let base = "https://www.wikidata.org/w/api.php"
    /// Endpoint SPARQL — utilisé UNIQUEMENT pour les classes P31 par lots, où l'Action API impose
    /// de rapatrier des entités entières (cf. `classes(pour qids:)`).
    private static let sparql = "https://query.wikidata.org/sparql"

    /// Session à timeout COURT : l'enrichissement Wikidata est **best-effort** → un Wikidata
    /// lent/injoignable ne doit pas bloquer l'enrichissement des entités (avant : `URLSession.shared`,
    /// 60 s par défaut). Sur iPhone/iPad on coupe encore plus court (6 s / 12 s) qu'en mode moteur Mac
    /// (12 s / 24 s) : en mobilité, on préfère sauter l'enrichissement Wikidata d'une entité plutôt que
    /// de faire patienter. Homogène avec le fetch de page (iOS 5/10, Mac 10/20).
    private static let sessionCourte: URLSession = {
        let cfg = URLSessionConfiguration.default
        #if os(iOS)
        cfg.timeoutIntervalForRequest  = 6
        cfg.timeoutIntervalForResource = 12
        #else
        cfg.timeoutIntervalForRequest  = 12
        cfg.timeoutIntervalForResource = 24
        #endif
        // ⚠️ Wikimedia (Action API + REST Wikipedia) RENVOIE 403 sans User-Agent descriptif → toutes
        // les recherches/enrichissements échouaient en silence. On envoie le même UA que les flux.
        cfg.httpAdditionalHeaders = ["User-Agent": fornewsUserAgent]
        return URLSession(configuration: cfg)
    }()

    /// `session: nil` → session à timeout court par défaut (injection possible pour les tests).
    public init(session: URLSession? = nil) { self.session = session ?? Self.sessionCourte }

    public func rechercher(_ terme: String, langue: String) async throws -> [WikidataCandidat] {
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "action", value: "wbsearchentities"),
            .init(name: "search", value: terme),
            .init(name: "language", value: langue),
            .init(name: "uselang", value: langue),
            .init(name: "type", value: "item"),
            .init(name: "limit", value: "7"),
            .init(name: "format", value: "json"),
        ]
        guard let url = comps.url else { return [] }
        let (data, reponse) = try await session.data(from: url)
        // ⚠️ L'état HTTP était jeté : un 429 ou un 403 se lisait « Aucun résultat ».
        if let http = reponse as? HTTPURLResponse, http.statusCode != 200 {
            throw ErreurWikidata.statut(http.statusCode)
        }

        struct Reponse: Decodable {
            struct Item: Decodable {
                let id: String; let label: String?; let description: String?
                struct Match: Decodable { let text: String? }
                struct Affichage: Decodable {
                    struct Valeur: Decodable { let language: String? }
                    let description: Valeur?
                }
                let display: Affichage?
                let match: Match?     // ce qui a réellement matché (alias / label d'une autre langue)
            }
            let search: [Item]
        }
        guard let decodee = try? JSONDecoder().decode(Reponse.self, from: data) else {
            // ⛔ 200 sans `search` : l'Action API met alors son motif dans `error`. Le lire est ce
            //    qui sépare « cette entité n'existe pas » de « nous avons été éconduits ».
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any] {
                throw ErreurWikidata.api(code: (err["code"] as? String) ?? "?",
                                         info: (err["info"] as? String) ?? "")
            }
            throw ErreurWikidata.reponseIllisible(octets: data.count)
        }
        let items = decodee.search
        guard !items.isEmpty else { return [] }

        // ⚠️ Même chemin allégé que le retypage : chercher « Paris » rapatriait les revendications
        // ENTIÈRES de chaque candidat — 415 Ko rien que pour Q90 — alors qu'on n'en lit que P31.
        // C'est le chemin d'appariement, le plus chaud du pipeline ; il en profite le plus.
        let types = (try? await classes(pour: items.map(\.id))) ?? [:]
        return items.map {
            WikidataCandidat(
                id: $0.id,
                label: $0.label ?? "",
                description: $0.description,
                instanceOf: types[$0.id] ?? [],
                matchText: $0.match?.text,
                descriptionLangue: $0.display?.description?.language
            )
        }
    }

    public func description(pour qid: String, langue: String) async throws -> String? {
        guard let titre = try await titreWikipedia(qid: qid, langue: langue) else { return nil }
        let encode = titre.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? titre
        guard let url = URL(string: "https://\(langue).wikipedia.org/api/rest_v1/page/summary/\(encode)")
        else { return nil }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["extract"] as? String
    }

    /// Récupère le titre de l'article Wikipedia (sitelink) pour la langue donnée.
    private func titreWikipedia(qid: String, langue: String) async throws -> String? {
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "ids", value: qid),
            .init(name: "props", value: "sitelinks"),
            .init(name: "sitefilter", value: "\(langue)wiki"),
            .init(name: "format", value: "json"),
        ]
        guard let url = comps.url else { return nil }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = json["entities"] as? [String: Any],
              let entite = entities[qid] as? [String: Any],
              let sitelinks = entite["sitelinks"] as? [String: Any],
              let site = sitelinks["\(langue)wiki"] as? [String: Any],
              let titre = site["title"] as? String else { return nil }
        return titre
    }

    public func vignette(pour qid: String) async throws -> String? {
        guard let fichier = try await claimValeurChaine(qid: qid, propriete: "P18") else { return nil }
        let encode = fichier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fichier
        return "https://commons.wikimedia.org/wiki/Special:FilePath/\(encode)?width=320"
    }

    /// Coordonnées (P625) : `mainsnak.datavalue.value.{latitude, longitude}` (Double).
    public func coordonnees(pour qid: String) async throws -> (latitude: Double, longitude: Double)? {
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "ids", value: qid),
            .init(name: "props", value: "claims"),
            .init(name: "format", value: "json"),
        ]
        guard let url = comps.url else { return nil }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = json["entities"] as? [String: Any],
              let entite = entities[qid] as? [String: Any],
              let claims = entite["claims"] as? [String: Any],
              let liste = claims["P625"] as? [[String: Any]] else { return nil }
        for claim in liste {
            if let mainsnak = claim["mainsnak"] as? [String: Any],
               let datavalue = mainsnak["datavalue"] as? [String: Any],
               let value = datavalue["value"] as? [String: Any],
               let lat = value["latitude"] as? Double,
               let lon = value["longitude"] as? Double {
                // ⛔ **P625 ne parle pas que de la Terre.** La revendication porte un `globe`, et
                // les cratères de Mars ou de Vénus s'y repèrent sur 0–360° est. On lisait la
                // première revendication venue : « Olya » est entrée en base à longitude 291,8,
                // hors du monde pour MapKit. On refuse le globe étranger et les bornes dépassées,
                // puis on CONTINUE — une entité peut porter plusieurs revendications, dont une
                // terrestre.
                guard CoordonneeTerrestre.globeEstLaTerre(value["globe"] as? String),
                      CoordonneeTerrestre.estValide(latitude: lat, longitude: lon) else { continue }
                return (lat, lon)
            }
        }
        return nil
    }

    /// **Classes P31 d'une entité — requête CIBLÉE, pas l'entité entière.**
    ///
    /// ⚠️ `wbgetentities&props=claims` rapatrie TOUTES les revendications pour n'en lire qu'une.
    /// Mesuré le 03/08 sur l'API réelle : **Paris (Q90) pèse 415 528 octets** par ce chemin, Berlin
    /// 391 639 — contre **14 519** pour la même question posée à `wbgetclaims&property=P31`, et
    /// ~1,1 Ko en moyenne sur le corpus. Avec `timeoutIntervalForRequest = 6` sur iPhone, ces
    /// centaines de kilo-octets ne passent pas toujours en cellulaire ; l'appel rendait alors `[]`,
    /// que l'appelant traite — à juste titre — comme un refus. D'où l'effet observé sur Paris :
    /// *plus le lieu est célèbre, plus sa fiche est lourde, moins sa vue Look Around apparaît.*
    public func classes(pour qid: String) async throws -> [String] {
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "action", value: "wbgetclaims"),
            .init(name: "entity", value: qid),
            .init(name: "property", value: "P31"),
            .init(name: "format", value: "json"),
        ]
        guard let url = comps.url else { return [] }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        // `wbgetclaims` rend directement `claims`, sans l'enveloppe `entities` de `wbgetentities`.
        return qidsDeClaim(["claims": json["claims"] ?? [:]], propriete: "P31")
    }

    /// **Super-classes P279 d'une classe** — même patron ciblé que `classes(pour:)`, et pour la
    /// même raison : `wbgetclaims&property=P279` rend ~1 Ko là où `wbgetentities` rapatrie la fiche
    /// entière pour n'en lire qu'une revendication.
    ///
    /// ⛔ **Surtout pas SPARQL ici.** Mesuré le 22/08 : le service de requêtes était en panne et
    /// limitait à 1 requête/minute. L'API Action, elle, répondait — et c'est elle qui porte cette
    /// remontée de hiérarchie.
    public func superClasses(pour qid: String) async throws -> [String] {
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "action", value: "wbgetclaims"),
            .init(name: "entity", value: qid),
            .init(name: "property", value: "P279"),
            .init(name: "format", value: "json"),
        ]
        guard let url = comps.url else { return [] }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return qidsDeClaim(["claims": json["claims"] ?? [:]], propriete: "P279")
    }

    /// **Classes P31 de plusieurs entités — une seule requête par lot, via SPARQL.**
    ///
    /// ⚠️ Le lot est ce qui souffrait le plus : sur 50 QID réels du store, `wbgetentities` rend
    /// **6 619 355 octets en un appel** — hors d'atteinte d'un délai de 6 s en cellulaire. Et
    /// `WikimediaService.classes(qids:)` omet simplement un lot qui échoue : **50 entités sautées
    /// sans bruit**, ce qui faisait paraître le retypage inopérant sur iPhone alors qu'il marchait
    /// sur Mac (12 s, lien rapide). Même lot en SPARQL : **21 645 octets**, soit 306 × moins.
    ///
    /// ⛔ **Le fan-out par entité est écarté volontairement** — le protocole le dit : un appel par
    /// entité sur un corpus de plusieurs milliers est un déni de service qu'on s'infligerait autant
    /// qu'à Wikidata. On garde donc UNE requête par lot ; seule sa taille change.
    ///
    /// ⚠️ **`p:P31/ps:P31`, surtout PAS `wdt:P31`.** Le prédicat « truthy » ne garde que le meilleur
    /// rang : sur Paris il ne rend que 6 classes sur 15 et laisse tomber `Q1549591` « grande ville »
    /// et `Q484170` « commune de France » — précisément celles dont dépendent la règle Look Around
    /// et `typeParP31`. Le chemin retenu rend l'identique à l'appel historique, vérifié sur
    /// **50 entités sur 50**, pas sur un échantillon de trois.
    public func classes(pour qids: [String]) async throws -> [String: [String]] {
        guard !qids.isEmpty else { return [:] }
        let valeurs = qids.map { "wd:\($0)" }.joined(separator: " ")
        let requete = "SELECT ?item ?c WHERE { VALUES ?item { \(valeurs) } ?item p:P31/ps:P31 ?c }"

        var rq = URLRequest(url: URL(string: Self.sparql)!)
        rq.httpMethod = "POST"   // un lot de 50 dépasse ce qu'on met raisonnablement en URL
        rq.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        rq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var corps = URLComponents()
        corps.queryItems = [.init(name: "query", value: requete)]
        rq.httpBody = corps.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await session.data(for: rq)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultats = json["results"] as? [String: Any],
              let lignes = resultats["bindings"] as? [[String: Any]] else { return [:] }

        var resultat: [String: Set<String>] = [:]
        for ligne in lignes {
            guard let item = (ligne["item"] as? [String: Any])?["value"] as? String,
                  let classe = (ligne["c"] as? [String: Any])?["value"] as? String else { continue }
            resultat[dernierSegment(item), default: []].insert(dernierSegment(classe))
        }
        return resultat.mapValues { $0.sorted() }
    }

    /// Coordonnée (P625) et description courte (français, sinon anglais) d'un lot de fiches — un seul appel SPARQL.
    /// `schema:version` n'existe que pour une fiche réelle : une fiche supprimée ne revient pas, et n'est donc pas jugée.
    public func localisation(pour qids: [String]) async throws -> [String: Localisation] {
        guard !qids.isEmpty else { return [:] }
        let valeurs = qids.map { "wd:\($0)" }.joined(separator: " ")
        let requete = """
            SELECT ?item ?coord ?fr ?en WHERE {
              VALUES ?item { \(valeurs) }
              ?item schema:version ?v .
              OPTIONAL { ?item wdt:P625 ?coord }
              OPTIONAL { ?item schema:description ?fr FILTER(LANG(?fr) = "fr") }
              OPTIONAL { ?item schema:description ?en FILTER(LANG(?en) = "en") }
            }
            """
        var rq = URLRequest(url: URL(string: Self.sparql)!)
        rq.httpMethod = "POST"
        rq.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        rq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var corps = URLComponents()
        corps.queryItems = [.init(name: "query", value: requete)]
        rq.httpBody = corps.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await session.data(for: rq)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultats = json["results"] as? [String: Any],
              let lignes = resultats["bindings"] as? [[String: Any]] else { return [:] }
        func valeur(_ l: [String: Any], _ cle: String) -> String? { (l[cle] as? [String: Any])?["value"] as? String }
        var out: [String: Localisation] = [:]
        for l in lignes {
            guard let item = valeur(l, "item") else { continue }
            let q = dernierSegment(item)
            let avant = out[q]
            out[q] = Localisation(aDesCoordonnees: (avant?.aDesCoordonnees ?? false) || valeur(l, "coord") != nil,
                                  description: avant?.description ?? valeur(l, "fr") ?? valeur(l, "en"))
        }
        return out
    }

    /// Les fiches d'un lot situées sur un autre astre (P376 ≠ Terre) et nommées d'après un être humain (P138 → Q5).
    public func astresEponymes(pour qids: [String]) async throws -> Set<String>? {
        guard !qids.isEmpty else { return [] }
        let valeurs = qids.map { "wd:\($0)" }.joined(separator: " ")
        let requete = """
            SELECT DISTINCT ?item WHERE {
              VALUES ?item { \(valeurs) }
              ?item wdt:P376 ?astre . FILTER(?astre != wd:Q2)
              ?item wdt:P138 ?personne . ?personne wdt:P31 wd:Q5 .
            }
            """
        var rq = URLRequest(url: URL(string: Self.sparql)!)
        rq.httpMethod = "POST"
        rq.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        rq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var corps = URLComponents()
        corps.queryItems = [.init(name: "query", value: requete)]
        rq.httpBody = corps.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await session.data(for: rq)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultats = json["results"] as? [String: Any],
              let lignes = resultats["bindings"] as? [[String: Any]] else { return nil }
        return Set(lignes.compactMap { (($0["item"] as? [String: Any])?["value"] as? String).map(dernierSegment) })
    }

    /// Société mère / fabricant d'un lot d'entités — un seul appel SPARQL (cf. `classes(pour:)`).
    ///
    /// L'ordre des propriétés est une PRÉFÉRENCE, pas une union : une entité qui déclare à la fois un
    /// fabricant et un propriétaire retient le fabricant. `COALESCE` s'en charge côté serveur.
    public func societesMeres(pour qids: [String]) async throws -> [String: String] {
        guard !qids.isEmpty else { return [:] }
        let valeurs = qids.map { "wd:\($0)" }.joined(separator: " ")
        let requete = """
            SELECT ?item ?parent WHERE {
              VALUES ?item { \(valeurs) }
              OPTIONAL { ?item wdt:P176 ?fab }
              OPTIONAL { ?item wdt:P178 ?dev }
              OPTIONAL { ?item wdt:P749 ?mere }
              OPTIONAL { ?item wdt:P127 ?prop }
              BIND(COALESCE(?fab, ?dev, ?mere, ?prop) AS ?parent)
              FILTER(BOUND(?parent))
            }
            """
        var rq = URLRequest(url: URL(string: Self.sparql)!)
        rq.httpMethod = "POST"
        rq.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        rq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var corps = URLComponents()
        corps.queryItems = [.init(name: "query", value: requete)]
        rq.httpBody = corps.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await session.data(for: rq)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultats = json["results"] as? [String: Any],
              let lignes = resultats["bindings"] as? [[String: Any]] else { return [:] }
        var resultat: [String: String] = [:]
        for ligne in lignes {
            guard let item = (ligne["item"] as? [String: Any])?["value"] as? String,
                  let parent = (ligne["parent"] as? [String: Any])?["value"] as? String else { continue }
            let cle = dernierSegment(item), valeur = dernierSegment(parent)
            // ⛔ Une entité n'est pas sa propre mère (Wikidata contient des boucles de ce genre).
            if cle != valeur { resultat[cle] = valeur }
        }
        return resultat
    }

    /// Libellés et alias d'un élément — appel CIBLÉ (`props=labels|aliases`), quelques kilo-octets,
    /// jamais les revendications entières (cf. `classes(pour:)` et les 415 Ko de Q90).
    public func libellesEtAlias(pour qid: String) async throws -> Set<String> {
        let d = try await libellesDetailles(pour: qid)
        return d.principaux.union(d.tous)
    }

    /// Les mêmes noms, en séparant les LIBELLÉS PRINCIPAUX (`mul`, `fr`, `en`) de tout le reste (alias, autres langues).
    /// ⚠️ L'allemand capitalise tous les noms (« Smartphone », « Film ») : un libellé allemand ne dit pas qu'une fiche est
    /// un nom propre (05/10/2026, cf. `WikimediaService.natureImpossible`).
    public func libellesDetailles(pour qid: String) async throws -> (principaux: Set<String>, tous: Set<String>) {
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "ids", value: qid),
            .init(name: "props", value: "labels|aliases"),
            // ⛔ **`mul` d'abord — sans lui, les noms latins ne reviennent PAS.**
            //
            // Wikidata a déplacé les libellés identiques d'une langue latine à l'autre vers un
            // libellé unique de code `mul` (« multilingue »). Un élément comme **Q22686 — Donald
            // Trump** n'a donc PLUS de libellé `fr` ni `en` : il porte 111 libellés, tous en
            // écritures non latines, plus `mul = "Donald Trump"`. Demander `fr|en|de|it|es` rend
            // alors un ensemble de noms **VIDE**.
            //
            // ⛔ Mesuré le 01/09/2026 sur les 400 entités les plus citées du Mac mini : **27 des
            // 44 « anomalies »** d'un premier croisement n'en étaient pas — Donald Trump, Taylor
            // Swift, Blick, Zendaya, Emmanuel Macron, Tom Holland… tous parfaitement rattachés,
            // tous rendus muets par ce paramètre.
            //
            // ⭐ Le garde-fou « abstention par défaut » évitait le pire (`!noms.isEmpty` avant
            // `designeVraiment`, cf. `WikimediaService.enrichir` ⑲) : aucune fiche n'a jamais été
            // détachée à tort. Mais la vérification ne s'exerçait plus sur ces entités, et
            // `coordonneesSiLeQIDDesigneVraiment` s'abstenait — **ces lieux n'obtenaient jamais
            // leurs coordonnées**, donc jamais leur épingle sur la carte.
            .init(name: "languages", value: "mul|fr|en|de|it|es"),
            .init(name: "format", value: "json"),
        ]
        guard let url = comps.url else { return ([], []) }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entite = (json["entities"] as? [String: Any])?[qid] as? [String: Any]
        else { return ([], []) }

        var noms: Set<String> = []
        var principaux: Set<String> = []
        for (langue, v) in (entite["labels"] as? [String: Any]) ?? [:] {
            if let s = (v as? [String: Any])?["value"] as? String {
                noms.insert(s)
                if ["mul", "fr", "en"].contains(langue) { principaux.insert(s) }
            }
        }
        for (_, v) in (entite["aliases"] as? [String: Any]) ?? [:] {
            for a in (v as? [[String: Any]]) ?? [] {
                if let s = a["value"] as? String { noms.insert(s) }
            }
        }
        return (principaux, noms)
    }

    // MARK: Claims

    /// `https://www.wikidata.org/entity/Q90` → `Q90`. Les résultats SPARQL rendent des URI.
    private func dernierSegment(_ uri: String) -> String {
        String(uri.split(separator: "/").last ?? "")
    }

    private func claimValeurChaine(qid: String, propriete: String) async throws -> String? {
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "ids", value: qid),
            .init(name: "props", value: "claims"),
            .init(name: "format", value: "json"),
        ]
        guard let url = comps.url else { return nil }
        let (data, _) = try await session.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = json["entities"] as? [String: Any],
              let entite = entities[qid] else { return nil }

        guard let claims = (entite as? [String: Any])?["claims"] as? [String: Any],
              let liste = claims[propriete] as? [[String: Any]] else { return nil }
        for claim in liste {
            if let mainsnak = claim["mainsnak"] as? [String: Any],
               let datavalue = mainsnak["datavalue"] as? [String: Any],
               let valeur = datavalue["value"] as? String {
                return valeur
            }
        }
        return nil
    }

    private func qidsDeClaim(_ entite: Any, propriete: String) -> [String] {
        guard let claims = (entite as? [String: Any])?["claims"] as? [String: Any],
              let liste = claims[propriete] as? [[String: Any]] else { return [] }
        return liste.compactMap { claim in
            guard let mainsnak = claim["mainsnak"] as? [String: Any],
                  let datavalue = mainsnak["datavalue"] as? [String: Any],
                  let value = datavalue["value"] as? [String: Any],
                  let id = value["id"] as? String else { return nil }
            return id
        }
    }
}
