import Foundation

/// Option Analytic (1.4) — les corrections de l'utilisateur. Demandé par Patrick le 25/10/2026 :
/// « on doit pouvoir signaler une erreur et en tenir compte dans les traitements suivants ».
///
/// Une correction porte sur un NOM (plié, comme l'identifiant d'une entité) et vaut pour tous les
/// documents. Elle fait autorité sur tout le reste — détection, genre, choix Wikidata, fusion,
/// sources —, comme `CorrectionEntite` dans fornews : c'est l'utilisateur qui sait.
struct CorrectionEntite: Codable, Equatable {
    /// « Ce n'est pas une entité » : le nom n'est plus jamais retenu.
    var ignorer = false
    /// Le genre imposé.
    var type: TypeEntite?
    /// « C'est une source » (vrai) ou « ce n'en est pas une » (faux).
    var source: Bool?
    /// La fiche Wikidata choisie par l'utilisateur, complète (description, photo, position) : elle
    /// ne dépend plus du cache, qui vieillit.
    var fiche: ResolutionEntite?
    /// Les fiches qu'il a écartées (« ce n'est pas la bonne fiche »).
    var qidsRefuses: [String] = []
    /// « Aucune fiche ne convient ».
    var sansFiche = false
    /// « Mauvaise photo » : la fiche est la bonne, sa photo ne l'est pas (un homonyme sur Commons).
    var sansImage = false
    /// « C'est la même que… » : le nom de l'entité qui la reprend.
    var memeQue: String?

    var vide: Bool { self == CorrectionEntite() }
}

@MainActor
final class CorrectionsEntites {
    static let partage = CorrectionsEntites()

    private var corrections: [String: CorrectionEntite] = [:]
    private let fichier: URL

    init(fichier: URL? = nil) {
        let dossier = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        self.fichier = fichier ?? dossier.appendingPathComponent("Analytic/corrections.json")
        if let data = try? Data(contentsOf: self.fichier),
           let lues = try? JSONDecoder().decode([String: CorrectionEntite].self, from: data) {
            corrections = lues
        }
    }

    func correction(_ nom: String) -> CorrectionEntite? { corrections[EntiteDocument.cle(nom)] }

    /// Modifie la correction d'un nom et l'enregistre aussitôt.
    func modifier(_ nom: String, _ changement: (inout CorrectionEntite) -> Void) {
        let cle = EntiteDocument.cle(nom)
        var c = corrections[cle] ?? CorrectionEntite()
        changement(&c)
        corrections[cle] = c.vide ? nil : c
        ecrire()
    }

    func oublier(_ nom: String) {
        corrections[EntiteDocument.cle(nom)] = nil
        ecrire()
    }

    var nombre: Int { corrections.count }

    func toutOublier() {
        corrections = [:]
        ecrire()
    }

    /// Les corrections appliquées à une liste d'entités : les noms ignorés retirés, les genres et
    /// les sources imposés, les noms réunis. Le choix de la fiche se fait à la résolution.
    func appliquer(_ entites: [EntiteDocument]) -> [EntiteDocument] {
        var liste: [EntiteDocument] = []
        var reprises: [(EntiteDocument, String)] = []
        for var e in entites {
            guard let c = corrections[e.id] else { liste.append(e); continue }
            if c.ignorer { continue }
            if let t = c.type { e.type = t }
            if let s = c.source { e.source = s }
            if c.sansFiche { e.qid = nil; e.description = nil; e.image = nil }
            if let cible = c.memeQue { reprises.append((e, EntiteDocument.cle(cible))); continue }
            liste.append(e)
        }
        // « C'est la même que » : les mentions rejoignent l'entité choisie, si le document la nomme ;
        // sinon, l'entité prend son nom.
        for (e, cible) in reprises {
            if let i = liste.firstIndex(where: { $0.id == cible }) {
                liste[i].mentions += e.mentions
            } else if let nom = corrections[e.id]?.memeQue {
                var renommee = e
                renommee.nom = nom
                liste.append(renommee)
            }
        }
        return liste
    }

    private func ecrire() {
        try? FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(corrections) { try? data.write(to: fichier, options: .atomic) }
    }
}
