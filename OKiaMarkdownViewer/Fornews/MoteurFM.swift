// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/Apple/MoteurFM.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif
import Foundation

/// **Une session Foundation Models qui ne touche JAMAIS le fil principal.**
///
/// ⚠️ Le défaut qu'il corrige, et qui a coûté cinq builds : les appels FM interactifs créaient leur
/// `LanguageModelSession` DANS un modèle de vue `@MainActor`, puis l'appelaient via `avecDelaiMax`
/// — lui aussi `@MainActor`. Un `Task {}` créé dans un contexte `@MainActor` en HÉRITE : l'inférence
/// tournait donc sur le fil principal et **figeait l'app** pendant toute la génération, jusqu'à
/// 120 s pour une traduction intégrale. L'app figée assez longtemps se faisait tuer par le watchdog
/// (`0x8BADF00D`), ce qui produisait un rapport de plantage et faisait chercher un bug de mémoire
/// là où il n'y avait qu'un blocage.
///
/// ⛔ **Détacher la seule CLOSURE d'appel ne suffit pas** (essayé, reverté) : ce qui compte est
/// l'isolation de l'OBJET appelé, pas celle de l'appel. Tant que la session appartient au MainActor,
/// `respond` y revient. Ici la session est créée ET appelée dans cet acteur : elle n'appartient
/// jamais au fil principal. C'est ce que fait `ResumeurFoundationModels` depuis toujours — et lui
/// n'a jamais rien gelé.
///
/// À utiliser avec `avecDelaiMaxFond` (la variante HORS MainActor) : les deux vont ensemble, borner
/// l'appel depuis le fil principal ne l'empêche pas d'y tourner.
public actor MoteurFM {

    #if canImport(FoundationModels) && !os(tvOS)
    private var session: LanguageModelSession?
    private let jetonsReponse: Int?
    #endif

    /// Gardées pour repartir d'une session neuve quand la fenêtre sature.
    private let instructions: String

    /// - Parameter jetonsReponse: plafond de la réponse. Indispensable pour un fil MULTI-TOUR (le
    ///   modèle relit tout l'historique à chaque question, une réponse bavarde mange les tours
    ///   suivants) ; inutile pour un appel unique, où `nil` laisse le réglage par défaut.
    public init(instructions: String, jetonsReponse: Int? = nil) {
        self.instructions = instructions
        #if canImport(FoundationModels) && !os(tvOS)
        self.jetonsReponse = jetonsReponse
        self.session = LanguageModelSession(instructions: instructions)
        #endif
    }

    #if canImport(FoundationModels) && !os(tvOS)
    private var options: GenerationOptions {
        if let jetonsReponse { return GenerationOptions(maximumResponseTokens: jetonsReponse) }
        return GenerationOptions()
    }
    #endif

    /// Pose une invite et renvoie le texte de la réponse.
    ///
    /// ⚠️ **Reprise sur fenêtre pleine.** Un fil multi-tour finit toujours par saturer la fenêtre :
    /// les consignes y restent en permanence et chaque échange s'empile. On repart alors d'une
    /// session neuve avec les MÊMES consignes — l'historique des tours est perdu, jamais le sujet.
    /// Très préférable à ce que faisait l'app auparavant : rien, puis un gel.
    /// Reconstruit la session depuis les consignes mémorisées — après un échec, pour qu'un tour
    /// raté ne condamne pas la conversation suivante.
    public func reinitialiser() {
        #if canImport(FoundationModels) && !os(tvOS)
        session = LanguageModelSession(instructions: instructions)
        #endif
    }

    public func repondre(_ invite: String) async throws -> String {
        #if canImport(FoundationModels) && !os(tvOS)
        guard let courante = session else { return "" }
        // ⚠️ **Jamais `respond` sur une session qui répond déjà** — c'est la faute que le SDK nomme
        // (`GenerationError.concurrentRequests`), et la cause des plantages du chat.
        //
        // ⛔ L'acteur ne suffit pas : `repondre` suspend sur `await respond`, et un acteur suspendu
        // accepte un autre appel (réentrance). Sans danger pour les moteurs JETABLES — un par appel,
        // ils ne peuvent pas se chevaucher — mais la conversation de l'éditorial, elle, réutilise sa
        // session entre les tours. C'est le jumeau du chat d'article.
        guard !courante.isResponding else { throw ConversationOccupeeErreur() }
        do {
            return try await courante.respond(to: invite, options: options).content
        } catch let erreur as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = erreur else {
                // ⚠️ **Toute autre erreur JETTE la session.** Une session qui a échoué — ou qui a
                // été abandonnée par une course de délai — peut être restée EN COURS de génération.
                // La réutiliser au tour suivant, c'est appeler `respond` sur une session occupée :
                // c'est de là que venaient les plantages du chat.
                session = nil
                throw erreur
            }
            let neuve = LanguageModelSession(instructions: instructions)
            session = neuve
            return try await neuve.respond(to: invite, options: options).content
        } catch {
            session = nil
            throw error
        }
        #else
        return ""
        #endif
    }

    #if canImport(FoundationModels) && !os(tvOS)
    /// Variante à **sortie structurée** (`@Generable`), pour les appels qui ne veulent pas du texte
    /// libre : génération de règle, suggestions de sujets.
    ///
    /// ⚠️ `LanguageModelSession.Response` n'est PAS `Sendable` : on n'en fait jamais sortir la
    /// réponse elle-même. L'appelant fournit `extraire`, qui en tire des valeurs (`[String]`,
    /// tuples) — c'est cette valeur-là qui traverse la frontière de l'acteur.
    public func repondre<Contenu: Generable, Resultat: Sendable>(
        _ invite: String, generant: Contenu.Type,
        options optionsAppel: GenerationOptions? = nil,
        extraire: @Sendable (Contenu) -> Resultat
    ) async throws -> Resultat {
        guard let courante = session else { throw MoteurFMErreur.sessionAbsente }
        let reponse = try await courante.respond(to: invite, generating: generant,
                                                 options: optionsAppel ?? options)
        return extraire(reponse.content)
    }
    #endif
}

public enum MoteurFMErreur: Error { case sessionAbsente }

/// **Une demande est arrivée pendant qu'une génération tournait encore.**
///
/// ⚠️ Distincte d'une erreur de génération, et l'appelant ne doit **PAS** jeter la session quand
/// elle survient : la réponse en cours est parfaitement valide, c'est la nouvelle demande qui est de
/// trop. Reconstruire la session ici transformerait une garde en sabotage du tour attendu.
public struct ConversationOccupeeErreur: Error {
    public init() {}
}
