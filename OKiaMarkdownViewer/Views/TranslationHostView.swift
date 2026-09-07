import SwiftUI
#if canImport(Translation)
import Translation
#endif

#if canImport(Translation)

/// Porte `.translationTask` pour le traducteur, et rien d'autre.
///
/// Une vue à part parce que les types du framework `Translation` n'existent qu'à partir
/// d'iOS 18 et de macCatalyst 26 : les enfermer ici évite d'annoter tout le lecteur, qui
/// se déploie encore sur iOS 17. Elle n'affiche rien — c'est un point d'ancrage, pas une
/// interface : le framework ne rend une session qu'à une vue vivante.
@available(iOS 18.0, macCatalyst 26.0, macOS 15.0, *)
struct TranslationHostView: View {
    @ObservedObject var translator: DocumentTranslator

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .translationTask(configuration) { session in
                await translator.traduire(avec: session)
            }
    }

    /// La configuration se recalcule à chaque passage : c'est voulu. Deux configurations
    /// de même paire ET de même version sont égales, donc un simple redessin ne relance
    /// rien ; seule une nouvelle demande — jeton incrémenté — ouvre une session. Sans ce
    /// jeton, le deuxième document fr→de d'une session ne serait jamais traduit, la
    /// configuration étant identique à la précédente. Mesuré au banc.
    private var configuration: TranslationSession.Configuration? {
        guard let demande = translator.demande else { return nil }
        var cfg = TranslationSession.Configuration(
            source: Locale.Language(identifier: demande.source),
            target: Locale.Language(identifier: demande.cible))
        for _ in 0..<demande.jeton { cfg.invalidate() }
        return cfg
    }
}

#endif
