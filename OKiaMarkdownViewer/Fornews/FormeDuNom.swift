// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/FormeDuNom.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **La FORME d'un nom, indépendamment de ce qu'il désigne.**
///
/// Ces règles vivent dans `FornewsModels` parce que **deux modules en ont besoin** : le filtre NER
/// (`FornewsAI`), qui refuse le span à la détection, et la fusion d'alias (`FornewsServices`), qui
/// refuse d'absorber une entité dans une phrase. `FornewsServices` ne dépend pas de `FornewsAI` :
/// laisser la règle dans l'un des deux aurait imposé de la dupliquer, donc de la laisser diverger.
public enum FormeDuNom {

    /// **Une phrase qui OPPOSE deux noms propres n'est pas une entité** (signalement de Patrick, 21/08).
    ///
    /// Capture d'écran : une fiche intitulée **« Etats-Unis contre l'Iran »**, typée *entité
    /// géopolitique*, portant **Q30** — le QID des États-Unis — avec leur description complète et
    /// leur carte. Le lecteur voit donc une fiche d'apparence officielle pour quelque chose qui
    /// n'existe pas.
    ///
    /// Même famille retrouvée dans le corpus : **« Suisse contre la Colombie »** typée `gpe` et
    /// portant **Q739 (Colombie)**, description du pays incluse.
    ///
    /// Le défaut est double — un span de NER trop long, puis un QID qui décore la phrase de
    /// l'identité de **l'un** de ses membres. C'est le second qui rend la fiche crédible : sans lui,
    /// on aurait un libellé bizarre ; avec lui, on a une contre-vérité documentée.
    ///
    /// ## Ce qui déclenche, et ce qui ne déclenche pas
    ///
    /// Il faut **un connecteur d'opposition** ET **un mot capitalisé de chaque côté**. Les deux
    /// conditions ensemble, jamais l'une seule :
    ///
    /// - ⛔ « **Fondation** pour le **cheval** » — nom d'organisation parfaitement réel, mesuré dans
    ///   le corpus. « pour » n'est pas un connecteur d'opposition, et « cheval » n'est pas capitalisé.
    /// - ⛔ « Trinité-**et**-Tobago », « Saint-Pierre-**et**-Miquelon » — noms de pays. Le connecteur
    ///   y est collé par des traits d'union, jamais entouré d'espaces.
    ///
    /// ⚠️ **« et » et « ou » sont volontairement EXCLUS de la liste.** « Der Spiegel et Le Monde »
    /// (mesuré, typé `org`, portant Q131478) échappe donc à cette règle — mais les inclure mettrait
    /// en danger tous les noms composés légitimes. Entre garder une mauvaise entité et détruire un
    /// nom réel, on garde : le premier se corrige d'un geste, le second est une perte.
    public static func estOppositionDeDeuxNomsPropres(_ valeur: String) -> Bool {
        let mots = valeur.split(separator: " ").map(String.init)
        guard mots.count >= 3 else { return false }
        // Articles et déterminants : ils encadrent le nom propre sans être lui.
        let determinants: Set<String> = ["le", "la", "les", "l'", "l’", "the", "der", "die", "das",
                                         "el", "los", "las", "il", "lo", "un", "une", "des", "du"]
        // ⚠️ **Le déterminant élidé est COLLÉ au nom** : « l'Iran », « d'Allemagne », « l’Ukraine ».
        // Tester la première lettre du mot renverrait donc « minuscule » sur un nom propre évident —
        // c'est ce qui laissait passer « Etats-Unis contre l'Iran », le cas même de la capture.
        // Les trois apostrophes du corpus sont traitées (droite, courbe, lettre-apostrophe).
        func estNomPropre(_ m: String) -> Bool {
            var mot = m
            for sep in ["'", "\u{2019}", "\u{02BC}"] {
                if let r = mot.range(of: sep), mot.distance(from: mot.startIndex, to: r.lowerBound) <= 2 {
                    mot = String(mot[r.upperBound...])
                    break
                }
            }
            guard let p = mot.first else { return false }
            return p.isUppercase && !determinants.contains(mot.lowercased())
        }
        for (i, mot) in mots.enumerated() {
            let m = mot.lowercased()
            // « face à » se lit sur deux mots : on teste le couple.
            let couple = i + 1 < mots.count ? "\(m) \(mots[i + 1].lowercased())" : ""
            guard connecteursOpposition.contains(m) || connecteursOpposition.contains(couple)
            else { continue }
            let saut = connecteursOpposition.contains(couple) ? 2 : 1
            let avant = mots[..<i]
            let apres = mots[(i + saut)...]
            if avant.contains(where: estNomPropre), apres.contains(where: estNomPropre) { return true }
        }
        return false
    }

    /// ⚠️ **Opposition seulement.** Pas « et », pas « ou », pas « pour », pas « de » : ceux-là
    /// composent des noms réels. Ceux-ci décrivent un affrontement, jamais une entité.
    private static let connecteursOpposition: Set<String> = [
        "contre", "vs", "vs.", "versus", "face à", "face a", "against", "gegen", "contra",
    ]

}
