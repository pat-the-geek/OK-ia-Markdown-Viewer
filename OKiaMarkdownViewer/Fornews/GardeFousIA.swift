// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/Apple/GardeFousIA.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Garde-fous communs aux appels Apple Intelligence **interactifs** (l'utilisateur attend devant un
/// spinner) : un message d'indisponibilité prêt à afficher, et un délai maximal qui évite de pendre
/// indéfiniment.
///
/// Pourquoi : le LLM tourne 100 % sur l'appareil et n'a PAS besoin du réseau une fois le modèle
/// téléchargé. Mais sur un réseau médiocre (4G faible), deux choses peuvent faire « ne démarre pas /
/// tourne en rond » : (1) le modèle pas encore provisionné → le 1ᵉʳ `respond` peut attendre très
/// longtemps ; (2) aucune borne de temps côté app. On court-circuite donc AVANT l'appel
/// (`messageIndisponibilite`) et on borne l'appel (`avecDelaiMax`).

public extension DisponibiliteAppleIntelligence {
    /// Message utilisateur (français) si Apple Intelligence n'est pas prêt à générer, sinon `nil`.
    /// À tester AVANT d'appeler `respond` pour échouer vite et clairement plutôt que de pendre.
    var messageIndisponibilite: String? {
        switch statut {
        case .disponible:
            return nil
        case .appareilNonCompatible:
            return "Cet appareil n'est pas compatible avec Apple Intelligence."
        case .appleIntelligenceDesactivee:
            return "Apple Intelligence n'est pas activé. Ouvrez Réglages → Apple Intelligence et Siri pour l'activer."
        case .modeleNonPret:
            return "Le modèle Apple Intelligence se télécharge ou se prépare. Patientez quelques instants puis réessayez."
        case .indisponible:
            return "Apple Intelligence est indisponible pour le moment. Réessayez plus tard."
        }
    }
}

/// Levée quand une opération IA dépasse son délai maximal (cf. `avecDelaiMax`).
public struct DelaiDepasseErreur: LocalizedError {
    public init() {}
    public var errorDescription: String? {
        "La génération a pris trop de temps (réseau ou modèle indisponible). Réessayez."
    }
}

/// Exécute `operation` avec un **délai maximal**, sous forme de **course** : on rend la main dès le
/// PREMIER des deux (fin de l'opération OU expiration du délai), **sans bloquer sur le perdant**.
///
/// Pourquoi une course et pas un simple `await travail.value` borné : l'inférence LLM on-device
/// n'est pas toujours interruptible en plein milieu → `travail.cancel()` peut être ignoré, et
/// `await travail.value` resterait bloqué tout le temps de la génération (lente sur iPhone). Ici, à
/// l'expiration du délai on lève `DelaiDepasseErreur` immédiatement ; l'opération est annulée au mieux
/// et se termine en arrière-plan sans bloquer l'UI.
///
/// `@MainActor` : pensé pour les modèles de vue `@MainActor @Observable` (éditorial, conversation),
/// donc `operation` capture sans souci leur état isolé (pas d'exigence `Sendable`).
/// Garde « une seule reprise » hors MainActor (verrouillée) pour `avecDelaiMaxFond`.
private final class GardeRepriseFond: @unchecked Sendable {
    private let verrou = NSLock()
    private var fini = false
    /// `true` pour le premier appelant seulement (celui qui a le droit de reprendre la continuation).
    func premierArrive() -> Bool {
        verrou.lock(); defer { verrou.unlock() }
        if fini { return false }
        fini = true
        return true
    }
}

/// Variante **hors MainActor** d'`avecDelaiMax`, pour le pipeline de fond (résumé/NER Foundation
/// Models depuis un acteur de traitement) : même course « premier des deux gagne, sans bloquer sur
/// le perdant », sans faire transiter chaque inférence par le MainActor. Une inférence FM figée
/// n'est pas annulable : sans borne, un seul `respond` gelé bloquait la passe (puis le verrou de
/// cycle, puis tout le moteur) — l'expiration rend la main et l'inférence zombie finit seule.
public func avecDelaiMaxFond<T: Sendable>(
    _ secondes: Double, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let garde = GardeRepriseFond()
    let travail = Task { try await operation() }
    let minuteur = Task<Void, Never> { try? await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000)) }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            Task {
                let r = await travail.result
                guard garde.premierArrive() else { return }
                minuteur.cancel()
                cont.resume(with: r)
            }
            Task {
                _ = await minuteur.result            // fin du sommeil (ou annulation)
                guard garde.premierArrive() else { return }
                travail.cancel()                     // annulation au mieux (peut être ignorée par le LLM)
                cont.resume(throwing: DelaiDepasseErreur())
            }
        }
    } onCancel: {
        travail.cancel()
        minuteur.cancel()
    }
}

/// Compteur process-wide de **timeouts consécutifs** des inférences Foundation Models du pipeline.
/// Les inférences figées ne sont pas annulables : elles s'empilent en zombies passe après passe
/// jusqu'à saturer l'ANE/CPU. Sur le Data Provider (mode serveur), au-delà du seuil on préfère
/// quitter proprement — le superviseur launchd relance un process sain ; c'est le mécanisme
/// d'auto-guérison le plus fiable. Sur l'app interactive, on se contente de journaliser.
public enum SurveillanceInferenceFM {
    nonisolated(unsafe) private static var timeoutsConsecutifs = 0
    private static let verrou = NSLock()
    private static let seuil = 5

    public static func succes() {
        verrou.lock(); timeoutsConsecutifs = 0; verrou.unlock()
    }

    public static func timeout() {
        verrou.lock()
        timeoutsConsecutifs += 1
        let n = timeoutsConsecutifs
        verrou.unlock()
        NSLog("fornews: inférence Foundation Models expirée (%d consécutive(s))", n)
        guard n >= seuil,
              UserDefaults.standard.bool(forKey: "fornews.modeServeur"),
              RelanceGarantie.disponible else { return }
        NSLog("fornews: %d timeouts FM consécutifs — sortie volontaire pour relance", n)
        RelanceGarantie.quitterPourRelance()
    }
}

// ⚠️ **`avecDelaiMax` (@MainActor) A ÉTÉ RETIRÉE le 29/07 — ne pas la réintroduire.**
//
// Elle a coûté cinq builds et quatre signalements. Le piège tenait en une ligne : la fonction était
// `@MainActor`, donc un `Task {}` créé à l'intérieur en HÉRITAIT — l'inférence Foundation Models
// tournait sur le fil principal et figeait l'app pendant toute la génération (jusqu'à 120 s pour une
// traduction intégrale, et sur le Mac Data Provider quatre fois par jour pour l'éditorial). Figée
// assez longtemps, l'app se faisait tuer par le watchdog (`0x8BADF00D`) — ce qui produisait un
// rapport de PLANTAGE et faisait chercher une corruption mémoire là où il n'y avait qu'un blocage.
//
// ⛔ Détacher la seule CLOSURE ne corrige rien (essayé, reverté) : ce qui compte est l'isolation de
// l'OBJET appelé, pas celle de l'appel. Tant que la session appartient au MainActor, `respond` y
// revient.
//
// ✅ Le remède, appliqué aux NEUF appels : la session vit dans un acteur (`MoteurFM`) et l'appel
// passe par `avecDelaiMaxFond`. Les deux vont ensemble. Une variante `@MainActor` n'a aucune raison
// d'exister : elle ne servirait qu'à refaire l'erreur.
