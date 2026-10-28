// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/DrapeauPays.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Dérive un **émoji drapeau** à partir d'un nom de **pays** (dans une des langues de l'app),
/// 100 % on-device (aucun schéma, aucun réseau). Repli `nil` si le nom ne correspond pas à un
/// pays ISO (régions, villes, blocs comme « UE »…) → on garde alors le symbole générique.
public enum DrapeauPays {

    /// Émoji drapeau pour un nom de pays/entité géopolitique, ou `nil`.
    /// 1) cas particuliers à émoji direct (drapeaux à séquence de tags : Angleterre/Écosse/Galles) ;
    /// 2) sinon code ISO → drapeau (regional indicators), avec alias (UE, ONU, abréviations…).
    public static func emoji(pourNom nom: String) -> String? {
        let n = norm(nom)
        if let direct = emojiSpecial[n] { return direct }
        return codeISO(n).map(drapeau)
    }

    /// Drapeaux émoji NON dérivables d'un code à 2 lettres (séquences de tags Unicode).
    private static let emojiSpecial: [String: String] = [
        // Nations constitutives du Royaume-Uni.
        "angleterre": "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",
        "england":    "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",
        "ecosse":     "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
        "scotland":   "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
        "schottland": "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
        "pays de galles": "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}",
        "wales":          "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}",
    ]

    /// Drapeau émoji à partir d'un code pays ISO 3166-1 alpha-2 (ex. « FR » → 🇫🇷),
    /// via les **regional indicator symbols** (offset 127397).
    private static func drapeau(_ code: String) -> String {
        code.uppercased().unicodeScalars.reduce(into: "") { acc, s in
            if let scalar = Unicode.Scalar(127397 + s.value) { acc.unicodeScalars.append(scalar) }
        }
    }

    private static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Map (nom de pays normalisé, dans les 5 langues de l'app) → code ISO. Construite une seule fois.
    private static let nomVersCode: [String: String] = {
        var m: [String: String] = [:]
        let langues = ["fr", "en", "es", "de", "it"]
        let codes = Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }
        for code in codes {
            for lang in langues {
                if let nom = Locale(identifier: lang).localizedString(forRegionCode: code) {
                    m[norm(nom)] = code
                }
            }
        }
        // Cas particuliers / alias non couverts par les noms localisés ISO. Le code est ensuite
        // converti en drapeau via les regional indicators (ex. EU → 🇪🇺, UN → 🇺🇳, XK → 🇽🇰).
        let alias: [String: String] = [
            // Abréviations & variantes courantes de pays.
            "usa": "US", "u s a": "US", "etats unis d amerique": "US",
            "uk": "GB", "u k": "GB", "grande bretagne": "GB", "great britain": "GB",
            "uae": "AE", "taiwan": "TW", "palestine": "PS", "kosovo": "XK",
            "coree": "KR", "birmanie": "MM", "vatican": "VA",
            // Union européenne (toutes langues de l'app).
            "ue": "EU", "union europeenne": "EU", "union europeene": "EU",
            "european union": "EU", "union europea": "EU", "unione europea": "EU",
            "europaische union": "EU",
            // Nations Unies / ONU.
            "onu": "UN", "nations unies": "UN", "organisation des nations unies": "UN",
            "united nations": "UN", "un": "UN", "naciones unidas": "UN",
            "vereinte nationen": "UN", "nazioni unite": "UN",
        ]
        for (nom, code) in alias { m[norm(nom)] = code }
        return m
    }()

    private static func codeISO(_ nom: String) -> String? { nomVersCode[norm(nom)] }

    /// Code ISO d'un PAYS d'après son nom — `nil` pour les blocs (UE, ONU), qui n'ont ni centre ni
    /// frontière. Sert à `CentresPays` (carte d'une entité pays, 18/09/2026).
    public static func codeISO(pourNom nom: String) -> String? {
        guard let c = codeISO(norm(nom)), c != "EU", c != "UN" else { return nil }
        return c
    }
}
