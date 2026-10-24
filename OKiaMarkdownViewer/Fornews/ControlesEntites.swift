// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/ControlesEntites.swift (commit 1eb3b3d8, 23/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Quatre contrôles d'entités, appliqués aux DEUX bouts** (Patrick, 04/10/2026 : « nous avons un algorithme de
/// nettoyage des entités, peut-on ajouter des contrôles selon tes constatations ? » — relevés sur les rapports
/// « Anthropic » et « Elon Musk », puis mesurés sur la base du Mac mini, 34 614 entités) :
///
/// - `FiltreEntitesNER.estValide` (FornewsAI) bloque les nouvelles détections ;
/// - `NettoyageEntites` (FornewsServices) traite l'existant à chaque passe.
///
/// Même patron que [[PaireDePays]] et [[LibelleTronque]]. Le quatrième contrôle — un titre devant un nom de
/// personne (« CEO Mark Zuckerberg », « Dr. Alan Grant ») — vit dans `TermesGeneriquesNER.retirerTitrePersonne`,
/// qui reconnaît désormais « CEO », « CFO », « PDG »… et les titres suivis d'un point.
///
/// ⛔ Écartés à la mesure, parce qu'ils prenaient de vraies entités : une personne d'un seul mot (Zendaya, Batman),
/// un nom de trois lettres (Mac, Git, Liu), un lieu commençant par un acteur (Suisse romande, Centre Pompidou),
/// deux lieux à une lettre près (Cully/Pully, Bologne/Pologne).
public enum ControlesEntites {

    /// **Deux personnes en une seule entité** — « Paul McCartney et Ringo Starr », « Samuel Boivin - Emmanuel
    /// Macron », « Cliff Booth de David Fincher ». 📏 76 entités sur le mini, toutes fausses une fois retirés « y »
    /// et « e » des séparateurs (« Santiago Ramón y Cajal » est UN nom). Aucune fusion ne les rend justes : les
    /// rattacher à l'une perdrait l'autre — même raisonnement que l'énumération « Nintendo and Sony ».
    ///
    /// Avec « de », « of », « von » : seulement quand les DEUX côtés portent au moins deux noms (« Charles de
    /// Gaulle », « Jean de La Fontaine », « Antoine de Saint-Exupéry » restent).
    public static func deuxPersonnes(_ valeur: String, typeRaw: String) -> Bool {
        guard typeRaw == TypeEntite.person.rawValue else { return false }
        let v = " " + valeur.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) + " "
        func capitalises(_ s: Substring) -> Int {
            s.split(separator: " ").filter { $0.first?.isUppercase == true }.count
        }
        for sep in [" et ", " and ", " und ", " & ", " - ", " – ", " — "] {
            if let r = v.range(of: sep) {
                if capitalises(v[..<r.lowerBound]) >= 1, capitalises(v[r.upperBound...]) >= 1 { return true }
            }
        }
        for sep in [" de ", " du ", " of ", " von "] {
            if let r = v.range(of: sep) {
                let gauche = v[..<r.lowerBound].split(separator: " ")
                if gauche.count >= 2, gauche.allSatisfy({ $0.first?.isUppercase == true }),
                   capitalises(v[r.upperBound...]) >= 2 { return true }
            }
        }
        return false
    }

    /// Les fonctions qui, en tête d'un nom de personne, ne sont pas le nom (formes normalisées, sans point).
    public static let fonctions: Set<String> = ["ceo", "cfo", "cto", "coo", "pdg"]

    /// **Une fonction sans nom** — « CEO de Sulzer », « CEO d'Energa SA » : la fonction d'une ORGANISATION, pas
    /// une personne. Sans ce contrôle, le retrait du titre en ferait la « personne » « Sulzer ».
    ///
    /// ⭐ **Quel que soit le type** (06/10/2026, vérification du nettoyage sur le mini) : réservée aux personnes, la
    /// règle laissait « CEO d'Apple », « PDG de Tesla », « CTO of Microsoft » classés organisation ou lieu. 📏 Mesuré
    /// sur la base du mini (34 942 entités) : l'extension touche 10 entités, 12 liens — toutes fausses, rien d'autre.
    public static func fonctionSansNom(_ valeur: String, typeRaw: String) -> Bool {
        let mots = valeur.split(separator: " ").map { $0.lowercased() }
        guard mots.count >= 2, fonctions.contains(mots[0].replacingOccurrences(of: ".", with: "")) else { return false }
        let suite = mots[1]
        return ["de", "du", "des", "of", "at", "von", "di", "del"].contains(suite)
            || suite.hasPrefix("d'") || suite.hasPrefix("d’")
    }

    /// Abréviations de jours et de mois (anglais, français), sans accents.
    static let abreviations: Set<String> = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
        "janv", "fevr", "avr", "juil", "lun", "mer", "jeu", "ven", "sam", "dim",
    ]
    /// Seules, elles sont aussi des noms (Theresa May, The Sun, Jan Koum…) : gardées.
    static let ambigues: Set<String> = ["may", "mar", "sun", "jan", "mer", "sam", "dim", "ven", "jeu", "lun"]

    /// **Une date abrégée prise pour une entité** — « Sep » classé maladie, « Mon Sep » ou « Tue Jun » classés
    /// personnes : l'en-tête de date d'un flux (« Tue Jun 30 »). 📏 Une dizaine sur le mini. Un sigle en
    /// capitales (« APR ») reste.
    public static func dateAbregee(_ valeur: String) -> Bool {
        guard valeur != valeur.uppercased() else { return false }
        let mots = valeur.split(separator: " ").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,")).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        }
        guard !mots.isEmpty, mots.count <= 3, mots.allSatisfy({ abreviations.contains($0) }) else { return false }
        return mots.count >= 2 || !ambigues.contains(mots[0])
    }

    /// Une entité à supprimer : deux personnes en une, une fonction sans nom, une date abrégée.
    public static func aRejeter(_ valeur: String, typeRaw: String) -> Bool {
        deuxPersonnes(valeur, typeRaw: typeRaw) || fonctionSansNom(valeur, typeRaw: typeRaw) || dateAbregee(valeur)
    }

    /// Les types qui nomment une chose par son NOM PROPRE (une date, une maladie, une somme n'en ont pas).
    public static let typesNomPropre: Set<String> = ["person", "org", "gpe", "loc", "product", "event", "work"]

    /// **Un nom commun typé comme un nom propre** — « intelligence artificielle » en produit (1 199 liens sur le
    /// mini), « fonction publique » en organisation, « nord », « mardi », « mariage » en lieux : 616 entités, 610
    /// avec une fiche Wikidata. Elles naissent le plus souvent au RENOMMAGE par Wikidata, dont les libellés de
    /// concepts sont en minuscules — la majuscule exigée à l'extraction n'y peut rien. Le nettoyage les RETYPE en
    /// « autre » plutôt que de les supprimer : leurs liens et leur fiche restent, elles quittent cartes, graphes et
    /// listes d'acteurs.
    public static func nomCommunTypeNomPropre(_ valeur: String, typeRaw: String) -> Bool {
        typesNomPropre.contains(typeRaw) && !valeur.isEmpty && !valeur.contains(where: \.isUppercase)
    }
}
