// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/SyntagmePositionnel.swift (commit 58fb14e9, 25/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Détecte un **syntagme positionnel** capturé à tort comme lieu — « nord des Alpes »,
/// « sud-ouest de la Crimée », « centre du Var », « Washington au nord-ouest des Etats-Unis ».
///
/// ## Ce que c'est, et pourquoi ça compte
///
/// Ce ne sont pas des entités : ce sont des **morceaux de phrase**. Le NER les capture parce qu'ils
/// ressemblent à un nom de lieu — ils en contiennent un — et le rattachement Wikidata leur colle
/// ensuite le QID du lieu enchâssé. Relevé le 03/08 sur le corpus du mini :
///
/// ```
/// « nord des Alpes »                          → Q47497915 (« article dans l'encyclopédie Otto »)
/// « sud-ouest de la Crimée »                  → Q7835  (Crimée)
/// « Washington au nord-ouest des Etats-Unis » → Q30    (États-Unis)
/// « centre du Var »                           → Q12789 (département du Var)
/// ```
///
/// ⚠️ **Le défaut est VIVANT**, pas une séquelle : ces entités portent des articles de juillet 2026
/// (canicule, guerre en Ukraine). Le pipeline en fabrique encore.
///
/// ## La règle, et ce qu'elle ÉPARGNE
///
/// Un point cardinal **immédiatement suivi d'une préposition** — « nord des », « sud-ouest de la »,
/// « centre du ». C'est cette adjacence qui fait la différence :
///
/// | nom | rejeté ? | pourquoi |
/// |---|---|---|
/// | `nord des Alpes` | ⛔ | « nord » + « des » |
/// | `Nord-Pas-de-Calais` | ✅ gardé | après « nord » vient « pas », pas une préposition |
/// | `Sud-Kivu` | ✅ gardé | idem |
/// | `Rhénanie-du-Nord-Westphalie` | ✅ gardé | idem |
///
/// ⚠️ **Mesuré sur les 1 706 noms de lieux du corpus réel** : la règle en rejette **6**, exactement
/// les six syntagmes, et **aucun autre**. Zéro faux positif — pas une estimation, un décompte.
///
/// ⛔ Réservé aux types `loc`/`gpe`. Une organisation peut légitimement s'appeler « Ministère de
/// l'Économie et des Finances » ; le fragment de conjonction ci-dessous n'a de sens que pour un lieu.
///
/// Pur (String → Bool), donc partageable par `FornewsAI` (filtre NER) et `FornewsServices`
/// (nettoyage rétroactif) sans dépendance croisée — même patron que [[LibellePromotionnel]].
public enum SyntagmePositionnel {

    /// Points cardinaux et « centre », sous leurs formes normalisées.
    private static let directions = "(nord|sud|est|ouest|nord-est|nord-ouest|sud-est|sud-ouest|centre)"
    /// Prépositions qui, juste après une direction, trahissent un syntagme et non un nom propre.
    private static let prepositions = "(de|du|des|de la|de l'|d')"

    /// Direction + préposition + quelque chose : « nord des Alpes », « au sud-ouest de la Crimée ».
    private static let positionnel = try! NSRegularExpression(
        pattern: "\\b\(directions)\\s+\(prepositions)\\s+\\S")

    /// ⚠️ Fragment de proposition : « Sénat et de la Chambre ». Un vrai toponyme composé s'écrit
    /// avec des traits d'union (« Trinité-et-Tobago », « Saint-Pierre-et-Miquelon ») — jamais avec
    /// « et de la » entouré d'espaces.
    private static let conjonction = try! NSRegularExpression(pattern: "\\set\\s+(de la|du|des|de)\\s")

    /// La valeur est-elle un syntagme positionnel plutôt qu'un nom de lieu ?
    public static func detecte(_ valeur: String) -> Bool {
        let n = valeur
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let plage = NSRange(n.startIndex..., in: n)
        return positionnel.firstMatch(in: n, range: plage) != nil
            || conjonction.firstMatch(in: n, range: plage) != nil
    }
}
