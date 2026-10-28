// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/Protocols/AIProtocols.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Résultat d'un résumé généré on-device.
/// **D'où vient ce résumé** (㉔, 21/08).
///
/// ⚠️ Le repli extractif était **totalement silencieux** : `FornewsAIFactory` attrapait l'erreur du
/// modèle et rendait un résumé de secours sans que rien, nulle part, n'en garde trace. Un résumé
/// nettement moins bon apparaissait donc sans raison visible — et c'est la leçon de l'éditorial gelé
/// du 17/08 : **un repli muet se lit comme une panne**.
public enum OrigineResume: Sendable, Equatable {
    /// Produit par le modèle de langue.
    case modele
    /// Produit par le repli extractif, le modèle ayant échoué ou refusé. `raison` est le message
    /// d'origine — c'est lui qui permet de DIRE pourquoi, au lieu de laisser deviner.
    case repliExtractif(raison: String)

    public var estRepli: Bool { if case .repliExtractif = self { return true }; return false }
}

public struct ResumeResultat: Sendable, Equatable {
    public var resume: String
    public var pointsCles: [String]
    /// ⚠️ Valeur par défaut `.modele` : les résumeurs qui n'ont rien à déclarer restent inchangés,
    /// et seule la façade de repli a besoin de la renseigner.
    public var origine: OrigineResume

    public init(resume: String, pointsCles: [String] = [], origine: OrigineResume = .modele) {
        self.resume = resume
        self.pointsCles = pointsCles
        self.origine = origine
    }
}

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

// MARK: - Protocoles (frontière d'abstraction des frameworks Apple)

/// Génère un résumé. Implémentations : Foundation Models (à venir) / extractif dégradé.
public protocol SummarizerProtocol: Sendable {
    func resumer(_ texte: String, langue: String?) async throws -> ResumeResultat
    /// Avec la consigne de TON de l'utilisateur (⑨, 15/09/2026). Par défaut ignorée : seul le résumeur
    /// génératif sait l'appliquer, et seulement sur une fenêtre assez grande.
    func resumer(_ texte: String, langue: String?, consigne: String?) async throws -> ResumeResultat
}

public extension SummarizerProtocol {
    func resumer(_ texte: String, langue: String?, consigne: String?) async throws -> ResumeResultat {
        try await resumer(texte, langue: langue)
    }
}

/// Détecte les entités nommées. Implémentations : NL + Foundation Models / NL seul (dégradé).
public protocol NERProtocol: Sendable {
    func detecter(_ texte: String, langue: String?) async throws -> [EntiteDetectee]
}

/// Traduit du texte. Implémentations : Translation framework / pass-through (dégradé).
public protocol TranslatorProtocol: Sendable {
    func traduire(_ texte: String, vers cible: String, depuis source: String?) async throws -> String
}

/// Indique si l'IA générative (LLM on-device) est réellement disponible.
public protocol DisponibiliteIA: Sendable {
    var llmDisponible: Bool { get }
}
