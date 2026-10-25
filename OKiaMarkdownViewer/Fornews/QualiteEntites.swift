// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsServices/Purge/QualiteEntites.swift (commit 58fb14e9, 25/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : `motifFicheSansContenu` seul, dont `WikimediaService.choisir` a besoin (le reste lit le
// modèle SwiftData).
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

public enum QualiteEntites {
    /// Motifs de description trahissant une fiche sans contenu, dans les cinq langues de l'app.
    /// Comparés en tête de description : « prénom masculin », « nom de famille », « given name »…
    static let motifsSansContenu: [String] = [
        // français
        "prenom", "nom de famille", "patronyme", "page d homonymie", "homonymie",
        // anglais
        "given name", "family name", "surname", "male name", "female name", "disambiguation",
        // allemand
        "vorname", "familienname", "nachname", "begriffsklarung",
        // espagnol
        "nombre de pila", "nombre propio", "apellido", "desambiguacion",
        // italien
        "nome proprio", "cognome", "disambiguazione",
    ]

    /// Renvoie le motif LISIBLE si la description désigne un prénom / patronyme / homonymie.
    ///
    /// ⚠️ **Le motif doit apparaître EN TÊTE.** La documentation le disait déjà — « comparés en tête
    /// de description » — mais le code cherchait dans TOUTE la chaîne. Mesuré le 15/08 sur les 275
    /// fiches signalées du store réel : 255 portent le motif dans les 12 premiers caractères
    /// (« nom de famille », « prénom masculin »), les autres au plus tard vers 50 — la tournure
    /// française normale, « X est un prénom ». Mais DEUX le portaient au-delà de 400 : « Andrew
    /// Watt », producteur de musique bien réel dont la biographie mentionne un nom de scène, et une
    /// fiche décrivant le héros de Zelda. Les détacher aurait effacé des données justes.
    ///
    /// Le seuil de 120 caractères sépare les deux populations sans en couper aucune : le plus
    /// tardif des vrais cas est à 47, le plus précoce des faux à 403.
    public static func motifFicheSansContenu(_ description: String) -> String? {
        let d = KeywordMatcher.normalize(description)
        let tete = String(d.prefix(120))
        guard motifsSansContenu.contains(where: { tete.contains($0) }) else { return nil }
        // On rend la description telle quelle : c'est elle qui doit convaincre, pas notre résumé.
        let extrait = description.count > 60 ? String(description.prefix(60)) + "…" : description
        return "Sa fiche Wikidata dit « \(extrait) » — un prénom, un patronyme ou une page "
             + "d'homonymie ne désigne aucun sujet. La description, l'image et les coordonnées "
             + "qu'elle apporte appartiennent donc à autre chose."
    }
}
