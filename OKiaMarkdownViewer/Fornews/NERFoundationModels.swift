// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/Apple/NERFoundationModels.swift (commit 1eb3b3d8, 23/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels

/// Entité extraite par le LLM (sortie structurée).
@Generable
struct EntiteGeneree {
    @Guide(description: """
        Nom propre uniquement (personne, organisation, lieu, produit, événement, œuvre précis), \
        sans article ni adjectif de nationalité (ex. « Alexander Zverev », pas « Allemand Alexander Zverev »). \
        N'extrais PAS : les noms communs (« frère », « mairie », « primature »), les titres ou fonctions \
        seuls (« président », « ministre », « directeur », « M. », « Dr »), les gentilés/nationalités \
        (« Grecs », « Français »), ni les termes génériques (« organisateurs », « armateurs », « habitants »). \
        Conserve la casse d'origine du nom propre. \
        Si le même nom apparaît sous plusieurs orthographes, donne une seule forme, la plus complète.
        """)
    var valeur: String

    @Guide(description: "Type, en minuscules, parmi : person, org, gpe, loc, product, event, work, maladie, money, date, autre. « maladie » pour une maladie ou un agent pathogène nommé (Ebola, Covid-19, grippe aviaire).")
    var type: String
}

@Generable
struct ResultatNER {
    @Guide(description: """
        Vrais noms propres importants du texte, dédupliqués. \
        Exclure noms communs, titres/fonctions seuls, gentilés et termes génériques.
        """)
    var entites: [EntiteGeneree]
}

/// NER fin / typé via Foundation Models (§13.2) : types précis et désambiguïsation,
/// là où Natural Language ne suffit pas.
public struct NERFoundationModels: NERProtocol {
    private let maxCaracteresExplicite: Int?

    /// - Parameter maxCaracteres: `nil` (défaut) → budget déduit de la fenêtre réelle. La réponse
    ///   d'un NER est une simple liste de noms : la réserve de sortie est faible, et presque toute
    ///   la fenêtre peut servir à LIRE l'article — ce que les 6 000 caractères fixes ne faisaient pas.
    public init(maxCaracteres: Int? = nil) {
        self.maxCaracteresExplicite = maxCaracteres
    }

    /// Consignes système — **hoistées pour être DÉCOMPTÉES du budget** autant qu'elles sont
    /// envoyées : sans cela, un millier de caractères partait dans la fenêtre sans être compté.
    private static let consignes = """
        Tu extrais uniquement les VRAIS NOMS PROPRES importants : personnes, organisations, \
        lieux, produits, événements, œuvres précis — ainsi que les MALADIES et agents \
        pathogènes nommés (Ebola, Covid-19, grippe aviaire), qui sont des sujets d'actualité \
        à part entière même quand ils s'écrivent sans majuscule. Donne le nom propre seul, sans article \
        ni adjectif de nationalité. \
        N'extrais jamais : les noms communs, les titres ou fonctions seuls \
        (« président », « ministre », « M. », « Dr »), les gentilés/nationalités \
        (« Grecs », « Français »), ni les termes génériques (« organisateurs », « habitants »). \
        En cas d'orthographes multiples d'un même nom, n'en donne qu'une, la plus complète.
        """

    private var maxCaracteres: Int {
        if let explicite = maxCaracteresExplicite { return explicite }
        return max(2_000, BudgetContexteLLM.budgetEntree(motsReponseAttendus: 120,
                                                         instructions: Self.consignes))
    }

    public func detecter(_ texte: String, langue: String?) async throws -> [EntiteDetectee] {
        let session = LanguageModelSession(instructions: Self.consignes)
        let extrait = String(texte.prefix(maxCaracteres))
        // Borne dure (cf. ResumeurFoundationModels) : une inférence figée gelait toute la passe.
        // `.content` extrait DANS la closure : `Response` n'est pas `Sendable`.
        let contenu: ResultatNER
        do {
            contenu = try await avecDelaiMaxFond(90) {
                try await session.respond(
                    to: "Extrais les entités nommées de ce texte :\n\n\(extrait)",
                    generating: ResultatNER.self).content
            }
            SurveillanceInferenceFM.succes()
        } catch is DelaiDepasseErreur {
            SurveillanceInferenceFM.timeout()
            throw DelaiDepasseErreur()
        }
        let candidates = contenu.entites.compactMap { gen -> EntiteDetectee? in
            let valeur = gen.valeur.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !valeur.isEmpty else { return nil }
            let type = TypeEntite(rawValue: gen.type.lowercased()) ?? .autre
            return EntiteDetectee(valeur: valeur, type: type)
        }
        // Garde-fou côté code : le prompt réduit le bruit sans l'éliminer (cf. démo). On ancre aussi
        // sur `extrait` (le texte réellement vu par le LLM) pour écarter les noms hallucinés.
        return FiltreEntitesNER.filtrer(candidates, texteSource: extrait)
    }
}
#endif
