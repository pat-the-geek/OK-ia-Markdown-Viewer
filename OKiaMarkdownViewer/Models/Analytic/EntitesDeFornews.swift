import Foundation

/// Option Analytic (1.4) — les entités que fornews a déjà résolues par Wikidata, publiées dans le
/// groupe `group.ai.fornews.native` (`Entites/cache.json`, fornews 1.7.4, `CacheEntitesFornews`).
/// Ce que fornews sait, md Viewer ne le redemande pas à Wikidata : rien ne part sur le réseau.
///
/// ⚠️ Le `nom` d'une entrée est la forme que fornews a lue dans ses articles, pas le libellé
/// Wikidata — une quinzaine sont fautifs (« Suisse après Berne » pour Q39). L'identité, c'est le
/// QID : on n'en tire jamais de libellé, et un nom que `FiltreEntitesNER.estNommable` refuse
/// n'entre pas dans l'index.
@MainActor
final class EntitesDeFornews {
    static let partage = EntitesDeFornews()

    /// Les entrées par type et nom plié, puis par nom seul (`""` à la place du type). Un nom qui
    /// désigne deux QID différents est ambigu : il vaut `nil`, et on ne s'en sert pas.
    private var index: [String: CacheEntitesFornews.Entree?] = [:]
    private var dateLue: Date?
    private var enLecture = false

    var nombre: Int { index.count }

    /// Relit le cache quand fornews l'a réécrit (au plus une fois l'heure) : au lancement et au
    /// retour au premier plan. ~1 s et 10 Mo pour 30 000 entrées : hors du fil principal, et
    /// seulement avec l'option, seule à s'en servir.
    func actualiser() async {
        guard await AchatAnalytic.partage.accesSur() else { return }
        guard !enLecture, let url = CacheEntitesFornews.url else { return }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let date, date != dateLue else { return }
        enLecture = true
        Task.detached(priority: .utility) {
            let index = CacheEntitesFornews.lire().map(Self.indexer)
            await MainActor.run {
                let partage = EntitesDeFornews.partage
                partage.enLecture = false
                guard let index else { return }
                partage.index = index
                partage.dateLue = date
            }
        }
    }

    nonisolated static func indexer(_ entrees: [CacheEntitesFornews.Entree]) -> [String: CacheEntitesFornews.Entree?] {
        var index: [String: CacheEntitesFornews.Entree?] = [:]
        func ajouter(_ cle: String, _ e: CacheEntitesFornews.Entree) {
            if let deja = index[cle] {
                if deja?.qid != e.qid { index[cle] = .some(nil) }   // deux fiches pour un nom
            } else {
                index[cle] = e
            }
        }
        for e in entrees {
            guard let type = TypeEntite(rawValue: e.type) else { continue }
            for nom in [e.nom] + e.alias where FiltreEntitesNER.estNommable(nom, type: type) {
                let n = EntiteDocument.cle(nom)
                guard n.count > 2 else { continue }   // comme pour Wikidata : trop ambigu
                ajouter("\(type.rawValue)|\(n)", e)
                ajouter("|\(n)", e)
            }
        }
        return index
    }

    /// La fiche que fornews connaît pour ce nom : d'abord sous le même type, sinon sous le nom seul.
    /// Dans une autre langue que celle du document, sa description ne sert pas.
    func resolution(_ nom: String, type: TypeEntite, langue: String) -> ResolutionEntite? {
        let n = EntiteDocument.cle(nom)
        guard let trouvee = index["\(type.rawValue)|\(n)"] ?? index["|\(n)"], let e = trouvee else { return nil }
        let memeLangue = e.langue.split(separator: "-").first?.lowercased()
            == langue.split(separator: "-").first?.lowercased()
        return ResolutionEntite(qid: e.qid, libelle: nil, description: memeLangue ? e.description : nil,
                                image: e.image, latitude: e.latitude, longitude: e.longitude,
                                type: TypeEntite(rawValue: e.type), date: Date())
    }
}
