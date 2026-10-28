// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsFeatures/Components/LangueHelper.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Consignes communes imposées aux dialogues LLM (conversation article + éditorial).
enum ConsignesLLM {
    /// Mise en forme obligatoire de TOUTE réponse de dialogue : chapitres « ## » + paragraphes,
    /// rendue par `ResumeMarkdownView`. Évite le bloc unique et le code markdown brut affiché tel quel.
    static let miseEnForme = """
        Structure TOUJOURS ta réponse en Markdown : un ou plusieurs CHAPITRES introduits par un titre \
        « ## » sur sa propre ligne, suivis de paragraphes courts (2-3 phrases). Mets en **gras** les \
        éléments saillants et n'utilise des listes à puces « - » que pour de vraies énumérations. Ne \
        place JAMAIS « ## », « # » ou « | » à l'intérieur d'une phrase ; un titre est toujours seul sur \
        sa ligne. N'enveloppe pas ta réponse dans un bloc de code.
        """
}

/// Drapeaux et métadonnées des 5 langues supportées dans Fornews.
/// Utilisé par les sélecteurs de langue (source) et les badges (article).
enum LangueHelper {

    /// Les 5 langues disponibles dans l'app (code BCP-47 + libellé affiché).
    static let disponibles: [(code: String, label: String)] = [
        ("fr", "🇫🇷 Français"),
        ("en", "🇬🇧 English"),
        ("de", "🇩🇪 Deutsch"),
        ("es", "🇪🇸 Español"),
        ("it", "🇮🇹 Italiano"),
    ]

    /// Emoji drapeau pour un code BCP-47 (compare les 2 premiers caractères).
    static func drapeau(_ code: String?) -> String {
        switch code?.prefix(2) {
        case "fr": return "🇫🇷"
        case "en": return "🇬🇧"
        case "de": return "🇩🇪"
        case "es": return "🇪🇸"
        case "it": return "🇮🇹"
        default:   return "🌐"
        }
    }

    /// Nom de la langue pour un code BCP-47 (accessibilité / tooltips).
    static func nom(_ code: String?) -> String {
        switch code?.prefix(2) {
        case "fr": return "Français"
        case "en": return "English"
        case "de": return "Deutsch"
        case "es": return "Español"
        case "it": return "Italiano"
        default:   return code ?? "?"
        }
    }

    /// Nom de la langue **en français**, pour les instructions de prompt LLM
    /// (« Réponds en … »). Aligné sur ResumeurFoundationModels.nomLangue.
    static func nomCible(_ code: String?) -> String {
        switch (code ?? "fr").prefix(2) {
        case "en": return "anglais"
        case "es": return "espagnol"
        case "de": return "allemand"
        case "it": return "italien"
        // ⭐ 1.7.4 ⑥ (md Viewer 1.4) : les langues que le modèle de l'appareil parle ; le russe, l'ukrainien et le
        // hindi, qu'il ne parle pas, demandent l'anglais (cf. `ConsignesAnalyste.langueDeRedaction`).
        case "ja": return "japonais"
        case "ko": return "coréen"
        case "zh": return "chinois simplifié"
        case "pt": return "portugais du Brésil"
        case "nl": return "néerlandais"
        case "tr": return "turc"
        case "vi": return "vietnamien"
        case "ru", "uk", "hi": return "anglais"
        default:   return "français"
        }
    }

    /// Vrai si le code est valide et connu (exclut nil, vide, « und »).
    static func estConnu(_ code: String?) -> Bool {
        guard let c = code, !c.isEmpty, c != "und" else { return false }
        return disponibles.contains { $0.code == String(c.prefix(2)) }
    }
}
