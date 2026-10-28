// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsServices/Wikimedia/WikimediaService.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : sans les fonctions qui écrivent dans le modèle SwiftData (enrichir, appliquerCandidat,
// geolocaliser, fusionnerSiDoublon) ; restent le protocole du client et les règles de choix.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

public extension Notification.Name {
    /// Postée quand une entité est renommée / enrichie sans changement de nombre (les vues qui
    /// cachent leur liste par compte doivent se rafraîchir).
    static let fornewsEntitesModifiees = Notification.Name("ai.fornews.native.entitesModifiees")
}

/// Candidat Wikidata pour une entité (résultat de recherche + types `instance of`/P31).
public struct WikidataCandidat: Sendable, Equatable {
    public var id: String              // Q…
    public var label: String           // libellé canonique dans la langue de recherche
    public var description: String?
    public var instanceOf: [String]    // QIDs de P31 (peut être vide si inconnu)
    /// Texte qui a **réellement matché** la recherche (`wbsearchentities.match.text`) : peut être un
    /// alias ou le label d'une AUTRE langue. Ex. « London » match le label anglais de Q84 (Londres),
    /// dont le label fr est « Londres » → indispensable pour la correspondance exacte cross-langue.
    public var matchText: String?
    /// Langue RÉELLE de `description` (`display.description.language`). Wikidata se rabat sur
    /// l'anglais quand la langue demandée n'a pas de description : `nil` = inconnue.
    public var descriptionLangue: String?

    public init(id: String, label: String, description: String? = nil,
                instanceOf: [String] = [], matchText: String? = nil, descriptionLangue: String? = nil) {
        self.descriptionLangue = descriptionLangue
        self.id = id
        self.label = label
        self.description = description
        self.instanceOf = instanceOf
        self.matchText = matchText
    }
}

extension WikimediaService {
    /// La description courte du candidat, seulement si elle est rédigée dans `langue`.
    /// ⚠️ Langue inconnue (`nil`, anciens clients de test) : on la garde, comme avant.
    static func descriptionDansLaLangue(_ c: WikidataCandidat, langue: String) -> String? {
        guard let d = c.description, !d.isEmpty else { return nil }
        guard let l = c.descriptionLangue else { return d }
        let cible = langue.lowercased().split(separator: "-").first.map(String.init) ?? langue
        return l.lowercased().split(separator: "-").first.map(String.init) == cible ? d : nil
    }
}

/// Accès Wikimedia (injectable pour les tests).
public protocol WikimediaClient: Sendable {
    func rechercher(_ terme: String, langue: String) async throws -> [WikidataCandidat]
    func vignette(pour qid: String) async throws -> String?
    /// Description longue (résumé d'introduction Wikipedia) pour l'entité.
    func description(pour qid: String, langue: String) async throws -> String?
    /// Coordonnées géographiques (Wikidata **P625**) — pour les lieux/pays (`loc`/`gpe`).
    func coordonnees(pour qid: String) async throws -> (latitude: Double, longitude: Double)?
    /// Classes **P31** d'une entité déjà identifiée. Le type NER dit « c'est un lieu » ; seul le P31
    /// dit **quel genre de lieu** — un stade ou un continent, ce qui ne se regarde pas pareil.
    func classes(pour qid: String) async throws -> [String]
    /// Libellés **et alias** d'un élément, toutes langues servies. Sert à vérifier qu'un QID déjà
    /// attaché désigne bien ce que l'entité nomme — cf. `WikimediaService.designeVraiment`.
    func libellesEtAlias(pour qid: String) async throws -> Set<String>
    /// Libellés principaux (`mul`, `fr`, `en`) et tous les noms (alias, autres langues) — cf. `natureImpossible`.
    func libellesDetailles(pour qid: String) async throws -> (principaux: Set<String>, tous: Set<String>)
    /// **Société mère / fabricant de plusieurs entités**, en un appel (⑤ ① — mesure du 21/08).
    ///
    /// Quatre propriétés Wikidata, dans cet ordre de préférence : `P176` (fabricant), `P178`
    /// (développeur), `P749` (maison mère), `P127` (propriétaire). C'est ce qui rattache `AirPods`,
    /// `Siri`, `iOS 27` ou `Safari` à **Apple** sans qu'aucune liste ne soit écrite à la main.
    ///
    /// ⛔ **Ni `P108` (employeur) ni `P169` (dirigeant)** : Tim Cook travaille chez Apple, mais un
    /// article sur Tim Cook n'est pas nécessairement un article sur Apple. La règle vaut pour ce
    /// qu'une société **fabrique**, pas pour qui elle emploie.
    func societesMeres(pour qids: [String]) async throws -> [String: String]

    /// **Super-classes `P279` d'une CLASSE** — le pas élémentaire de la remontée de hiérarchie
    /// (cf. `CoherenceType`). Une classe à la fois, à dessein : les classes se partagent entre
    /// entités, donc chacune n'est demandée **qu'une seule fois dans la vie de l'app**, ce qu'un
    /// appel par lot ne saurait pas exploiter.
    func superClasses(pour qid: String) async throws -> [String]

    /// Classes P31 de **plusieurs** entités en un appel. ⚠️ Indispensable pour le retypage de
    /// l'existant : un appel par entité sur un corpus de plusieurs milliers, c'est un déni de
    /// service qu'on s'infligerait à soi-même autant qu'à Wikidata.
    func classes(pour qids: [String]) async throws -> [String: [String]]

    /// **Coordonnée (P625) et description courte de plusieurs fiches**, en un appel (04/10/2026). Une fiche absente
    /// de la réponse n'existe pas ou l'appel a échoué : on ne juge que ce qui revient.
    func localisation(pour qids: [String]) async throws -> [String: Localisation]

    /// **Les fiches d'un objet situé sur un AUTRE ASTRE et nommé d'après une personne** (P376 ≠ Terre, P138 → humain),
    /// parmi celles demandées (05/10/2026 : « Gogol » → un cratère de Mercure). `nil` : la réponse n'a pas pu être lue.
    func astresEponymes(pour qids: [String]) async throws -> Set<String>?
}

/// Ce que Wikidata dit d'une fiche pour savoir si elle désigne un LIEU (cf. `LieuSansCoordonnees`).
public struct Localisation: Sendable, Equatable {
    public let aDesCoordonnees: Bool
    public let description: String?
    public init(aDesCoordonnees: Bool, description: String?) {
        self.aDesCoordonnees = aDesCoordonnees; self.description = description
    }
}

public extension WikimediaClient {
    func description(pour qid: String, langue: String) async throws -> String? { nil }
    func coordonnees(pour qid: String) async throws -> (latitude: Double, longitude: Double)? { nil }
    func classes(pour qid: String) async throws -> [String] { [] }
    func libellesEtAlias(pour qid: String) async throws -> Set<String> { [] }
    /// Défaut : les noms connus, sans distinguer les principaux — aucune exception de concept ne joue alors.
    func libellesDetailles(pour qid: String) async throws -> (principaux: Set<String>, tous: Set<String>) {
        ([], try await libellesEtAlias(pour: qid))
    }
    func classes(pour qids: [String]) async throws -> [String: [String]] { [:] }
    /// Défaut VIDE : un client qui ne sait pas répondre ne fait reclasser aucun lieu.
    func localisation(pour qids: [String]) async throws -> [String: Localisation] { [:] }
    /// Défaut : on ne sait pas (`nil`) — aucune fiche retirée, aucune mémorisée comme vérifiée.
    func astresEponymes(pour qids: [String]) async throws -> Set<String>? { nil }
    /// Défaut VIDE : `CoherenceType` compte les liens obtenus et **s'abstient** quand il n'en obtient
    /// aucun — un client qui ne sait pas répondre ne fait donc jamais condamner un rattachement.
    func superClasses(pour qid: String) async throws -> [String] { [] }
    /// Défaut VIDE : un client qui ne sait pas répondre ne rattache rien, plutôt que d'obliger
    /// chaque implémentation (et chaque double de test) à s'en occuper.
    func societesMeres(pour qids: [String]) async throws -> [String: String] { [:] }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  Témoin d'exécuteur — où l'écriture SwiftData a-t-elle VRAIMENT lieu ?
// ════════════════════════════════════════════════════════════════════════════════════════════



/// Enrichissement des entités via Wikidata/Wikipedia, avec **linking conservateur** (§10.4) :
/// on n'attache un QID qu'en cas de correspondance fiable et non ambiguë.
public struct WikimediaService: Sendable {
    /// Exposé (et non `private`) pour que les passes qui interrogent Wikidata **sans enrichir une
    /// entité** — `RattachementSocieteMere` — réutilisent le MÊME client, donc le même User-Agent et
    /// la même session, plutôt que d'en fabriquer un second.
    public let client: WikimediaClient
    public init(client: WikimediaClient) { self.client = client }





    // MARK: Typage depuis Wikidata

    /// **Le QID attaché désigne-t-il vraiment ce que l'entité nomme ?**
    ///
    /// Comparaison sur le NOM, insensible à la casse et aux accents, contre les labels **et alias**
    /// de l'élément dans les cinq langues servies. Les alias comptent : « Ofen » est un alias
    /// légitime de Budapest, « NYC » de New York — les écarter ferait perdre de vrais lieux.
    ///
    /// ⛔ Abstention par défaut : sans réponse franche (réseau, QID absent, aucun nom connu), on ne
    /// complète pas. Un lieu sans carte est réparable ; une épingle fausse est une information
    /// fausse, et elle est publiée à tous les lecteurs.
    static func designeVraiment(_ noms: Set<String>, valeur: String) -> Bool {
        guard !noms.isEmpty else { return false }
        let cible = normaliserNom(valeur)
        return !cible.isEmpty && noms.contains { normaliserNom($0) == cible }
    }

    /// ⚠️ **L'apostrophe typographique compte.** Mesuré le 03/08 sur les 1 158 lieux déjà
    /// cartographiés : « Château-d’Œx » (apostrophe courbe U+2019, celle des textes de presse) était
    /// rejeté alors que Wikidata écrit « Château-d'Œx » avec l'apostrophe droite. Même chose pour
    /// « Europe de l’Est », « L’Olympia », « République islamique d’Iran ». Sans cette
    /// normalisation, la garde s'abstient sur de VRAIS lieux — elle ne fabrique rien de faux, mais
    /// elle prive de carte des entités parfaitement rattachées.
    static func normaliserNom(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")   // ’ apostrophe courbe
            .replacingOccurrences(of: "\u{02BC}", with: "'") // ʼ lettre apostrophe
            .replacingOccurrences(of: "\u{2018}", with: "'") // ‘ guillemet simple ouvrant
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }


    /// Classes P31 d'une entité déjà liée à Wikidata. `[]` si l'appel échoue — un « je ne sais pas »
    /// que l'appelant doit traiter comme un refus, jamais comme une permission.
    public func classes(qid: String) async -> [String] {
        (try? await client.classes(pour: qid)) ?? []
    }

    /// Classes P31 de plusieurs entités, par lots. Un lot qui échoue est simplement absent du
    /// résultat — l'appelant ne doit corriger que ce dont il a la réponse.
    public func classes(qids: [String], parLot: Int = 50) async -> [String: [String]] {
        var resultat: [String: [String]] = [:]
        for debut in stride(from: 0, to: qids.count, by: parLot) {
            let lot = Array(qids[debut..<min(debut + parLot, qids.count)])
            if let r = try? await client.classes(pour: lot) { resultat.merge(r) { a, _ in a } }
        }
        return resultat
    }

    /// Natures P31 par lots, ET les fiches SANS nature : celles qui manquent dans un lot qui a répondu pour les autres
    /// (la requête ne rend aucune ligne pour elles). Un lot qui échoue en entier ne dit rien — ses fiches ne sont ni
    /// dans l'un ni dans l'autre.
    public func naturesParLot(qids: [String], parLot: Int = 50) async -> (natures: [String: [String]], sansNature: Set<String>) {
        var natures: [String: [String]] = [:]
        var sans = Set<String>()
        for debut in stride(from: 0, to: qids.count, by: parLot) {
            let lot = Array(qids[debut..<min(debut + parLot, qids.count)])
            guard let r = try? await client.classes(pour: lot), !r.isEmpty else { continue }
            natures.merge(r) { a, _ in a }
            sans.formUnion(Set(lot).subtracting(r.keys))
        }
        return (natures, sans)
    }

    /// Les fiches d'astres éponymes parmi `qids`, par lots ; `verifiees` : celles dont la réponse a été lue.
    public func astresEponymesParLot(qids: [String], parLot: Int = 300) async -> (eponymes: Set<String>, verifiees: Set<String>) {
        var eponymes = Set<String>(), verifiees = Set<String>()
        for debut in stride(from: 0, to: qids.count, by: parLot) where !Task.isCancelled {
            let lot = Array(qids[debut..<min(debut + parLot, qids.count)])
            guard let r = try? await client.astresEponymes(pour: lot) else { continue }
            eponymes.formUnion(r)
            verifiees.formUnion(lot)
        }
        return (eponymes, verifiees)
    }

    /// Coordonnée et description courte de plusieurs fiches, par lots ; un lot qui échoue est simplement absent.
    public func localisationParLot(qids: [String], parLot: Int = 50) async -> [String: Localisation] {
        var out: [String: Localisation] = [:]
        for debut in stride(from: 0, to: qids.count, by: parLot) where !Task.isCancelled {
            let lot = Array(qids[debut..<min(debut + parLot, qids.count)])
            guard let r = try? await client.localisation(pour: lot) else { continue }
            out.merge(r) { a, _ in a }
        }
        return out
    }

    /// Les catégories parentes (P279) d'une fiche ; `[]` si l'appel échoue.
    public func superClasses(qid: String) async -> [String] {
        (try? await client.superClasses(pour: qid)) ?? []
    }

    // MARK: Lieux qu'on peut REGARDER

    /// **Classes dont la coordonnée est une MOYENNE — et une moyenne ne se photographie pas.**
    ///
    /// Le danger n'est pas l'absence d'imagerie : `MKLookAroundSceneRequest` rend alors `nil` et
    /// rien ne s'affiche. Le danger est l'inverse — « France » a une coordonnée comme toute entité,
    /// son centroïde quelque part vers Bourges, et Apple y a de l'imagerie. On montrerait une route
    /// de campagne présentée comme le lieu de l'actualité.
    ///
    /// ⚠️ **C'est une liste de REFUS, et c'est un renversement assumé.** J'avais d'abord écrit une
    /// liste d'autorisation — plus prudente en principe. La mesure l'a démolie : **Berlin**,
    /// **Kharkiv** et **Engelberg** (le cas signalé par Patrick le 03/08) ne portent AUCUNE classe
    /// générale, seulement des classes nationales — « commune de Suisse » Q70208, et deux classes
    /// ukrainiennes pour Kharkiv. Autoriser localité par localité, c'est réécrire la nomenclature
    /// administrative de chaque pays ; on n'aurait jamais fini, et la fonction serait restée
    /// invisible presque partout.
    ///
    /// Les classes à refuser, elles, sont peu nombreuses et stables : un pays est un pays dans
    /// toutes les langues. Le compromis est donc inversé — on peut montrer une vue pour un
    /// département, ce qui est discutable ; on n'en montrera pas pour un pays ni un océan.
    ///
    /// ⛔ Table **curée**, comme `typeParP31` : elle s'étoffera au fil des cas rencontrés.
    public static let classesLieuTropVaste: Set<String> = [
        "Q6256",      // pays
        "Q3624078",   // État souverain
        "Q7275",      // État
        "Q82794",     // zone géographique
        "Q1620908",   // région historique
        "Q5107",      // continent
        "Q165",       // mer
        "Q9430",      // océan
        "Q46831",     // chaîne de montagnes
        "Q23442",     // île
    ]

    /// **Une coordonnée PONCTUELLE a-t-elle un sens pour ce lieu ?**
    ///
    /// ⚠️ La table `classesLieuTropVaste` existait depuis le 03/08 — mais elle ne servait qu'à
    /// Look Around (`estLieuVisitable`). Le raisonnement qui l'accompagne vaut pourtant à
    /// l'identique pour l'ÉPINGLE : « "France" a une coordonnée comme toute entité, son centroïde
    /// quelque part vers Bourges ». Une moyenne ne se photographie pas ; elle ne s'épingle pas
    /// davantage.
    ///
    /// Mesuré sur le store iPhone le 15/08, exactement ce que décrit le rapport de terrain de
    /// Patrick : **Europe → 48,69 / 9,14, soit Stuttgart**. Asie → Xinjiang. Afrique, France,
    /// Italie, Espagne, Allemagne, Ukraine, Maroc, Colombie : toutes épinglées sur un point
    /// arbitraire. Une épingle fausse est pire qu'une épingle absente — elle est crédible.
    ///
    /// ⚠️ **P31 inconnu → on ÉCRIT quand même.** L'abstention priverait de carte des villes
    /// parfaitement légitimes dont la classe n'a pas été récupérée. Le doute ne justifie pas ici
    /// de retirer, seulement de ne pas conclure : la passe rétroactive tranchera avec la donnée
    /// autoritative.
    public static func coordonneeALeSens(_ instanceOf: [String]) -> Bool {
        !instanceOf.contains(where: classesLieuTropVaste.contains)
    }

    /// **Divisions administratives de premier niveau — refusées, SAUF si le lieu est aussi une
    /// localité.**
    ///
    /// ⚠️ **Second niveau de refus, et il ne se confond pas avec le premier.** Un pays reste refusé
    /// même s'il est aussi une ville (cf. `estLieuVisitable` et son test cité-État : le doute
    /// profite au refus). Une division administrative, elle, se cumule très souvent avec une vraie
    /// ville — et là, refuser serait une faute.
    ///
    /// ⚠️ **Mesuré le 03/08 sur le corpus réel**, pas supposé : sur les 1 140 entités géolocalisées
    /// portant un QID, 117 ont une classe qui descend de `Q10864048`. Sur ces 117, **24 sont AUSSI
    /// des localités** — Berlin (Land), Hambourg (Land *et* ville libre d'Empire), Moscou (ville
    /// fédérale), Istanbul, Hongkong, Mexico, Cologne, Nuremberg, Chongqing, Bucarest, Kinshasa…
    /// Les refuser en bloc aurait supprimé Look Around exactement là où il a le plus de sens. Les
    /// 93 autres — Alaska, Bretagne, Argovie, Bade-Wurtemberg — sont des divisions pures, dont la
    /// coordonnée est un centroïde : c'est le cas « France, quelque part vers Bourges ».
    ///
    /// ⛔ **`Q10864048` et `Q6465` ont été DÉPLACÉES ici depuis le refus absolu.** Elles y causaient
    /// un défaut vivant : Bucarest et Kinshasa portent `Q10864048` en direct et n'avaient donc
    /// aucune vue, alors que ce sont des capitales parfaitement regardables.
    ///
    /// Table relevée par `p:P31/ps:P31` + `wdt:P279*` jusqu'à `Q10864048`, sur les entités du store.
    /// Elle s'étoffera au fil des corpus — une classe absente ne fait que laisser passer.
    public static let classesDivisionAdministrative: Set<String> = [
        "Q6465",        // département français
        "Q10742",       // communauté autonome d'Espagne
        "Q16110",       // région de l'Italie
        "Q23058",       // canton de la Suisse
        "Q35657",       // État des États-Unis
        "Q36784",       // région de France
        "Q38911",       // kraj de la République tchèque
        "Q41162",       // république de Russie
        "Q43263",       // sujet fédéral de Russie
        "Q46395",       // territoire britannique d'outre-mer
        "Q50198",       // province de Thaïlande
        "Q50337",       // préfecture du Japon
        "Q57053",       // comitat de Croatie
        "Q57318",       // ville libre d'Empire
        "Q183342",      // ville fédérale de Russie
        "Q204910",      // gouvernorat de l'Égypte
        "Q236036",      // subdivisions territoriales de l'Union soviétique
        "Q261543",      // État d'Autriche
        "Q462778",      // zone insulaire des États-Unis
        "Q482821",      // ville métropolitaine
        "Q499073",      // municipalité sous juridiction centrale
        "Q501094",      // État du Venezuela
        "Q641078",      // gouvernorats d'Oman
        "Q654140",      // provinces de la république démocratique du Congo
        "Q743074",      // régions du Mali
        "Q746290",      // État du Soudan
        "Q779415",      // région administrative spéciale de Chine
        "Q815068",      // département du Paraguay
        "Q835714",      // oblast de Russie
        "Q843886",      // préfecture de la République centrafricaine
        "Q867094",      // région du Burkina Faso
        "Q1053630",     // province de Papouasie-Nouvelle-Guinée
        "Q1208802",     // municipalité
        "Q1221156",     // Land d'Allemagne
        "Q1344695",     // province d'Iran
        "Q1615742",     // province de la Chine
        "Q1710033",     // région autonome à statut spécial
        "Q2716259",     // municipalité métropolitaine de Turquie
        "Q2736168",     // nationalité historique
        "Q3336843",     // nation constitutive du Royaume-Uni
        "Q10864048",    // division administrative de premier niveau
        "Q11828004",    // province du Canada
        "Q12014176",    // province du Turkménistan
        "Q12443800",    // État de l'Inde
        "Q15063586",    // État de la Malaisie
        "Q15149663",    // État du Mexique
        "Q16532593",    // ville autonome d'Espagne
        "Q20528428",    // entité fédérative du Mexique
        "Q26830017",    // État du Saint-Empire
        "Q104117291",   // région d'Espagne
        "Q113136497",   // État de la Confédération germanique
        "Q124313007",   // préfecture métropolitaine
    ]

    /// **Classes qui disent « c'est une localité » — RATTRAPAGE, pas liste d'autorisation.**
    ///
    /// ⚠️ La distinction est ce qui rend cette liste sûre, là où une liste d'autorisation avait
    /// échoué (`e89ace0` : Engelberg, Kharkiv et Berlin ne portent que des classes nationales). Ici
    /// une classe manquante n'interdit rien : elle ne joue QUE pour une entité déjà porteuse d'une
    /// classe de division administrative. Engelberg, qui n'en porte aucune, passe sans jamais
    /// consulter cette table.
    ///
    /// Vérifiée sur les 24 collisions mesurées : chacune porte au moins une de ces classes.
    public static let classesLocalite: Set<String> = [
        "Q515",       // ville
        "Q1549591",   // grande ville
        "Q3957",      // petite ville
        "Q532",       // village
        "Q5119",      // capitale
        "Q200250",    // métropole
        "Q174844",    // mégapole
        "Q208511",    // ville mondiale
        "Q1637706",   // ville de plus d'un million d'habitants
        "Q486972",    // établissement humain
        "Q15284",     // commune
        "Q484170",    // commune de France
        "Q70208",     // commune de Suisse
        "Q262166",    // commune d'Allemagne
        "Q747074",    // commune d'Italie
    ]

    /// L'entité désigne-t-elle un lieu qu'on peut regarder ?
    ///
    /// ⚠️ **Aucune classe connue → non.** Un appel Wikidata qui échoue rend `[]` : traiter ce
    /// « je ne sais pas » comme une permission ferait apparaître la vue au hasard des pannes réseau.
    /// **Objets bâtis — un point, pas une étendue.** Liste CURÉE, reprise de l'ancienne liste
    /// d'autorisation (build 440) où elle avait été relue à la main.
    ///
    /// ⛔ **Surtout pas une remontée `P279*`.** Essayée le 03/08 pour ce même besoin : sur les 7
    /// entités à coordonnée grossière qu'elle classait « bâtiment », **5 étaient des villes** —
    /// Austin, Salt Lake City, Raleigh, Kansas City, Verbier. L'ontologie Wikidata est un
    /// enchevêtrement, exactement comme `typeParP31` le documente déjà. Seuls Las Vegas Strip et
    /// l'aéroport d'Édimbourg étaient réellement bâtis.
    public static let classesObjetBati: Set<String> = [
        "Q41176",    // bâtiment
        "Q811979",   // ouvrage architectural
        "Q483110",   // stade
        "Q33506",    // musée
        "Q207694",   // musée d'art
        "Q1248784",  // aéroport
        "Q55488",    // gare ferroviaire
        "Q4989906",  // monument
        "Q16970",    // église
        "Q23413",    // château
        "Q12280",    // pont
        "Q22698",    // parc
        "Q174782",   // place publique
        "Q79007",    // rue
        "Q41253",    // salle de cinéma
        "Q24354",    // théâtre
        "Q1060829",  // salle de concert
        "Q3918",     // université
        "Q16917",    // hôpital
        "Q11707",    // restaurant
        "Q27686",    // hôtel
        "Q11315",    // centre commercial
    ]

    /// **Jusqu'où chercher une vue autour du point — selon la TAILLE de ce qu'on désigne.**
    ///
    /// Rayons en degrés de latitude (0,003° ≈ 330 m). Le point exact est toujours essayé en
    /// premier ; ces valeurs ne servent qu'en cas d'échec.
    ///
    /// ⚠️ **Le réglage resserre, il n'élargit pas.** Mesuré le 03/08 sur 10 lieux à coordonnée
    /// grossière en pays couvert : 6 trouvent au point exact, 2 sont rattrapés à 330 m, et 2 ne
    /// rendent RIEN même à 6 km. **Aucun cas entre 660 m et 6 km** — la couverture suit les routes,
    /// soit elle est là, soit il n'y en a pas. Élargir davantage ne rapporterait donc rien, et
    /// montrerait une rue au hasard à des kilomètres du sujet.
    ///
    /// ⛔ **Un objet bâti n'a droit à aucun élargissement.** Sa coordonnée désigne un point précis :
    /// une vue prise à 330 m d'un musée n'est pas le musée, c'est une rue voisine présentée comme
    /// lui. C'est la faute que toute cette fonction existe pour éviter, à l'échelle du bâtiment.
    public static func rayonsAlentours(_ instanceOf: [String]) -> [Double] {
        if instanceOf.contains(where: classesObjetBati.contains) { return [] }
        if instanceOf.contains(where: classesLocalite.contains) { return [0.003, 0.006] }
        // Ni bâti ni localité reconnue (classes nationales, Kharkiv…) : un seul palier, prudent.
        return [0.003]
    }

    /// Deux niveaux de refus, et ils ne se valent pas :
    /// 1. **Absolu** — pays, océan, continent… : le refus l'emporte sur tout, même si l'entité est
    ///    aussi une ville (cité-État). Le doute profite au refus.
    /// 2. **Division administrative** — État américain, canton, Land… : refusé SEULEMENT si rien
    ///    n'indique par ailleurs une localité. Hambourg est un Land ET une ville ; sa coordonnée
    ///    n'est pas une moyenne, et elle se regarde très bien.
    public static func estLieuVisitable(_ instanceOf: [String]) -> Bool {
        guard !instanceOf.isEmpty else { return false }
        guard !instanceOf.contains(where: classesLieuTropVaste.contains) else { return false }
        let estDivision = instanceOf.contains(where: classesDivisionAdministrative.contains)
        let estLocalite = instanceOf.contains(where: classesLocalite.contains)
        return !estDivision || estLocalite
    }

    /// **Le type d'une entité, déduit de son P31 Wikidata.**
    ///
    /// ⚠️ Le type vient aujourd'hui d'une SUPPOSITION du modèle NER, alors qu'une source
    /// d'autorité est déjà consultée pour la même entité. Constaté le 01/08 sur un export réel :
    /// « Visual Studio » (Q134067) typé `gpe`, « Microsoft Silverlight » (Q489048) typé `org` —
    /// deux logiciels. Un lieu erroné finit épinglé sur la carte du monde ; c'est le défaut le plus
    /// visible de la chaîne.
    ///
    /// ⛔ **Table de CERTITUDES, pas de probabilités.** Elle ne contient que des types dont la
    /// correspondance ne se discute pas. Un P31 absent de la table ne corrige rien : on garde ce
    /// que le NER a dit. C'est la même règle d'abstention que pour le rattachement d'un QID —
    /// mieux vaut un type incertain qu'un type faux affirmé par nous.
    static let typeParP31: [String: TypeEntite] = [
        // ⚠️ **Table RELEVÉE sur le corpus réel**, pas écrite de mémoire. Méthode : les 8 083 entités
        // du store qui portent un QID, leurs 11 735 valeurs de P31, dont 2 327 classes distinctes ;
        // les 184 classes ci-dessous en couvrent 71 % et ont été relues une à une.
        //
        // ⛔ Deux approches ont été écartées en chemin, chacune vérifiée :
        // 1. Les classes GÉNÉRALES (« logiciel » Q7397, « organisation » Q43229). Le P31 réel d'un
        //    logiciel n'est presque jamais « logiciel » : Visual Studio est un « environnement de
        //    développement intégré », Silverlight un « cadre applicatif ». Sur 56 entités `gpe`
        //    tirées du corpus, cette table-là n'en corrigeait qu'UNE.
        // 2. La remontée automatique de l'arbre `P279*` jusqu'à des racines. L'ontologie Wikidata
        //    est un enchevêtrement : une ville y descend à la fois de « lieu » et d'« organisation »,
        //    un logiciel d'« œuvre de création ». Le classement qui en sortait typait Firefox et
        //    Red Bull en « œuvre », et le Washington Post en « produit ». Pire que l'existant.
        //
        // Ce qui reste : une liste de CERTITUDES relues à la main. Une classe absente ne corrige
        // rien — le type du NER est conservé. Régénérable via `Scripts/classes-wikidata.py`.
        // ── Personnes
        "Q5": .person,
        // ── Organisations — entreprises, médias, clubs, partis, institutions
        "Q3918": .org, "Q7278": .org, "Q11032": .org, "Q18127": .org, "Q22687": .org,
        "Q31855": .org, "Q35127": .org, "Q41298": .org, "Q43229": .org, "Q46970": .org,
        "Q161726": .org, "Q163740": .org, "Q192283": .org, "Q207694": .org, "Q210167": .org,
        "Q215380": .org, "Q219577": .org, "Q327333": .org, "Q368290": .org, "Q375336": .org,
        "Q476028": .org, "Q484652": .org, "Q561068": .org, "Q658255": .org, "Q778575": .org,
        "Q783794": .org, "Q786820": .org, "Q847017": .org, "Q875538": .org, "Q891723": .org,
        "Q1002697": .org, "Q1005418": .org, "Q1058914": .org, "Q1107679": .org, "Q1110794": .org,
        "Q1137109": .org, "Q1153191": .org, "Q1254874": .org, "Q1331793": .org, "Q1371037": .org,
        "Q1589009": .org, "Q1616075": .org, "Q1752939": .org, "Q1762059": .org, "Q2001305": .org,
        "Q2085381": .org, "Q4830453": .org, "Q5009242": .org, "Q5633421": .org, "Q6576792": .org,
        "Q6881511": .org, "Q10689397": .org, "Q11396960": .org, "Q11422536": .org,
        "Q17232649": .org, "Q17431399": .org, "Q18388277": .org, "Q23002039": .org,
        "Q45400320": .org, "Q62078547": .org, "Q113025511": .org,
        // ── Entités géopolitiques — pays, cantons, communes, quartiers
        "Q515": .gpe, "Q532": .gpe, "Q3957": .gpe, "Q6256": .gpe, "Q6465": .gpe, "Q7270": .gpe,
        "Q15284": .gpe, "Q23058": .gpe, "Q35657": .gpe, "Q56061": .gpe, "Q62049": .gpe,
        "Q70208": .gpe,
        // ⚠️ Ajoutée le 03/08 après mesure sur corpus réel : « Hockey Club Fribourg-Gottéron »
        // (Q4498974) était typé `gpe` — un club de hockey épinglé comme lieu. La classe manquait,
        // donc rien ne pouvait le corriger.
        "Q4498974": .org, "Q112099": .gpe, "Q123480": .gpe, "Q123705": .gpe, "Q133442": .gpe,
        "Q174844": .gpe, "Q179164": .gpe, "Q200250": .gpe, "Q208511": .gpe, "Q257391": .gpe,
        "Q484170": .gpe, "Q486972": .gpe, "Q498162": .gpe, "Q685309": .gpe, "Q707813": .gpe,
        "Q747074": .gpe, "Q902814": .gpe, "Q1093829": .gpe, "Q1115575": .gpe, "Q1187811": .gpe,
        "Q1549591": .gpe, "Q2074737": .gpe, "Q2264924": .gpe, "Q3024240": .gpe, "Q3624078": .gpe,
        "Q5123999": .gpe, "Q7930989": .gpe, "Q10864048": .gpe, "Q12131624": .gpe,
        "Q13218391": .gpe, "Q14770218": .gpe, "Q15127012": .gpe, "Q17343829": .gpe,
        "Q42744322": .gpe, "Q51576574": .gpe, "Q51929311": .gpe, "Q54935504": .gpe,
        "Q108178728": .gpe, "Q127693126": .gpe,
        // ── Lieux physiques et ouvrages
        "Q165": .loc, "Q4022": .loc, "Q8502": .loc, "Q23397": .loc, "Q23442": .loc, "Q41176": .loc,
        "Q46831": .loc, "Q55488": .loc, "Q82794": .loc, "Q355304": .loc, "Q644371": .loc,
        "Q811979": .loc, "Q928830": .loc, "Q1076486": .loc, "Q1200957": .loc, "Q1248784": .loc,
        "Q3502482": .loc, "Q94993988": .loc,
        // ── Logiciels, services et produits — la famille la plus mal typée par le NER
        "Q341": .product, "Q7397": .product, "Q9135": .product, "Q9143": .product,
        "Q13741": .product, "Q166142": .product, "Q167270": .product, "Q189210": .product,
        "Q218616": .product, "Q241317": .product, "Q271680": .product, "Q431289": .product,
        "Q506883": .product, "Q620615": .product, "Q756637": .product, "Q811701": .product,
        "Q1077784": .product, "Q1130645": .product, "Q1186723": .product, "Q1639024": .product,
        "Q3220391": .product, "Q3231690": .product, "Q3257930": .product, "Q10429667": .product,
        "Q10929058": .product, "Q19723451": .product, "Q19967801": .product, "Q21127166": .product,
        "Q59152282": .product, "Q115305900": .product,
        // ── Œuvres — films, séries, albums, jeux
        "Q571": .work, "Q7366": .work, "Q7889": .work, "Q11424": .work, "Q134556": .work,
        "Q196600": .work, "Q202866": .work, "Q482994": .work, "Q5398426": .work, "Q7058673": .work,
        "Q7725634": .work, "Q105543609": .work,
        // ── Événements — festivals, élections, guerres
        "Q198": .event, "Q40231": .event, "Q220505": .event, "Q868557": .event, "Q1190554": .event,
        "Q1656682": .event, "Q13418847": .event, "Q15275719": .event,
        // ── Maladies
        "Q12136": .maladie, "Q929833": .maladie, "Q18123741": .maladie, "Q112193867": .maladie,

        // ═══ Relevé du 23/08/2026 — le corpus a presque doublé (10 480 entités à QID contre 8 083)
        //
        // Régénéré par `Scripts/classes-wikidata.py` : 203 classes atteignent 8 occurrences, dont
        // **52 que la table ignorait**. Les familles ci-dessous ne se discutent pas ; les cas
        // douteux ont été laissés dehors, où ils ne corrigent rien (`typeDepuisP31` rend `nil`, le
        // type du NER est conservé) — c'est le sens même de cette table : des CERTITUDES.
        //
        // ⛔ Écartés à dessein, faute de famille évidente : « salle de cinéma » (lieu ou société ?),
        // « standard technique », « catégorie de produits », « groupe de récompenses ».

        // ── Ce qui n'est PAS une personne, et que le NER prenait pour telle
        //
        // 🔑 **La plus grosse prise du relevé : 171 occurrences de PERSONNAGES DE FICTION.** Batman
        // et Dark Vador arrivaient dans le corpus avec le type `person`, donc dans les fiches, les
        // dossiers et le classement par poids, à égalité avec des dirigeants réels. `autre` ne les
        // efface pas — il cesse simplement de les présenter comme des gens.
        "Q15632617": .autre, "Q15773347": .autre, "Q1114461": .autre, "Q15773317": .autre,
        "Q15711870": .autre, "Q1569167": .autre, "Q3658341": .autre, "Q80447738": .autre,
        "Q20643955": .autre,
        // Vivant, minéral et abstrait — jamais des acteurs de l'actualité.
        //
        // ⛔ **`Q8928` (constellation) en est ABSENTE, et c'est délibéré.** C'est la classe de
        // l'affaire « CNC → Cancer », et l'y mettre DÉFAIT le correctif : le type passerait de
        // `org` à `autre`, or `autre` est compatible avec tout — `CoherenceType` cesserait alors de
        // s'appliquer et la description « constellation du zodiaque » reviendrait sur la fiche.
        // Un typage plus juste y aurait coûté la garde qui protège vraiment. Mon propre test l'a
        // signalé dans la minute.
        "Q16521": .autre, "Q7187": .autre, "Q3863": .autre,
        "Q1288568": .autre, "Q33742": .autre, "Q188451": .autre, "Q11862829": .autre,
        "Q28640": .autre, "Q1047113": .autre, "Q112144412": .autre,

        // ── Entités géopolitiques — l'essentiel du reliquat, et sans ambiguïté
        // ⛔ `Q334453` n'est PAS un lieu : c'est la « division » d'une entreprise ou d'une administration (« unité
        // d'organisation »). Rangée ici, elle faisait de « Microsoft AI », « Google AI », « BBC Radio » des lieux
        // (04/10/2026, rapport « Anthropic »). Déplacée dans les organisations.
        "Q106389302": .gpe, "Q253030": .gpe, "Q11183787": .gpe, "Q334453": .org,
        "Q7897276": .gpe, "Q192287": .gpe, "Q3184121": .gpe, "Q2755753": .gpe,
        "Q748149": .gpe, "Q26211545": .gpe, "Q43263": .gpe,

        // ── Organisations
        "Q33506": .org, "Q708676": .org, "Q20857065": .org, "Q245065": .org,
        "Q13393265": .org, "Q118140435": .org,

        // ── Lieux
        "Q22808403": .loc,

        // ── Œuvres
        "Q15416": .work, "Q55850593": .work, "Q3305213": .work, "Q21198342": .work,

        // ── Produits
        "Q6368": .product, "Q1668024": .product, "Q2462003": .product, "Q4182287": .product,

        // ── Événements
        "Q18608583": .event,
    ]

    /// Faut-il vraiment réécrire le type ?
    ///
    /// ⚠️ **`loc` et `gpe` ne se départagent PAS.** Une ville est à la fois un lieu et une entité
    /// géopolitique ; Wikidata tranche (Q515 → `gpe`), le NER tranche autrement, et les deux se
    /// valent — même épingle sur la carte, même affichage. Corriger cette nuance ferait muter des
    /// milliers d'entités du corpus pour un résultat invisible, chacune repartant à l'export
    /// CloudKit. On ne réécrit que ce qui change quelque chose pour l'utilisateur.
    public static func doitCorriger(de ancien: TypeEntite, vers nouveau: TypeEntite) -> Bool {
        let geo: Set<TypeEntite> = [.loc, .gpe]
        if geo.contains(ancien) && geo.contains(nouveau) { return false }
        return ancien != nouveau
    }

    /// Le type déduit, ou `nil` s'il n'y a **aucune certitude**.
    ///
    /// ⚠️ **Unanimité exigée.** Une entité peut porter plusieurs P31 (« entreprise » ET « éditeur
    /// de logiciels ») : tant qu'ils désignent la même famille, on tranche ; dès qu'ils se
    /// contredisent, on s'abstient. Trancher au premier venu ferait dépendre le résultat de l'ordre
    /// de réponse de l'API.
    public static func typeDepuisP31(_ instanceOf: [String]) -> TypeEntite? {
        let connus = Set(instanceOf.compactMap { typeParP31[$0] })
        return connus.count == 1 ? connus.first : nil
    }

    // MARK: Sélection conservatrice

    /// Types Wikidata (P31) **jamais** un lieu : œuvres, personnes, organisations. Un libellé de lieu
    /// qui ne matche QUE l'un d'eux est un faux positif (« Caroline » → chanson). Liste de refus, donc
    /// non exhaustive sans risque : un type manquant laisse simplement le candidat passer (pas de
    /// régression sur les vrais lieux).
    static let typesNonLieu: Set<String> = [
        "Q5",                                              // être humain
        "Q7366", "Q134556", "Q482994", "Q2188189",         // chanson, single, album, œuvre/composition musicale
        "Q105543609", "Q207628",                           // œuvre musicale, composition musicale
        "Q11424", "Q24856", "Q5398426", "Q1259759",        // film, série de films, série télévisée, mini-série
        "Q571", "Q7725634", "Q47461344", "Q49084",         // livre, œuvre littéraire, œuvre écrite, nouvelle
        "Q7889",                                           // jeu vidéo
        "Q43229", "Q4830453", "Q783794", "Q891723", "Q6881511", // organisation, entreprise, compagnie, société cotée, entreprise
    ]

    /// Types Wikidata d'entités **physiques** (rivière, lac, montagne…) : acceptables pour un `.loc`
    /// mais PAS pour un `.gpe` (lieu géopolitique). Écarte « SAN » (sigle) → rivière San.
    static let typesPhysiques: Set<String> = [
        "Q4022", "Q47521", "Q12284",                       // rivière, cours d'eau, canal
        "Q23397", "Q34038",                                // lac, chute d'eau
        "Q8502", "Q46831", "Q54050",                       // montagne, chaîne de montagnes, colline
        "Q165", "Q9430",                                   // mer, océan
        "Q23442", "Q35509", "Q40080",                      // île, grotte, plage
    ]

    /// Éléments Wikidata qui ne désignent **aucun contenu réel** : un nom de famille, un prénom,
    /// une page d'homonymie ou une page de service Wikimédia. Ils portent souvent le libellé nu
    /// (« Oppenheimer » = Q21431219, *nom de famille*) et arrivent donc en tête des résultats exacts
    /// — devant le film, la personne ou l'organisation qu'on cherchait vraiment.
    ///
    /// ⚠️ Écartés pour **TOUS les types**, pas seulement les personnes : jusqu'ici, une œuvre ou une
    /// organisation homonyme d'un patronyme se voyait rattacher le nom de famille (piège relevé par
    /// Patrick le 26/07 sur « Oppenheimer »). Écarter ces éléments ne fait jamais perdre un bon
    /// rattachement — aucun d'eux n'est un sujet d'actualité.
    static let typesSansContenu: Set<String> = [
        "Q101352",                                         // nom de famille
        "Q202444", "Q12308941", "Q11879590", "Q3409032",   // prénom (générique, masculin, féminin, unisexe)
        "Q4167410",                                        // page d'homonymie
        "Q13406463", "Q4167836", "Q11266439", "Q11753321", // liste, catégorie, modèle, page d'aide Wikimédia
    ]

    /// Les candidats dont le libellé correspond **exactement** au terme cherché, débarrassés de ceux
    /// qui ne désignent aucun contenu (nom de famille, prénom, page d'homonymie).
    ///
    /// Exact = le label OU le texte qui a matché (alias / label d'une autre langue). Sans le
    /// `matchText`, « London » ne trouvait pas Q84 (label fr « Londres ») et retombait sur London
    /// (Ontario) ; « US » ne trouvait pas Q30 et tombait sur la commune « Us ».
    static func exactsFiables(_ candidats: [WikidataCandidat], valeur: String) -> [WikidataCandidat] {
        let cible = KeywordMatcher.normalize(valeur)
        return candidats.filter {
            KeywordMatcher.normalize($0.label) == cible
                || KeywordMatcher.normalize($0.matchText ?? "") == cible
        }.filter { c in
            // Type INCONNU (`instanceOf` vide, l'appel étant best-effort) → on ne tranche pas, on garde.
            c.instanceOf.isEmpty || !c.instanceOf.allSatisfy(Self.typesSansContenu.contains)
        }
    }

    /// **« Ce n'est pas ce type-là »** — le verdict qu'on peut encore rendre quand le rattachement,
    /// lui, s'abstient.
    ///
    /// ⚠️ Raison d'être : le cas le plus visible se produit précisément là où `choisir` renonce.
    /// « Git » est typé `person` par le NER ; `choisir` voit que le seul candidat exact est un
    /// logiciel, en conclut que le rattachement serait faux et **n'écrit rien** — l'entité reste donc
    /// une personne, et se retrouve candidate à la fiche « personnalité du jour » de l'Apple TV.
    /// L'information « ce n'est pas une personne » était pourtant acquise ; elle était simplement
    /// jetée avec le candidat.
    ///
    /// Corrige le TYPE et **jamais** le QID : un rattachement douteux fusionnerait des entités sans
    /// rapport, alors qu'un type erroné se rectifie d'un geste (`fornews_retype_entity`). Exigences —
    /// tous les candidats exacts ont un P31 connu, et l'ensemble de leurs P31 désigne **une seule**
    /// famille de la table de certitudes.
    static func typeSansRattachement(_ candidats: [WikidataCandidat],
                                     valeur: String, type: TypeEntite) -> TypeEntite? {
        let exacts = exactsFiables(candidats, valeur: valeur)
        // ⚠️ **CHAQUE candidat doit se prononcer**, et tous dans le même sens. Vérifié sur l'API
        // le 01/08 : « Ebola » retourne la maladie, une RIVIÈRE du Congo et un groupe de musique.
        // Se contenter des candidats qu'on sait lire — en ignorant les autres — retypait la maladie
        // Ebola en lieu, à partir de la rivière. Un candidat dont on ne sait rien dire est un
        // candidat qui nous contredit peut-être.
        guard !exacts.isEmpty else { return nil }
        let familles = exacts.map { Set($0.instanceOf.compactMap { typeParP31[$0] }) }
        guard familles.allSatisfy({ $0.count == 1 }),
              let deduit = familles.first?.first, familles.allSatisfy({ $0.first == deduit }),
              doitCorriger(de: type, vers: deduit) else { return nil }
        return deduit
    }

    /// Retourne le candidat fiable, ou `nil` si aucun match exact de libellé ou type
    /// incohérent (personnes). En cas d'homonymes, on retient le **mieux classé** par Wikidata
    /// (les résultats arrivent par pertinence/notoriété décroissante).
    /// Classes P31 d'éléments Wikidata qui **ne désignent aucun sujet** : ils décrivent un NOM, ou
    /// listent des sujets, mais ne sont personne ni rien.
    ///
    /// ⚠️ Liste volontairement ÉTROITE, comme les autres refus de ce fichier. On n'écarte que ce
    /// dont on est sûr : mieux vaut laisser passer une fiche douteuse — `QualiteEntites` la
    /// signalera — que priver une entité légitime de son enrichissement.
    static let classesFicheSansSujet: Set<String> = [
        "Q101352",      // nom de famille
        "Q202444",      // prénom
        "Q12308941",    // prénom masculin
        "Q11879590",    // prénom féminin
        "Q3409032",     // prénom épicène
        "Q4167410",     // page d'homonymie Wikimedia
        "Q13406463",    // liste Wikimedia
        "Q4167836",     // catégorie Wikimedia
    ]

    /// Natures Wikidata (P31) d'êtres vivants, de gènes ou de molécules : un nom propre ne les désigne pas, sauf une
    /// maladie (un virus est un taxon).
    static let naturesScientifiques: Set<String> = [
        "Q16521",       // taxon
        "Q7187",        // gène
        "Q8054",        // protéine
        "Q11173",       // composé chimique
        "Q113145171",   // type d'entité chimique
        "Q3863",        // astéroïde
    ]

    /// Les types d'entité qui sont des NOMS PROPRES : une fiche de concept (une classe, sans nature) ne les désigne pas.
    static let typesNomsPropres: Set<TypeEntite> = [.org, .product, .person, .gpe, .loc, .work, .event]

    /// **La nature de la fiche est-elle impossible pour ce type d'entité ?** Rend le motif, ou `nil` (possible, ou on
    /// ne sait pas — un « je ne sais pas » ne retire jamais rien).
    /// - Parameters:
    ///   - p31: les natures de la fiche (« instance de ») ; vide = aucune, ou inconnue.
    ///   - p279: ses catégories parentes (« sous-classe de ») ; non vides SANS nature = la fiche est un CONCEPT
    ///     (« fenêtre », « fonction publique », « tiret »), pas une chose précise.
    ///   - noms: le nom LU dans l'article (la valeur d'origine quand Wikidata a renommé l'entité) ; `libelles` : les
    ///     libellés PRINCIPAUX de la fiche (`mul`, `fr`, `en`) ; `alias` : tous ses noms. Sans eux, les deux exceptions
    ///     ci-dessous ne jouent pas.
    ///
    /// ⭐ **Deux exceptions, quand la fiche porte EXACTEMENT le nom de l'entité** (Patrick, 05/10/2026 : « ok code », après
    /// relecture des 435 fiches retirées la première nuit, 90 % à raison) :
    /// - une MOLÉCULE nommée par son nom (cocaïne, fentanyl, dopamine, saccharine), ou une ESPÈCE nommée sans ambiguïté
    ///   — deux mots (« Pseudomonas aeruginosa »), un chiffre ou un trait d'union (« SARS-CoV-2 »), un virus
    ///   (« Adénovirus ») — n'est pas une fiche fausse. Un genre d'un seul mot (« Migros », « Temu », « Nasa ») l'est
    ///   presque toujours : il part. Un sigle (« CO », « PMR ») aussi ;
    /// - un CONCEPT dont le libellé est le nom propre de l'entité, majuscule comprise, est un modèle de produit que
    ///   Wikidata range en catégorie (« Siri Remote », « MacBook Air M4 », « FineWoven ») ; un vrai concept a un libellé
    ///   en minuscules (« fenêtre » pour Windows, « visa », « métal »).
    public static func natureImpossible(type: TypeEntite, p31: [String], p279: [String],
                                        noms: [String] = [], libelles: Set<String> = [], alias: Set<String> = []) -> String? {
        if p31.contains(where: classesFicheSansSujet.contains) { return "un prénom, un nom de famille ou une page d'homonymie" }
        if type != .maladie, p31.contains(where: naturesScientifiques.contains) {
            return moleculeOuEspeceNommee(p31: p31, noms: noms, libelles: libelles.union(alias))
                ? nil : "un être vivant, un gène ou une molécule"
        }
        if p31.isEmpty, !p279.isEmpty, typesNomsPropres.contains(type) {
            return produitNomme(noms: noms, libelles: libelles) ? nil : "un concept général"
        }
        return nil
    }

    static let classesMolecules: Set<String> = ["Q11173", "Q113145171"]   // composé chimique, type d'entité chimique
    static let classeTaxon = "Q16521"

    static func plier(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }

    static func moleculeOuEspeceNommee(p31: [String], noms: [String], libelles: Set<String>) -> Bool {
        let plies = Set(libelles.map(plier))
        for n in noms where plies.contains(plier(n)) {
            if n == n.uppercased(), n.count <= 5 { continue }                           // un sigle : « CO », « PMR »
            if p31.contains(where: classesMolecules.contains) { return true }
            if p31.contains(classeTaxon) {
                let p = plier(n)
                // Un nom latin (« Vespa velutina » : majuscule, puis minuscule) ; « Black Pepper », « Morning Glory »
                // sont des noms d'usage, ambigus.
                let mots = n.split(separator: " ")
                let binomial = mots.count == 2 && mots[0].first?.isUppercase == true && mots[1].first?.isLowercase == true
                if binomial || n.contains(where: \.isNumber) || n.contains("-")
                    || p.contains("virus") || p.hasSuffix("viridae") { return true }
            }
        }
        return false
    }

    static func produitNomme(noms: [String], libelles: Set<String>) -> Bool {
        noms.contains { $0.first?.isUppercase == true && libelles.contains($0) }
    }

    static func choisir(_ candidats: [WikidataCandidat], valeur: String, type: TypeEntite) -> WikidataCandidat? {
        // ⛔ **Écarter les fiches qui ne désignent AUCUN sujet** — avant toute autre règle.
        //
        // Un prénom, un patronyme ou une page d'homonymie sont des éléments Wikidata parfaitement
        // valides, souvent très bien classés sur une recherche par libellé : « Leo » ramène le
        // prénom, « Swiss » un nom de famille, « Banks » un patronyme. L'entité hérite alors d'une
        // description, d'une image et parfois de coordonnées qui appartiennent à autre chose — et
        // cette description part dans le contexte du modèle de langue.
        //
        // ⚠️ **Cette garde n'existait PAS.** `QualiteEntites` savait NOMMER le défaut depuis le
        // 26/07, mais seulement pour le SUGGÉRER à l'utilisateur après coup ; rien ne l'empêchait à
        // l'attachement. Mesuré le 15/08 sur le store réel : **275 entités sur 11 473** portent une
        // telle fiche, contre 261 sur 10 681 le 29/07 — soit un taux STABLE à ~2,4 %. Une note de
        // juillet disait « la prévention existe, il ne manque que le rejeu » : le taux constant
        // prouve le contraire. Rejouer sans poser cette garde aurait été vider un seau percé.
        //
        // On filtre par **P31**, pas par la description : c'est une donnée structurée, la même que
        // `typeDepuisP31` exploite déjà, et elle ne dépend d'aucune langue. Et on FILTRE plutôt
        // qu'on ne rejette : si un candidat mieux placé est un prénom mais qu'un autre désigne le
        // vrai sujet, on garde le second au lieu de tout abandonner.
        let candidats = candidats.filter { c in
            // Signal 1 — P31, quand Wikidata le fournit.
            if !c.instanceOf.isEmpty,
               c.instanceOf.contains(where: Self.classesFicheSansSujet.contains) { return false }
            // Signal 2 — la DESCRIPTION, quand P31 manque.
            //
            // ⚠️ Ajouté le 15/08 au soir, après le détachement groupé : Patrick a vu des fiches de
            // prénom REVENIR. La garde P31 seule ne pouvait rien — elle ne se déclenche que si
            // l'API renvoie les classes du candidat, et `wbsearchentities` ne les fournit pas
            // toujours. Un « je ne sais pas » était traité comme une permission.
            //
            // `QualiteEntites.motifFicheSansContenu` sait nommer ce défaut depuis le 26/07, mais
            // uniquement pour le SUGGÉRER après coup. C'est le motif de la journée, une cinquième
            // fois : une règle éprouvée, branchée à un seul consommateur.
            //
            // ⛔ La description d'un candidat de recherche est COURTE (« nom de famille », « prénom
            // masculin ») — la règle des 120 premiers caractères couvre donc la chaîne entière, ce
            // qui est exactement ce qu'on veut ici : aucune biographie longue ne peut la déclencher
            // par accident.
            if let d = c.description, QualiteEntites.motifFicheSansContenu(d) != nil { return false }
            return true
        }
        let exacts = Self.exactsFiables(candidats, valeur: valeur)
        guard !exacts.isEmpty else { return nil }

        if type == .person {
            // Q5 = être humain : signal de type fiable.
            let humains = exacts.filter { $0.instanceOf.contains("Q5") }
            if !humains.isEmpty {
                return humains.first   // mieux classé parmi les humains homonymes
            }
            // Si des candidats exacts ont un type connu mais qu'aucun n'est humain → mismatch.
            if exacts.contains(where: { !$0.instanceOf.isEmpty }) {
                return nil
            }
            // Type inconnu (instanceOf non récupéré) → on fait confiance au classement.
        }

        // Lieux/pays : le classement Wikidata place parfois un homonyme MINEUR avant l'entité
        // attendue (ex. « Suisse » → la commune Q22036 arrive AVANT le pays Q39). On privilégie donc
        // les types les plus englobants (pays > État > région > ville), puis, à égalité ou si le type
        // n'a pu être récupéré, le QID le plus ancien (= en général le plus notable : Q39 < Q22036).
        if type == .gpe || type == .loc {
            // Garde de cohérence de TYPE (anti faux-positifs) : un libellé peut matcher exactement une
            // entité qui n'est PAS un lieu (« Caroline » → chanson Q16034901) ou un lieu *physique*
            // alors qu'on attend un lieu *géopolitique* (« SAN », sigle d'organisation → rivière San
            // Q216488). On écarte un candidat seulement quand son type P31 est CONNU et **entièrement**
            // disqualifiant — liste de refus volontairement étroite (œuvres, personnes, organisations ;
            // + entités physiques pour `gpe`). Approche par refus et non par autorisation : un vrai
            // lieu au sous-type Wikidata inhabituel (petite commune, région nationale…) n'est jamais
            // écarté, donc pas de perte d'enrichissement. Type inconnu (instanceOf vide) → on ne tranche pas.
            func disqualifie(_ c: WikidataCandidat) -> Bool {
                guard !c.instanceOf.isEmpty else { return false }
                let interdits = (type == .gpe) ? Self.typesNonLieu.union(Self.typesPhysiques) : Self.typesNonLieu
                return c.instanceOf.allSatisfy(interdits.contains)
            }
            let acceptables = exacts.filter { !disqualifie($0) }
            guard !acceptables.isEmpty else { return nil }   // tous disqualifiés → abstention

            // Classement Wikidata : un homonyme MINEUR arrive parfois avant l'entité attendue
            // (« Suisse » → la commune Q22036 AVANT le pays Q39). On privilégie les types les plus
            // englobants (pays / État souverain / État / État fédéré US), puis le QID le plus ancien
            // (= en général le plus notable : Q39 < Q22036). PAS les types de ville ici : entre deux
            // villes homonymes (London UK vs London Ontario), le départage fiable reste le QID ancien.
            let prioritePlace = ["Q6256", "Q3624078", "Q7275", "Q35657"]
            func rang(_ c: WikidataCandidat) -> Int {
                prioritePlace.firstIndex(where: c.instanceOf.contains) ?? prioritePlace.count
            }
            func numero(_ c: WikidataCandidat) -> Int { Int(c.id.dropFirst()) ?? .max }
            let gagnant = acceptables.min {
                let (r0, r1) = (rang($0), rang($1))
                return r0 != r1 ? r0 < r1 : numero($0) < numero($1)
            }
            // Anti-collision d'ALIAS AMBIGU. Un acronyme court (« RDC ») est souvent un alias PARTAGÉ
            // par des entités sans rapport : « RDC » désigne sur Wikidata la RD Congo (Q974) MAIS AUSSI
            // Taïwan (Q865, alias « RDC » = Republic of China), un parti centrafricain, une radio…
            // Quand plusieurs candidats matchent et que le type P31 du gagnant n'a PAS pu être récupéré
            // (l'appel `instanceOf` est best-effort → `[:]` en cas de timeout/erreur, cf. rechercher),
            // tous tombent au même rang et le départage retombe sur « QID le plus petit ». Ce n'est un
            // désambiguïsateur valable qu'entre HOMONYMES DE MÊME TYPE (deux villes, pays vs commune) —
            // PAS entre entités sans rapport partageant un alias : il attrapait Taïwan (865 < 974) et,
            // par fusion de QID, collait Taïwan à tout article sur la RDC. Sans type pour confirmer, on
            // s'abstient (linking conservateur, §10.4). Un candidat unique reste accepté (rien à départager).
            if let g = gagnant, g.instanceOf.isEmpty, acceptables.count >= 2 { return nil }
            return gagnant
        }

        return exacts.first   // mieux classé
    }

    // MARK: Fusion de doublons (clé QID)

}
