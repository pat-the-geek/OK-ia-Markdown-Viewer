// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/PaireDePays.swift (commit 1eb3b3d8, 23/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Détecte une **notation de match « PaysA-PaysB »** (« Suisse-Algérie », « Suisse-Canada ») : deux noms
/// de **pays** séparés par un tiret (`-`, `–`, `—`), un « / » ou « vs ». Ce n'est PAS une entité mais
/// l'affrontement de deux équipes nationales — pollue le tableau de bord des entités dominantes.
///
/// Partagé (comme [[LibellePromotionnel]]) entre le **filtre NER** `FornewsAI` (bloque les NOUVELLES
/// détections) et le **nettoyage** `FornewsServices` (supprime les EXISTANTES). Conservateur : exige
/// EXACTEMENT deux moitiés, chacune un pays connu → n'affecte pas les vrais toponymes composés
/// (« Bosnie-Herzégovine », « Colombie-Britannique », « Guinée-Bissau ») dont une moitié n'est pas un pays.
public enum PaireDePays {

    /// Vrai si `valeur` est une paire de pays (« Suisse-Algérie »). Normalise en interne.
    public static func estPaire(_ valeur: String) -> Bool {
        let n = normaliser(valeur)
            .replacingOccurrences(of: "\u{2013}", with: "-")   // – en-dash
            .replacingOccurrences(of: "\u{2014}", with: "-")   // — em-dash
        // Séparateurs « versus » testés dans l'ordre (les formes avec espaces d'abord).
        for sep in [" - ", " / ", " vs ", " vs. ", "/", "-"] where n.contains(sep) {
            let moities = n.components(separatedBy: sep)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard moities.count == 2 else { continue }
            if pays.contains(moities[0]) && pays.contains(moities[1]) { return true }
        }
        return false
    }

    /// Normalisation minuscule / sans diacritiques / espaces compactés (cohérente avec
    /// `FiltreEntitesNER.normaliser` et `KeywordMatcher.normalize`).
    private static func normaliser(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Noms de **pays** (formes normalisées : minuscules, sans diacritiques) — FR + EN courants.
    static let pays: Set<String> = [
        // Europe (FR)
        "albanie", "allemagne", "andorre", "angleterre", "autriche", "azerbaidjan", "belgique",
        "bielorussie", "bosnie", "bulgarie", "chypre", "croatie", "danemark", "ecosse", "espagne",
        "estonie", "finlande", "france", "galles", "georgie", "grece", "hongrie", "irlande",
        "islande", "italie", "kosovo", "lettonie", "liechtenstein", "lituanie", "luxembourg",
        "macedoine", "malte", "moldavie", "montenegro", "norvege", "pays-bas", "pologne", "portugal",
        "roumanie", "russie", "serbie", "slovaquie", "slovenie", "suede", "suisse", "tchequie",
        "turquie", "ukraine", "royaume-uni", "republique tcheque",
        // Amériques (FR)
        "argentine", "bolivie", "bresil", "canada", "chili", "colombie", "cuba", "equateur",
        "etats-unis", "guatemala", "haiti", "honduras", "jamaique", "mexique", "nicaragua", "panama",
        "paraguay", "perou", "uruguay", "venezuela",
        // Afrique (FR)
        "afrique du sud", "algerie", "angola", "benin", "botswana", "burkina", "cameroun", "congo",
        "egypte", "ethiopie", "gabon", "gambie", "ghana", "guinee", "kenya", "liberia", "libye",
        "madagascar", "malawi", "mali", "maroc", "mauritanie", "mozambique", "namibie", "niger",
        "nigeria", "ouganda", "rwanda", "senegal", "somalie", "soudan", "tanzanie", "tchad", "togo",
        "tunisie", "zambie", "zimbabwe", "cote d'ivoire",
        // Asie / Océanie / Moyen-Orient (FR)
        "afghanistan", "arabie saoudite", "armenie", "australie", "bahrein", "bangladesh", "birmanie",
        "cambodge", "chine", "coree du sud", "coree du nord", "inde", "indonesie", "irak", "iran",
        "israel", "japon", "jordanie", "kazakhstan", "koweit", "laos", "liban", "malaisie", "mongolie",
        "nepal", "nouvelle-zelande", "oman", "ouzbekistan", "pakistan", "palestine", "philippines",
        "qatar", "singapour", "syrie", "thailande", "vietnam", "yemen",
        // EN (variantes fréquentes dans le contenu anglophone)
        "switzerland", "germany", "spain", "italy", "england", "scotland", "wales", "netherlands",
        "belgium", "croatia", "sweden", "denmark", "norway", "poland", "greece", "turkey",
        "brazil", "argentina", "mexico", "usa", "united states", "morocco", "algeria", "tunisia",
        "egypt", "cameroon", "japan", "china", "india", "australia",
        "south korea", "north korea", "saudi arabia", "south africa", "ivory coast",
    ]
}
