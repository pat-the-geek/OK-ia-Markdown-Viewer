// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsPipeline/RevuePresse.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : la pastille d'un média et la reconnaissance des signatures, pour la fiche de lecture.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

enum RevuePresse {
    /// **Une ligne de signature de page** : la date, l'heure et le temps de lecture que certains sites mettent en tête
    /// (« Wed Jul 01 2026, 02:33 PM EDT 2 minute read », « jeu. 17 sept. 2026, 22 h 18 EDT Lecture de 2 minutes »). Courte,
    /// et portant un temps de lecture ou une heure suivie d'un fuseau.
    public static func estLigneDeSignature(_ ligne: String) -> Bool {
        guard !ligne.isEmpty, ligne.count <= 100 else { return false }
        let lecture = "\\b\\d+\\s*(-\\s*)?(min|minutes?)\\s*(read|de lecture)\\b|\\blecture\\s*(de\\s*)?\\d+\\s*min"
            + "|\\b\\d+\\s*min(\\.|uten)?\\s*(Lesezeit|Lesedauer)\\b|\\b(Lesezeit|Lesedauer)\\s*:?\\s*\\d+"
            + "|\\b(lectura\\s*(de\\s*)?\\d+\\s*min|\\d+\\s*min(utos)?\\s*de\\s*lectura)"
            + "|\\b(lettura\\s*(di\\s*)?\\d+\\s*min|\\d+\\s*min(uti)?\\s*di\\s*lettura)"
        let heureFuseau = "\\b\\d{1,2}\\s*(:|h)\\s*\\d{2}\\s*(AM|PM)?\\s*(EDT|EST|PDT|PST|CDT|CST|UTC|GMT|CET|CEST|BST|MEZ|MESZ)\\b"
        return ligne.range(of: lecture, options: [.regularExpression, .caseInsensitive]) != nil
            || (ligne.range(of: heureFuseau, options: [.regularExpression, .caseInsensitive]) != nil
                && ligne.range(of: "\\b20\\d{2}\\b", options: .regularExpression) != nil)
    }

    /// **Une signature d'auteur** : « Par Laurence. - Publié le 14 septembre 2026 à 16h39. » (Mac4Ever, exemples du site,
    /// 06/10/2026 — elle passait pour la citation de l'article, dans la revue de presse ET le rapport de veille). Courte, et
    /// portant « publié le » suivi d'une date, ou « Par » + nom en tête, dans les cinq langues.
    public static func estSignatureDAuteur(_ phrase: String) -> Bool {
        let p = phrase.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, p.count <= 110 else { return false }
        let publie = "(?i)^[-–—|·\\s]*(publié|mis à jour|modifié|published|updated|veröffentlicht|aktualisiert|publicado|actualizado|pubblicato|aggiornato)"
            + "\\s+(le|on|am|el|il)?\\s*\\d"
        // Un NOM après « Par » (mots à majuscule) : « Par ailleurs, Apple recule. » reste une phrase.
        let auteur = "^(Par|par|By|by|Von|von|Por|por|Di|di)\\s+\\p{Lu}[\\p{L}'’-]+(\\s+\\p{Lu}[\\p{L}'’-]+){0,3}\\s*\\.?\\s*([-–—|·].*)?$"
        return p.range(of: publie, options: .regularExpression) != nil || p.range(of: auteur, options: .regularExpression) != nil
    }

    /// Une teinte par média, stable d'un document à l'autre (la somme des caractères, pas `hashValue`, qui change
    /// à chaque lancement). Des tons moyens, lisibles en blanc, en clair comme en sombre.
    static let palette = ["37,99,235", "5,150,105", "217,119,6", "219,39,119", "124,58,237", "8,145,178",
                          "220,38,38", "101,163,13", "71,85,105"]

    public static func teinte(_ nom: String?) -> String {
        guard let nom, !nom.isEmpty else { return palette.last! }
        return palette[nom.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count]
    }

    public static func initiales(_ nom: String?) -> String {
        guard let nom else { return "?" }
        let mots = nom.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "·" }).filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        guard let premier = mots.first else { return "?" }
        let deux = mots.count > 1 ? String(premier.prefix(1)) + String(mots[1].prefix(1)) : String(premier.prefix(2))
        return deux.uppercased()
    }

    public static func pastille(_ nom: String?, taille: Int) -> String {
        "<span style=\"flex:0 0 \(taille)px;width:\(taille)px;height:\(taille)px;border-radius:50%;background:rgb(\(teinte(nom)));color:#fff;font-size:\(taille * 38 / 100)px;font-weight:700;display:inline-flex;align-items:center;justify-content:center;\">\(html(initiales(nom)))</span>"
    }

    public static func html(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: " ")
    }
}
