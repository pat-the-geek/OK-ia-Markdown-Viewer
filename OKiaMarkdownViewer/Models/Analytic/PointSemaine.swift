import Foundation

/// Option Analytic (1.7) — le point de la semaine (Patrick, 13/11/2026 : « What came into the vault
/// since your last visit: new documents, entities that appear or come back more often, and a
/// summary computed on the device »).
///
/// Tout se calcule sur l'index de l'analyse du coffre (`AnalyseCoffre`), sur l'appareil : les
/// documents arrivés depuis une date (leur date de modification), les entités qui n'étaient dans
/// aucun document avant, et celles qui reviennent plus souvent que sur la période précédente de
/// même durée. Le résumé, rédigé par le modèle de l'appareil quand Apple Intelligence est là, ne
/// voit que les titres et les noms ; sans lui, une phrase composée ici.
struct PointSemaine {
    struct Document: Identifiable {
        let id: String
        let nom: String
        let arrivee: Date
    }
    struct Hausse: Identifiable {
        let entite: AnalyseCoffre.EntiteCoffre
        let maintenant: Int
        let avant: Int
        var id: String { entite.id }
    }

    let depuis: Date
    let documents: [Document]
    let nouvelles: [AnalyseCoffre.EntiteCoffre]
    let hausses: [Hausse]

    var vide: Bool { documents.isEmpty }

    /// La dernière visite, retenue d'une ouverture à l'autre.
    static let cleVisite = "okia.semaine.derniereVisite"

    static var derniereVisite: Date? { UserDefaults.standard.object(forKey: cleVisite) as? Date }
    static func noterVisite() { UserDefaults.standard.set(Date(), forKey: cleVisite) }

    /// La phrase composée ici, sans modèle : combien de documents, et les noms qui ressortent.
    var phrase: String {
        guard !vide else { return tr("Rien de nouveau dans le coffre depuis le %@.", depuis.dateCourte) }
        let noms = (nouvelles.map(\.entite.nom) + hausses.map(\.entite.entite.nom)).prefix(4)
        let debut = documents.count == 1
            ? tr("Un document est entré dans le coffre depuis le %@.", depuis.dateCourte)
            : tr("%d documents sont entrés dans le coffre depuis le %@.", documents.count, depuis.dateCourte)
        guard !noms.isEmpty else { return debut }
        return debut + " " + tr("Ils parlent surtout de %@.", ListFormatter.localizedString(byJoining: Array(noms)))
    }

    /// Ce que le modèle de l'appareil reçoit : les titres, les dates, les noms — rien d'autre.
    var matiere: String {
        var lignes = documents.prefix(30).map { "- " + $0.nom + " (" + $0.arrivee.dateCourte + ")" }
        if !nouvelles.isEmpty {
            lignes.append(tr("Nouveaux noms :") + " " + nouvelles.prefix(12).map(\.entite.nom).joined(separator: ", "))
        }
        if !hausses.isEmpty {
            lignes.append(tr("Plus souvent qu’avant :") + " " + hausses.prefix(12).map(\.entite.entite.nom).joined(separator: ", "))
        }
        return lignes.joined(separator: "\n")
    }
}

extension AnalyseCoffre {
    /// Le point de ce qui est entré dans le coffre depuis `depuis`.
    func pointDeLaSemaine(depuis: Date, maintenant: Date = Date()) -> PointSemaine {
        let duree = max(maintenant.timeIntervalSince(depuis), 86_400)
        let avantDebut = depuis.addingTimeInterval(-duree)
        let docs = documentsIndexes()
        let recents = Set(docs.filter { $0.modifie >= depuis }.map(\.id))
        let precedents = Set(docs.filter { $0.modifie >= avantDebut && $0.modifie < depuis }.map(\.id))
        let documents = docs.filter { recents.contains($0.id) }
            .sorted { $0.modifie > $1.modifie }
            .map { PointSemaine.Document(id: $0.id, nom: $0.nom, arrivee: $0.modifie) }
        var nouvelles: [EntiteCoffre] = [], hausses: [PointSemaine.Hausse] = []
        for e in entites {
            let ids = Set(e.presences.map(\.document))
            let n = ids.intersection(recents).count
            guard n > 0 else { continue }
            if ids.isSubset(of: recents) {
                nouvelles.append(e)
            } else {
                let a = ids.intersection(precedents).count
                if n > a { hausses.append(.init(entite: e, maintenant: n, avant: a)) }
            }
        }
        nouvelles.sort { ($0.presences.count, $0.mentions) > ($1.presences.count, $1.mentions) }
        hausses.sort { ($0.maintenant - $0.avant, $0.maintenant) > ($1.maintenant - $1.avant, $1.maintenant) }
        return PointSemaine(depuis: depuis, documents: documents,
                            nouvelles: Array(nouvelles.prefix(24)), hausses: Array(hausses.prefix(24)))
    }
}
