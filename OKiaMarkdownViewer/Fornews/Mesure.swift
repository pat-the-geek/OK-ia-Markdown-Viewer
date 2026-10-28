// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/Article.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : `Mesure` seule (une grandeur chiffrée), dont `AncrageLitteral` a besoin ; le reste est
// le modèle SwiftData des articles.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Une grandeur chiffrée extraite d'un article (spec Etna §7). ⚠️ `valeur` en **texte** pour préserver
/// l'ancrage littéral (« plus de 1 000 », « 12,8-24 ») — un chiffre reformaté n'est plus vérifiable.
public struct Mesure: Codable, Equatable, Sendable {
    public var grandeur: String            // « vols annulés », « dommage touristique »
    public var valeur: String              // littéral, tel qu'écrit dans la source
    public var unite: String?              // « M€ », « vols »… (optionnel)
    public var perimetreTemporel: String?  // « le 14 août », « au 15/08 »… (optionnel)
    public var sourceCitee: String?        // média/fédération cité dans le texte (optionnel)
    public init(grandeur: String, valeur: String, unite: String? = nil,
                perimetreTemporel: String? = nil, sourceCitee: String? = nil) {
        self.grandeur = grandeur; self.valeur = valeur; self.unite = unite
        self.perimetreTemporel = perimetreTemporel; self.sourceCitee = sourceCitee
    }
}
