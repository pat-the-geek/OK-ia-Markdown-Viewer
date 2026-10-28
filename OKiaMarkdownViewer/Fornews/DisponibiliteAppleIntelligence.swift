// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/Apple/DisponibiliteAppleIntelligence.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// Détecte si le modèle on-device d'Apple Intelligence est réellement utilisable
/// (matériel compatible, Apple Intelligence activé, modèle téléchargé).
///
/// Pilote le choix entre implémentations Apple et implémentations dégradées (§5, §13.3).
public struct DisponibiliteAppleIntelligence: DisponibiliteIA {
    public init() {}

    public var llmDisponible: Bool {
        if case .disponible = statut { return true } else { return false }
    }

    /// État détaillé d'Apple Intelligence — pour afficher un message précis (prérequis de l'app).
    public enum Statut: Sendable {
        case disponible
        case appareilNonCompatible
        case appleIntelligenceDesactivee
        case modeleNonPret
        case indisponible
    }

    public var statut: Statut {
        #if canImport(FoundationModels) && !os(tvOS)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .disponible
        case .unavailable(let raison):
            switch raison {
            case .deviceNotEligible:           return .appareilNonCompatible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceDesactivee
            case .modelNotReady:               return .modeleNonPret
            @unknown default:                  return .indisponible
            }
        @unknown default:
            return .indisponible
        }
        #else
        return .indisponible
        #endif
    }
}

// MARK: - À venir (itération 5 / 6)
//
// `ResumeurFoundationModels` (SummarizerProtocol) et `NERFoundationModels` (NERProtocol)
// s'implémenteront ici avec `LanguageModelSession` + sorties `@Generable` (cf. §13).
// Ils sont volontairement absents de l'itération 1 (scaffolding) : le pipeline tourne
// d'abord en mode dégradé (NL + extractif), puis bascule sur le LLM quand disponible.
