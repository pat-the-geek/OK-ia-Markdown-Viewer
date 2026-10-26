// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/LibelleTronque.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Un nom commun générique employé SEUL n'est jamais une entité** — c'est la troncature d'un
/// syntagme que le NER n'a pas su étendre.
///
/// Rapport de terrain de Patrick (§3, collection « Etna ») : l'entité `Institut`, typée `org` et
/// rattachée à une fiche Wikidata, était en réalité « Institut national de géophysique et de
/// volcanologie ». L'organisation la plus citée du dossier apparaissait sous une forme
/// méconnaissable, et son rapprochement avec `INGV` devenait impossible.
///
/// ⚠️ Mesuré le 15/08 sur le store iPhone : `Conseil` (Q24805210), `Agence` (Q1880737), `Banque`
/// (Q22687), `Service` (Q7406919), `Cour` (Q17383262). Cinq entités — peu nombreuses, mais chacune
/// **porte un QID**, donc paraît parfaitement enrichie. Une troncature crédible est plus nuisible
/// qu'une absence : elle entre dans l'analyse sans se signaler.
///
/// ## Ce que ce filtre n'est pas
///
/// ⛔ Il ne juge PAS de la longueur ni de la casse. « Suisse », « Total », « Orange » sont des mots
/// communs et de vraies entités. Seule compte l'appartenance à une liste **fermée** de têtes de
/// syntagme administratif — des mots qui, employés seuls et sans complément, ne désignent rien.
///
/// ⚠️ Et il ne s'applique qu'aux types `org`, `loc` et `gpe`. « Centre » peut être un patronyme ;
/// une personne nommée « Bureau » existe. On ne se mêle pas de ce qu'on ne mesure pas.
///
/// Pur (String → Bool), comme [[LibellePromotionnel]] : partageable par le filtre NER, la purge et
/// l'enrichissement sans dépendance croisée.
public enum LibelleTronque {

    /// Têtes de syntagme administratif ou institutionnel. **Normalisées** (minuscules, sans
    /// accents), comparées à l'ÉGALITÉ — jamais par inclusion : « Conseil fédéral » est une entité
    /// parfaitement valide, seul « Conseil » tout court ne l'est pas.
    static let tetesDeSyntagme: Set<String> = [
        // français
        "institut", "universite", "ministere", "agence", "federation", "conseil", "commission",
        "departement", "office", "service", "direction", "bureau", "centre", "association",
        "comite", "societe", "institution", "autorite", "parlement", "gouvernement", "tribunal",
        "cour", "banque", "hopital", "fondation", "syndicat", "observatoire", "laboratoire",
        "academie", "ecole", "college", "lycee", "administration", "secretariat", "assemblee",
        // anglais
        "institute", "university", "ministry", "agency", "federation", "council", "committee",
        "department", "office", "service", "board", "association", "foundation", "authority",
        "parliament", "government", "court", "bank", "hospital", "school", "college",
        "observatory", "laboratory", "academy", "secretariat", "assembly",
    ]

    /// Vrai si `valeur` est une tête de syntagme employée seule, pour un type où c'est aberrant.
    ///
    /// - Parameter typeRaw: `org`, `loc` ou `gpe` — ailleurs, on s'abstient (cf. la doc du type).
    public static func detecte(_ valeur: String, typeRaw: String) -> Bool {
        guard ["org", "loc", "gpe"].contains(typeRaw) else { return false }
        let n = valeur
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Un seul mot : dès qu'il y a un complément, le syntagme est complet et l'entité valide.
        guard !n.contains(" "), !n.contains("-") else { return false }
        return tetesDeSyntagme.contains(n)
    }
}
