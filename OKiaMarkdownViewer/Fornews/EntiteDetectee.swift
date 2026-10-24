// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/Protocols/AIProtocols.swift (commit 1eb3b3d8, 23/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : `EntiteDetectee` seule.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation


/// Entité détectée par la couche NER (avant enrichissement Wikimedia).
public struct EntiteDetectee: Sendable, Equatable {
    public var valeur: String
    public var type: TypeEntite
    /// Indice de QID proposé par le LLM — **jamais** cru sans vérification Wikimedia (§13.2).
    public var wikidataHint: String?
    public init(valeur: String, type: TypeEntite, wikidataHint: String? = nil) {
        self.valeur = valeur
        self.type = type
        self.wikidataHint = wikidataHint
    }
}
