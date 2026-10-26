import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Option Analytic (1.4) — la traduction d'une page web dans la langue de l'interface, pour sa fiche
/// de lecture (Patrick, 26/10/2026 : « le texte doit être traduit dans la langue choisie »).
///
/// Le framework Translation, sur l'appareil, comme le lecteur (`DocumentTranslator`). Il ne rend une
/// session qu'à une vue vivante : la fenêtre d'avancement de l'import porte donc
/// `TraducteurPonctuelHote`, qui ouvre la session — et, si les langues ne sont pas encore
/// installées, laisse le système proposer de les télécharger. Sans session au bout de deux minutes
/// (simulateur, où `prepareTranslation` reste suspendu ; téléchargement refusé), la fiche garde le
/// texte d'origine.
@MainActor
final class TraducteurPonctuel: ObservableObject {
    struct Demande: Equatable {
        let source: String
        let cible: String
        let jeton: Int
    }

    @Published private(set) var demande: Demande?
    private var textes: [String] = []
    private var suite: CheckedContinuation<[String]?, Never>?
    private var jeton = 0
    private var sessionOuverte = false
    private var progression: ((Int, Int) -> Void)?

    /// Les textes traduits, dans le même ordre ; nil si la traduction n'a pas pu se faire.
    func traduire(_ textes: [String], de source: String, vers cible: String,
                  progression: ((Int, Int) -> Void)? = nil) async -> [String]? {
        #if canImport(Translation)
        guard !textes.isEmpty, source != cible else { return nil }
        let statut = await LanguageAvailability().status(from: Locale.Language(identifier: source),
                                                         to: Locale.Language(identifier: cible))
        guard statut != .unsupported else { return nil }
        // Les deux langues déjà installées : une session sans vue, tout de suite. Sinon, la vue
        // d'ancrage, pour que le système propose le téléchargement.
        if statut == .installed {
            let session = TranslationSession(installedSource: Locale.Language(identifier: source),
                                             target: Locale.Language(identifier: cible))
            return await Self.lot(textes, session: session, progression: progression)
        }
        return await withCheckedContinuation { c in
            suite = c
            self.textes = textes
            self.progression = progression
            sessionOuverte = false
            jeton += 1
            demande = Demande(source: source, cible: cible, jeton: jeton)
            let attendu = jeton
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard let self, self.jeton == attendu, !self.sessionOuverte else { return }
                self.finir(nil)
            }
        }
        #else
        return nil
        #endif
    }

    #if canImport(Translation)
    /// Appelé par la vue d'ancrage quand le système donne la session. Un lot, rendu au fil de l'eau ;
    /// un morceau qui échoue garde son texte d'origine.
    func executer(_ session: TranslationSession) async {
        guard suite != nil else { return }
        sessionOuverte = true
        finir(await Self.lot(textes, session: session, progression: progression))
    }

    /// Le lot traduit au fil de l'eau ; nil si rien n'a pu l'être.
    static func lot(_ textes: [String], session: TranslationSession,
                    progression: ((Int, Int) -> Void)?) async -> [String]? {
        let requetes = textes.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        var rendu = textes
        var recus = 0, traduits = 0
        do {
            for try await r in session.translate(batch: requetes) {
                if let id = r.clientIdentifier, let i = Int(id), i < rendu.count {
                    rendu[i] = r.targetText
                    traduits += 1
                }
                recus += 1
                progression?(recus, textes.count)
            }
        } catch {
            // La session s'est interrompue : ce qui est traduit reste traduit.
        }
        return traduits > 0 ? rendu : nil
    }
    #endif

    private func finir(_ r: [String]?) {
        guard let s = suite else { return }
        suite = nil
        demande = nil
        progression = nil
        s.resume(returning: r)
    }
}

/// La vue d'ancrage : elle n'affiche rien, elle ouvre la session quand une traduction est demandée.
struct TraducteurPonctuelHote: View {
    @ObservedObject var traducteur: TraducteurPonctuel

    var body: some View {
        #if canImport(Translation)
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .translationTask(configuration) { session in await traducteur.executer(session) }
        #else
        EmptyView()
        #endif
    }

    #if canImport(Translation)
    /// Le jeton invalide la configuration à chaque demande : deux pages de même paire de langues ne
    /// rouvriraient sinon pas de session (même règle que `TranslationHostView`).
    private var configuration: TranslationSession.Configuration? {
        guard let d = traducteur.demande else { return nil }
        var cfg = TranslationSession.Configuration(source: Locale.Language(identifier: d.source),
                                                   target: Locale.Language(identifier: d.cible))
        for _ in 0..<d.jeton { cfg.invalidate() }
        return cfg
    }
    #endif
}
