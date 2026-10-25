// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/LibellePromotionnel.swift (commit 58fb14e9, 25/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Détecte un **libellé promotionnel / d'affiliation** (bouton « CHECK LATEST PRICE ON AMAZON »,
/// « Voir le prix », « Buy now »…) capturé à tort comme nom propre par le NER — surtout le NER
/// génératif (Foundation Models), qui prend volontiers un bouton tout-capitales pour une organisation
/// ou un produit. Un tel libellé n'est **jamais** une entité réelle : on le rejette à la détection et
/// on ne le « valide » jamais via Wikidata.
///
/// Pur (String → Bool), donc partageable par `FornewsAI` (filtre NER), `FornewsPipeline` (chokepoint
/// des deux backends NER) et `FornewsServices` (enrichissement Wikimedia) sans dépendance croisée.
public enum LibellePromotionnel {

    /// Fragments commerciaux / appels à l'action (formes **normalisées** : minuscules, sans accents).
    /// Détectés par **inclusion** dans la valeur normalisée de l'entité. Choisis pour ne jamais
    /// recouper un vrai nom propre : « Amazon » seul (→ `amazon`) ne contient aucun de ces fragments,
    /// seul un libellé-phrase comme « … on amazon » matche.
    static let fragments: [String] = [
        // EN — prix / achat / affiliation
        "check latest price", "check price", "latest price", "best price", "lowest price",
        "see price", "view price", "compare prices", "price on amazon", "buy on amazon",
        "shop on amazon", "available on amazon", "on amazon", "buy now", "shop now",
        "order now", "view deal", "best deal", "add to cart", "free shipping",
        "in stock", "out of stock", "click here", "read more", "learn more", "sign up",
        // FR — prix / achat / affiliation (apostrophes normalisées en espace : « l'offre » → « l offre »)
        "meilleur prix", "voir le prix", "verifier le prix", "acheter sur amazon",
        "prix sur amazon", "ajouter au panier", "en savoir plus", "cliquez ici",
        "decouvrir l offre", "voir l offre", "profiter de l offre", "l offre du jour",
        "voir l article", "lire l article", "toutes les offres",
    ]

    /// Vrai si `valeur` (nom d'entité brut) relève d'un libellé promotionnel / d'affiliation.
    public static func detecte(_ valeur: String) -> Bool {
        var n = valeur
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        // Normalise les apostrophes (droite, courbe, backtick) en espace → « Découvrir l'offre »
        // matche le fragment « decouvrir l offre » quel que soit le type d'apostrophe.
        for apo in ["'", "\u{2019}", "\u{2018}", "`", "\u{00B4}"] {
            n = n.replacingOccurrences(of: apo, with: " ")
        }
        n = n.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
             .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        return fragments.contains { n.contains($0) }
    }
}
