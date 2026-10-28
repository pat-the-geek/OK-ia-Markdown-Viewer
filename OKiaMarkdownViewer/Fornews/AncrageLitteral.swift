// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/AncrageLitteral.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Une valeur chiffrée doit se retrouver MOT POUR MOT dans l'article** (chantier ㉓, 21/08).
///
/// > *« Le chiffre est plus dangereux que le nom : **personne ne relit un nombre**. »* — fiche ⑩
///
/// Un nom propre inventé se remarque : le lecteur connaît les acteurs de l'actualité. Un nombre
/// inventé, non — il a l'allure de tous les autres nombres, et il se cite ensuite comme un fait.
/// D'où une garde plus stricte que celle des noms : **retrouvé littéralement, ou pas écrit**.
///
/// ## Pourquoi cette garde existe AVANT l'extraction
///
/// La fiche ⑩ range l'extraction des grandeurs en 1.7.1, parce que sa qualité dépendra du modèle
/// d'OS 27. Mais *« OS 27 réduit la fréquence de l'erreur, pas sa NATURE ni son coût »* : la garde,
/// elle, ne dépend d'aucun modèle et doit être en place **le jour où la première valeur est
/// extraite**, pas après. Une garde écrite après coup arrive toujours trop tard pour les données
/// déjà écrites.
///
/// ## Ce qui est normalisé, et ce qui ne l'est SURTOUT pas
///
/// ⚠️ La presse écrit le même nombre de plusieurs façons — « 1 000 » avec une espace fine
/// insécable, « 1'000 » à la suisse, « 1 000 » avec une espace ordinaire. Ne pas les rapprocher
/// rejetterait des valeurs parfaitement exactes.
///
/// ⛔ Mais **la virgule décimale n'est JAMAIS touchée**. « 12,8 » et « 128 » ne sont pas le même
/// nombre, et un rapprochement trop généreux transformerait la garde en passoire — c'est-à-dire en
/// caution donnée à une valeur fausse, ce qui est pire que pas de garde du tout.
public enum AncrageLitteral {

    /// Vrai si `valeur` se retrouve littéralement dans `texte`, aux séparateurs de milliers près.
    public static func figureDans(_ valeur: String, texte: String) -> Bool {
        let v = normaliser(valeur)
        guard !v.isEmpty else { return false }
        return contient(normaliser(texte), valeurNormalisee: v)
    }

    /// **Recherche aux frontières de nombre**, sur deux chaînes déjà normalisées.
    ///
    /// ⛔ 15/09/2026 : la garde cherchait une simple sous-chaîne. Or la normalisation retire les
    /// séparateurs de milliers — « 12'500 » devient « 12500 » — et « 125 » s'y trouvait. Une valeur
    /// FAUSSE passait l'ancrage, exactement ce que la garde doit empêcher. Une occurrence ne compte que
    /// si elle n'est ni précédée ni suivie d'un chiffre, ni d'un séparateur décimal suivi d'un chiffre
    /// (« 12 » n'est pas dans « 12,8 », ni « 8 » dans « 12,8 »).
    public static func contient(_ texte: String, valeurNormalisee v: String) -> Bool {
        !occurrences(v, dansTexteNormalise: texte).isEmpty
    }

    /// Positions (en caractères) des occurrences de `v` aux frontières de nombre — mêmes règles que
    /// `contient`. Sert à regarder ce qui SUIT une valeur (son unité).
    public static func occurrences(_ v: String, dansTexteNormalise texte: String) -> [Range<Int>] {
        guard !v.isEmpty else { return [] }
        let t = Array(texte), c = Array(v)
        let debutChiffre = c.first?.isNumber == true, finChiffre = c.last?.isNumber == true
        guard t.count >= c.count else { return [] }
        func chiffre(_ i: Int) -> Bool { t.indices.contains(i) && t[i].isNumber }
        func decimal(_ i: Int) -> Bool { t.indices.contains(i) && (t[i] == "," || t[i] == ".") }
        var trouvees: [Range<Int>] = []
        var i = 0
        while i <= t.count - c.count {
            if t[i] == c[0], Array(t[i..<(i + c.count)]) == c {
                let j = i + c.count
                let avantLibre = !debutChiffre || !(chiffre(i - 1) || (decimal(i - 1) && chiffre(i - 2)))
                let apresLibre = !finChiffre || !(chiffre(j) || (decimal(j) && chiffre(j + 1)))
                if avantLibre && apresLibre { trouvees.append(i..<j) }
            }
            i += 1
        }
        return trouvees
    }

    /// Sépare les mesures **retenues** (ancrées) des **rejetées**.
    ///
    /// ⚠️ On rend les deux listes : une valeur rejetée n'est pas un déchet, c'est un signal — soit le
    /// modèle a inventé, soit l'extraction a reformaté un nombre. Les compter, c'est pouvoir le dire.
    public static func trier(_ mesures: [Mesure], texte: String) -> (retenues: [Mesure], rejetees: [Mesure]) {
        var retenues: [Mesure] = [], rejetees: [Mesure] = []
        for m in mesures {
            if figureDans(m.valeur, texte: texte) { retenues.append(m) } else { rejetees.append(m) }
        }
        return (retenues, rejetees)
    }

    /// **Valeurs incompatibles pour la même grandeur au même moment** — exposées côte à côte,
    /// jamais arbitrées.
    ///
    /// ⛔ **On ne tranche pas.** Deux sources qui donnent 12,8 et 24 pour le même dommage à la même
    /// date ne se départagent pas par un calcul : choisir la plus récente, la plus grande ou la
    /// mieux classée serait fabriquer une certitude que le corpus n'a pas. Le désaccord **est**
    /// l'information — et c'est au lecteur de le voir.
    ///
    /// Le regroupement se fait sur **grandeur + périmètre temporel** : « vols annulés le 14 août »
    /// et « vols annulés le 15 août » ne sont pas en désaccord, ce sont deux jours.
    public static func desaccords(_ mesures: [Mesure]) -> [(cle: String, valeurs: [Mesure])] {
        var parCle: [String: [Mesure]] = [:]
        var ordre: [String] = []
        for m in mesures {
            let cle = clePourDesaccord(m)
            if parCle[cle] == nil { ordre.append(cle) }
            parCle[cle, default: []].append(m)
        }
        return ordre.compactMap { cle in
            guard let liste = parCle[cle] else { return nil }
            // Un désaccord suppose des valeurs DIFFÉRENTES : deux sources qui disent la même chose
            // se confirment, elles ne se contredisent pas.
            let distinctes = Set(liste.map { normaliser($0.valeur) + "|" + normaliser($0.unite ?? "") })
            guard distinctes.count > 1 else { return nil }
            return (cle, liste)
        }
    }

    public static func clePourDesaccord(_ m: Mesure) -> String {
        [m.grandeur, m.perimetreTemporel ?? ""].map(normaliser).joined(separator: "@")
    }

    /// Normalisation **minimale** : casse, accents, et les seuls séparateurs de milliers.
    ///
    /// ⚠️ Les trois espaces qui séparent les milliers dans la presse — fine insécable (U+202F),
    /// insécable (U+00A0), ordinaire — et l'apostrophe suisse (« 1'000 ») sont retirées **entre deux
    /// chiffres uniquement**. Ailleurs, l'espace reste : « 12 vols » ne doit pas devenir « 12vols ».
    public static func normaliser(_ s: String) -> String {
        var t = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        for sep in ["\u{202F}", "\u{00A0}", "\u{2019}", "'", " "] {
            t = retirerEntreChiffres(t, separateur: sep)
        }
        return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compilées UNE fois : 📏 16/09/2026, la fiche d'histoire normalise des milliers de phrases, et
    /// recompiler cinq expressions à chaque appel faisait l'essentiel des 5 s mesurées sur 520 articles.
    private static let separateursEntreChiffres: [String: NSRegularExpression] = {
        var d: [String: NSRegularExpression] = [:]
        for sep in ["\u{202F}", "\u{00A0}", "\u{2019}", "'", " "] {
            d[sep] = try? NSRegularExpression(
                pattern: "(?<=[0-9])\(NSRegularExpression.escapedPattern(for: sep))(?=[0-9])")
        }
        return d
    }()

    private static func retirerEntreChiffres(_ s: String, separateur: String) -> String {
        guard s.contains(separateur) else { return s }
        guard let re = separateursEntreChiffres[separateur] ?? (try? NSRegularExpression(
            pattern: "(?<=[0-9])\(NSRegularExpression.escapedPattern(for: separateur))(?=[0-9])"))
        else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length),
                                           withTemplate: "")
    }
}
