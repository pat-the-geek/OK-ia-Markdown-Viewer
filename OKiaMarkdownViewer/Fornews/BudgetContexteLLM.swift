// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/BudgetContexteLLM.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation
#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// **Budget de contexte du modèle on-device** — combien de matière on peut réellement lui donner.
///
/// Jusqu'ici les plafonds étaient des constantes prudentes, héritées de l'éditorial (« 8 articles
/// tronqués ») : une limite *éprouvée à l'usage*, jamais mesurée. Or `SystemLanguageModel` expose
/// **`contextSize`** depuis OS 26.0, et **`tokenCount(for:)`** depuis 26.4. On peut donc remplir la
/// fenêtre au lieu de la deviner.
///
/// ⚠️ **Remplir n'est pas déborder.** Trois réserves sont prélevées avant de calculer la place
/// disponible, et elles ne sont pas décoratives :
/// - la **réponse** attendue (le modèle écrit dans la même fenêtre que ce qu'il lit) ;
/// - les **instructions** du prompt système ;
/// - une **marge de sécurité**, parce que la conversion caractères → jetons n'est qu'une estimation
///   dès qu'on ne mesure pas exactement, et qu'un dépassement ne se rattrape pas : il lève
///   `exceededContextWindowSize` et l'utilisateur n'a rien.
///
/// Sans FoundationModels (tvOS, watchOS, appareil non compatible), tout retombe sur des valeurs
/// prudentes — le code appelant n'a pas à savoir sur quelle plateforme il tourne.
public enum BudgetContexteLLM {

    /// Repli quand la fenêtre n'est pas interrogeable. C'est aussi la valeur **mesurée** sur macOS
    /// 26.5 le 27/07/2026 : la fenêtre du modèle on-device est petite, et le rester probablement
    /// jusqu'à OS 27. Aucun code ne doit supposer qu'elle est grande.
    public static let tailleParDefaut = 4096

    /// Caractères par jeton, **mesuré** le 27/07/2026 avec `tokenCount(for:)` sur du français
    /// courant : 4,16 à 4,23 selon la longueur (2 000 → 12 000 caractères). On retient **3,8**,
    /// légèrement pessimiste : sous-estimer la place fait perdre un peu de matière, la surestimer
    /// fait échouer l'appel avec `exceededContextWindowSize` — et l'utilisateur n'a alors rien.
    ///
    /// ⚠️ Valeur pour le FRANÇAIS. L'allemand (mots composés) et les langues non latines coûtent
    /// plus cher par caractère ; la marge ci-dessous absorbe l'écart.
    public static let caracteresParJeton = 3.8

    /// Marge de sécurité sur la fenêtre annoncée.
    public static let margeSecurite = 0.90

    /// Taille de la fenêtre du modèle, en jetons.
    public static var tailleContexte: Int {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let taille = SystemLanguageModel.default.contextSize
            return taille > 0 ? taille : tailleParDefaut
        }
        #endif
        return tailleParDefaut
    }

    /// Place disponible pour la **matière** d'une invite, en caractères.
    ///
    /// - Parameters:
    ///   - reserveReponse: jetons réservés à la réponse attendue.
    ///   - instructions: le prompt système, dont la longueur est retirée de la place disponible.
    ///   - taille: fenêtre à considérer. Paramètre plutôt que lecture directe pour deux raisons :
    ///     les tests simulent une fenêtre plus grande (OS 27) sans muter d'état global, et un
    ///     appelant peut se brider volontairement.
    public static func budgetCaracteres(reserveReponse: Int, instructions: String = "",
                                        taille: Int = tailleContexte) -> Int {
        let disponible = Double(taille) * margeSecurite - Double(reserveReponse)
        let caracteres = disponible * caracteresParJeton - Double(instructions.count)
        // Plancher : en dessous, l'appel n'a plus d'intérêt — autant s'abstenir et laisser le repli
        // sans IA faire son travail.
        return max(0, Int(caracteres))
    }

    /// Budget d'ENTRÉE en caractères pour un appel qui produit une réponse d'environ
    /// `motsReponseAttendus` mots — la façon la plus lisible d'exprimer la réserve côté appelant :
    /// personne ne raisonne en jetons de sortie, tout le monde sait ce qu'il attend comme texte.
    ///
    /// ⚠️ Le modèle **écrit dans la même fenêtre que ce qu'il lit** : sans cette réserve, une
    /// réponse longue fait déborder un appel dont l'entrée tenait pourtant.
    public static func budgetEntree(motsReponseAttendus: Int, instructions: String = "",
                                    taille: Int = tailleContexte) -> Int {
        // ~1,45 jeton par mot français (mesuré : 4,2 car/jeton, ~6 caractères par mot avec espace).
        let jetonsReponse = Int(Double(motsReponseAttendus) * 1.45)
        return budgetCaracteres(reserveReponse: jetonsReponse, instructions: instructions, taille: taille)
    }

    // MARK: — Conversation multi-tour

    /// Jetons alloués à CHAQUE réponse d'une conversation. Borne indispensable : sans elle, le modèle
    /// écrit ce qu'il veut, et une réponse bavarde mange la place des tours suivants.
    public static let jetonsReponseConversation = 320

    /// Tours de conversation à préserver avant de repartir d'une session neuve.
    public static let toursConversation = 6

    /// Place laissée aux **CONSIGNES** d'une conversation (article + fiches d'entités), en caractères.
    ///
    /// ⚠️ Une conversation n'est pas un appel unique, et c'est ce qui a été manqué jusqu'au 29/07 :
    /// le modèle **relit tout le fil à chaque tour**. Les consignes ne sont pas payées une fois, elles
    /// occupent la fenêtre en permanence, et chaque question-réponse s'ajoute par-dessus. Avec
    /// 9 100 caractères de consignes (≈ 2 400 jetons sur 4 096) et des réponses non bornées, la
    /// fenêtre saturait au 3ᵉ ou 4ᵉ tour — exactement le symptôme rapporté (« plante à la 4ᵉ
    /// question, des fois à la 2ᵉ »).
    ///
    /// On réserve donc `toursConversation` allers-retours AVANT de calculer ce qui reste.
    public static func budgetConsignesConversation(tours: Int = toursConversation,
                                                   taille: Int = tailleContexte) -> Int {
        // Une question d'utilisateur : ~25 mots ≈ 36 jetons. Une réponse : le plafond ci-dessus.
        let parTour = 36 + jetonsReponseConversation
        let disponible = Double(taille) * margeSecurite - Double(tours * parTour)
        return max(0, Int(disponible * caracteresParJeton))
    }

    // MARK: — S'adapter à une fenêtre plus grande (OS 27)

    /// Budget d'une tâche dont la **sortie fait la taille de l'entrée** — traduction intégrale,
    /// réécriture. Le cas est à part : entrée et sortie se partagent la même fenêtre, donc chaque
    /// caractère lu coûte deux fois. Ignorer cela, c'est faire échouer l'appel juste au moment où
    /// l'article est un peu long.
    public static func budgetSymetrique(instructions: String = "",
                                        taille: Int = tailleContexte) -> Int {
        let jetonsUtiles = Double(taille) * margeSecurite / 2.0
        return max(0, Int(jetonsUtiles * caracteresParJeton - Double(instructions.count)))
    }

    /// De combien la fenêtre a grandi depuis celle **mesurée** le 27/07/2026 (4 096 jetons).
    /// Jamais < 1 : une fenêtre plus petite qu'attendu ne doit pas rétrécir des réglages déjà
    /// éprouvés — les budgets ci-dessus, eux, s'y adaptent déjà.
    public static func facteurFenetre(taille: Int = tailleContexte) -> Double {
        max(1.0, Double(taille) / Double(tailleParDefaut))
    }

    /// Fait **suivre à un plafond réglé à la main** l'agrandissement de la fenêtre.
    ///
    /// ⚠️ Pourquoi ce détour plutôt qu'un budget calculé : certaines limites ne viennent PAS de la
    /// fenêtre. « 20 articles pour l'éditorial », « 6 000 caractères à traduire » ont été réglées à
    /// l'usage — sur la qualité de la sortie et le temps de génération, pas sur la place disponible.
    /// Les recalculer d'un budget les changerait AUJOURD'HUI, sans que rien ne le justifie. Ici,
    /// elles restent exactement ce qu'elles sont sur la fenêtre actuelle, et ne bougent que le jour
    /// où l'OS en offre une plus grande.
    ///
    /// - Parameter plafond: borne absolue. Au-delà, ce n'est plus la fenêtre qui limite mais
    ///   l'attention du modèle et le temps de génération.
    public static func plafondAdaptatif(_ valeurReglee: Int, max plafond: Int,
                                        taille: Int = tailleContexte) -> Int {
        Swift.min(plafond, Int(Double(valeurReglee) * facteurFenetre(taille: taille)))
    }

    /// **Combien d'ARTICLES confier à une synthèse**, pour une fenêtre donnée.
    ///
    /// ⚠️ La raison d'être de cette fonction : quand OS 27 agrandira la fenêtre, les plafonds en dur
    /// (« 8 articles », « 20 articles ») ne suivraient pas — l'app resterait bridée sur une limite
    /// devenue fausse. Ici, elle suit.
    ///
    /// Bornée des DEUX côtés, et pas par prudence administrative :
    /// - un **plancher** (`min`) parce qu'une synthèse sur deux articles n'en est pas une ;
    /// - un **plafond** (`max`) parce qu'au-delà, ce n'est plus la fenêtre qui limite mais
    ///   l'attention du modèle et le temps de génération — un prompt de cent articles produit une
    ///   bouillie, lentement.
    public static func articlesPourSynthese(tailleExtrait: Int = 600, motsReponseAttendus: Int = 90,
                                            min plancher: Int = 8, max plafond: Int = 60,
                                            taille: Int = tailleContexte) -> Int {
        let budget = budgetEntree(motsReponseAttendus: motsReponseAttendus, taille: taille)
        let parArticle = Swift.max(1, tailleExtrait + 60)      // + titre et séparateur
        return Swift.min(plafond, Swift.max(plancher, budget / parArticle))
    }

    /// Mesure EXACTE du nombre de jetons d'un texte (OS 26.4+). `nil` si indisponible : l'appelant
    /// retombe alors sur l'estimation par caractères.
    public static func tokens(de texte: String) async -> Int? {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
            return try? await SystemLanguageModel.default.tokenCount(for: Prompt(texte))
        }
        #endif
        return nil
    }

    /// Tronque `morceaux` pour tenir dans le budget, **sans couper un morceau en deux** : on garde
    /// les premiers entiers. Un extrait tronqué au milieu d'une phrase apprend moins au modèle
    /// qu'un extrait de moins.
    ///
    /// - Returns: les morceaux retenus (au moins un, s'il en existe).
    public static func ajuster(_ morceaux: [String], budget: Int, separateur: String = "\n\n") -> [String] {
        guard budget > 0, !morceaux.isEmpty else { return morceaux.isEmpty ? [] : [morceaux[0]] }
        var retenus: [String] = []
        var total = 0
        for m in morceaux {
            let cout = m.count + separateur.count
            if total + cout > budget, !retenus.isEmpty { break }
            retenus.append(m)
            total += cout
        }
        return retenus
    }

    // MARK: — Longueur d'un résumé

    /// Jetons réellement consommés par une ligne de résumé Markdown. **Valeur empirique**, issue
    /// d'un bug de troncature : le résumé s'arrêtait à trois lignes, gras non refermé, faute d'un
    /// budget de sortie explicite. L'arithmétique naïve (12 mots × 1,45) donnerait 17 — quatre fois
    /// moins. On garde le chiffre mesuré à l'usage : il inclut le Markdown, les noms propres coûteux
    /// en jetons, et la variabilité du modèle.
    public static let jetonsParLigneResume = 60
    /// Supplément pour les champs structurés de la réponse (`faitsSources`, `pointsCles`).
    public static let jetonsStructureResume = 300
    /// Part de la fenêtre laissée à la SORTIE. Le reste sert à LIRE l'article — un résumé qui n'a vu
    /// qu'un tiers de son article n'est pas un résumé, il est une invention polie.
    public static let partSortieResume = 0.45

    /// Jetons à réserver pour un résumé de `lignes` lignes.
    ///
    /// ⚠️ **La même valeur doit servir aux deux bouts** : `GenerationOptions.maximumResponseTokens`
    /// ET la réserve retirée du budget d'entrée. Les dissocier — une réserve de 348 jetons face à
    /// une génération autorisée à 1 500 — fait dépasser la fenêtre dès que le modèle utilise son
    /// quota, et `exceededContextWindowSize` ne rend AUCUN résumé.
    public static func jetonsReponseResume(lignes: Int, taille: Int = tailleContexte) -> Int {
        let demande = lignes * jetonsParLigneResume + jetonsStructureResume
        return Swift.min(demande, Int(Double(taille) * margeSecurite * partSortieResume))
    }

    /// **Combien de lignes ce modèle peut-il réellement rendre**, en gardant de quoi lire l'article.
    ///
    /// C'est la borne que l'ancien réglage manuel ignorait : il proposait jusqu'à 80 lignes, soit
    /// 5 100 jetons de sortie — plus que la fenêtre ENTIÈRE. Au-delà du plafond calculé ici, la
    /// demande n'est pas ambitieuse, elle est irréalisable.
    public static func plafondLignesResume(taille: Int = tailleContexte) -> Int {
        let pourSortie = Double(taille) * margeSecurite * partSortieResume
        return Swift.max(5, Int((pourSortie - Double(jetonsStructureResume)) / Double(jetonsParLigneResume)))
    }

    /// **Longueur d'un résumé, déduite de l'article lui-même** — plus une valeur réglée à la main.
    ///
    /// Deux raisons de la calculer plutôt que de la fixer :
    /// - la bonne longueur dépend de l'ARTICLE, pas d'une préférence globale. Demander vingt lignes
    ///   sur une dépêche de trois paragraphes, c'est demander du remplissage — et le vérificateur
    ///   d'ancrage rejette alors le résumé, qui retombe sur l'extractif ;
    /// - le plafond, lui, dépend de la FENÊTRE, que l'on mesure désormais.
    ///
    /// Un compte rendu utile fait environ un sixième de sa source (≈ 1 ligne de 12 mots pour 60 mots
    /// lus). Plancher à 8 lignes : en dessous, autant lire l'article.
    public static func lignesResume(motsSource: Int, taille: Int = tailleContexte) -> Int {
        let cible = motsSource / 60
        return Swift.min(plafondLignesResume(taille: taille), Swift.max(8, cible))
    }
}
