// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/NomDeCodeTech.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Un nom de code de système ou de puce n'est pas un lieu.**
///
/// ## Le défaut, relevé par l'audit du 18/08/2026
///
/// « Golden Gate », nom de code de macOS 27, était typé `gpe`, relié à Q220032 et géolocalisé dans
/// le détroit de San Francisco — deuxième entité du corpus. La carte plaçait donc un système
/// d'exploitation dans un bras de mer.
///
/// Mesuré sur les 8 600 articles : **quatre** entités concernées, **19 sur 19 occurrences fausses**,
/// et pas une seule mention géographique légitime.
///
/// | Entité | Articles | Contexte réel |
/// |---|---|---|
/// | `Golden Gate` | 19 | Siri AI, iOS 27, macOS 27 |
/// | `Ventura` | 1 | « serveur IA local sur votre Mac » |
/// | `Sonoma` | 1 | « macOS Tahoe corrige 30 failles » |
///
/// ## ⛔ Pourquoi la liste ne suffit PAS, et pourquoi le contexte est exigé
///
/// Apple choisit ses noms de code parmi de **vrais lieux de Californie** : Big Sur, Catalina,
/// Monterey, Mojave, Yosemite, Ventura, Sonoma existent tous. Bannir ces noms du typage `gpe`
/// reviendrait à ne plus jamais localiser un incendie à Big Sur ou une votation à Monterey.
///
/// ⚠️ Le corpus actuel n'en contient aucun — mais « aucun aujourd'hui » n'est pas « aucun jamais »,
/// et un corpus d'actualité finit toujours par parler de la Californie. La règle exige donc **deux**
/// signaux : le nom EST un nom de code, **et** le texte porte un marqueur technologique. Sans le
/// second, on ne touche à rien.
///
/// C'est la même leçon que les mots-clés du 17/08 : une heuristique qui devine sur un seul signal
/// fabrique des dégâts qu'on ne mesure qu'après.
public enum NomDeCodeTech: Sendable {

    /// Noms de code de systèmes Apple qui sont AUSSI des toponymes réels.
    /// ⚠️ Les noms d'animaux (Tiger, Leopard, Panther…) n'y figurent pas : ils ne sont jamais typés
    /// `gpe`, et les inscrire ici n'ajouterait qu'un risque sans contrepartie mesurée.
    static let toponymesDetournes: Set<String> = [
        "golden gate", "ventura", "sonoma", "sequoia", "tahoe", "monterey",
        "big sur", "catalina", "mojave", "yosemite", "el capitan", "sierra",
        "high sierra", "mavericks",
    ]

    /// Marqueurs qui établissent le contexte technologique. Un seul suffit.
    /// ⚠️ En minuscules sans diacritiques : la comparaison se fait sur le texte normalisé.
    static let marqueursTech: [String] = [
        "macos", "ios", "ipados", "watchos", "tvos", "visionos", "xcode",
        "apple silicon", "mac os", "beta", "firmware", "wwdc",
    ]

    /// Vrai si `valeur` est un nom de code détourné **et** que `texte` établit le contexte technique.
    ///
    /// - Parameter texte: le texte de l'article, **normalisé** (minuscules, sans diacritiques).
    ///   `nil` → on ne tranche pas, et l'entité est conservée : sans contexte, aucune décision.
    public static func estNomDeCodeDansContexteTech(_ valeur: String, texte: String?) -> Bool {
        guard let texte else { return false }
        let v = valeur.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard toponymesDetournes.contains(v) else { return false }
        return marqueursTech.contains { texte.contains($0) }
    }
}
