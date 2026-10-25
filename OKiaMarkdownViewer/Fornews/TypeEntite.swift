// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/Enums.swift (commit 58fb14e9, 25/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : `TypeEntite` seul (le reste du fichier tient au modèle SwiftData).
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation


/// Type d'entité nommée (aligné sur les schémas NER / Wikidata).
public enum TypeEntite: String, Codable, Sendable, CaseIterable {
    case person, org, gpe, loc, product, event, date, money, work, maladie, autre

    // ⚠️ `maladie` ajouté le 27/07/2026 (demande de Patrick). Aucun impact de SCHÉMA : le type est
    // stocké dans `EntiteNER.typeRaw`, une simple chaîne. En revanche, un appareil resté sur un
    // build antérieur ne connaît pas cette valeur et affichera ces entités en « Autres »
    // (`TypeEntite(rawValue:) ?? .autre`) — sans rien casser, et le libellé se corrige de lui-même
    // dès la mise à jour.

    /// Priorité de type pour la déduplication cross-type : valeur élevée = plus spécifique.
    /// Quand deux entités portent le même nom normalisé mais des types différents
    /// (ex. `org:apple` vs `autre:apple`), le type le plus spécifique l'emporte.
    public var priorite: Int {
        switch self {
        case .person:  return 9
        // Aussi spécifique qu'une organisation : « Ebola » ou « grippe aviaire » désigne une chose
        // précise, et doit l'emporter sur un `autre` du même nom.
        case .maladie: return 8
        case .org:     return 8
        case .gpe:     return 7
        case .loc:     return 6
        case .product: return 5
        case .event:   return 4
        case .work:    return 3
        case .date:    return 2
        case .money:   return 1
        case .autre:   return 0
        }
    }

    /// Ordre d'**affichage** des entités dans un article (≠ `priorite`, qui sert à la dédup) :
    /// person → loc → gpe → org → product → event, puis les types secondaires.
    public var rangAffichage: Int {
        switch self {
        case .person:  return 0
        case .loc:     return 1
        case .gpe:     return 2
        case .org:     return 3
        case .product: return 4
        case .event:   return 5
        case .work:    return 6
        case .maladie: return 7
        case .date:    return 8
        case .money:   return 9
        case .autre:   return 10
        }
    }
}
