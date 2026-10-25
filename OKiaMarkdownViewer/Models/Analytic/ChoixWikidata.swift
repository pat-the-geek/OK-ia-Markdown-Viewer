import Foundation

/// Option Analytic (1.4) — le choix d'une fiche Wikidata quand on n'a QUE le nom.
///
/// fornews choisit avec le contexte de ses articles ; md Viewer, lui, n'envoie que le nom. Le choix
/// de fornews (`WikimediaService.choisir`) retenait alors trop souvent un homonyme obscur : « NASA »
/// → un genre de plantes, écarté, puis la filiale ferroviaire du Land de Saxe-Anhalt ; « Elysée »
/// → une salle des fêtes d'Ostende ; « Washington » → l'État (Patrick, B89, 25/10/2026).
///
/// Ce qui marche sans contexte : parmi les fiches dont le nom correspond exactement et dont la
/// nature est possible, la plus ANCIENNE — le plus petit numéro Q. Les fiches créées tôt sont les
/// sujets connus : Q23548 (NASA), Q188190 (palais de l'Élysée), Q61 (Washington, D.C.), Q37230
/// (CIA). Les règles de fornews restent : correspondance exacte (`exactsFiables`), fiches sans sujet
/// écartées, nature impossible écartée.
enum ChoixWikidata {

    /// Les candidats possibles, du plus ancien au plus récent. `natures` donne les classes (P31)
    /// d'un candidat qui n'en a pas dans la réponse de recherche.
    static func candidats(_ candidats: [WikidataCandidat], nom: String, type: TypeEntite,
                          typeFiable: Bool) -> [WikidataCandidat] {
        WikimediaService.exactsFiables(candidats, valeur: nom)
            .filter { c in
                WikimediaService.natureImpossible(type: type, p31: c.instanceOf, p279: [],
                                                  noms: [nom], libelles: [c.label], alias: [c.label]) == nil
            }
            .filter { c in tientLeGenre(c, type: type, typeFiable: typeFiable) }
            .sorted { numero($0) < numero($1) }
    }

    /// Le genre de l'entité tient-il ? Sans contexte, c'est la seule garde contre l'homonyme :
    /// - une personne doit être un être humain (P31 = Q5) ;
    /// - un lieu doit être un lieu pour la table de fornews (`typeDepuisP31` → gpe ou loc) —
    ///   « Ryad » tombait sur un établissement scolaire marocain (Patrick, B89) ;
    /// - un genre donné par le document (rapport fornews) n'est pas contredit.
    /// Un candidat sans classes connues (`instanceOf` vide) n'est pas jugé. Le genre « autre »
    /// (repli par majuscules) n'impose rien : Wikidata le donnera.
    static func tientLeGenre(_ c: WikidataCandidat, type: TypeEntite, typeFiable: Bool) -> Bool {
        guard !c.instanceOf.isEmpty else { return true }
        let deduit = WikimediaService.typeDepuisP31(c.instanceOf)
        switch type {
        case .person:
            return c.instanceOf.contains("Q5")
        case .gpe, .loc:
            // Au moins une classe de lieu connue : une ville a souvent plusieurs classes (commune,
            // capitale, grande ville…) et `typeDepuisP31`, qui exige l'unanimité, s'abstenait —
            // Paris tombait alors sur Paris (Texas). Sans aucune classe de lieu connue, on
            // s'abstient : mieux vaut pas de fiche qu'une école marocaine pour « Ryad ».
            return c.instanceOf.contains { [.gpe, .loc].contains(WikimediaService.typeParP31[$0]) }
        default:
            guard typeFiable, let t = deduit else { return true }
            return compatibles(type, t)
        }
    }

    static func numero(_ c: WikidataCandidat) -> Int { Int(c.id.dropFirst()) ?? .max }

    /// Deux types qui ne se contredisent pas : le même, deux lieux (fornews ne départage pas une
    /// ville d'une région, cf. `doitCorriger`), ou une organisation et un produit — une enseigne est
    /// l'un et l'autre, et Wikidata rangeait Leroy Merlin en marque.
    static func compatibles(_ a: TypeEntite, _ b: TypeEntite) -> Bool {
        let familles: [Set<TypeEntite>] = [[.loc, .gpe], [.org, .product]]
        return a == b || familles.contains { $0.contains(a) && $0.contains(b) }
    }
}
