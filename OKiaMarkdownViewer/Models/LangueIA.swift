import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 1.4 — la langue des réponses d'Apple Intelligence (résumé, conversation). L'app parle quinze
/// langues, le modèle de l'appareil non (Patrick, 27/10/2026 : « fais des contrôles », « si les
/// langues ne fonctionnent pas, il faut proposer une autre langue »). On le lui demande
/// (`supportedLanguages`) : s'il parle la langue de l'app, rien ne change ; sinon les réponses
/// viennent dans la langue choisie dans les Réglages, l'anglais à défaut.
enum LangueIA {
    static let cle = "okia.langueIA"

    /// Les langues de l'app que le modèle parle, dans l'ordre de l'app. Vide sans Apple Intelligence.
    static var prisesEnCharge: [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let modele = SystemLanguageModel.default.supportedLanguages
            return Localization.supported.filter { code in
                let l = Locale.Language(identifier: code)
                return modele.contains { $0.languageCode == l.languageCode
                    && ($0.script == nil || l.script == nil || $0.script == l.script) }
            }
        }
        #endif
        return []
    }

    /// Vrai quand le modèle parle la langue de l'app — ou qu'on ne peut pas le savoir (pas d'Apple
    /// Intelligence : rien à proposer).
    static var parleLaLangueDeLApp: Bool {
        let liste = prisesEnCharge
        return liste.isEmpty || liste.contains(Localization.shared.code)
    }

    /// La langue des résumés et des réponses.
    static var code: String {
        let app = Localization.shared.code
        let liste = prisesEnCharge
        if liste.isEmpty || liste.contains(app) { return app }
        if let choisie = UserDefaults.standard.string(forKey: cle), liste.contains(choisie) { return choisie }
        return liste.contains(Localization.fallback) ? Localization.fallback : liste[0]
    }

    /// La mention sous un résumé ou une conversation, quand ils ne viennent pas dans la langue de
    /// l'app ; vide sinon.
    static var mention: String {
        guard !parleLaLangueDeLApp else { return "" }
        let nom = AppLanguage(rawValue: code)?.nativeName ?? code
        return " " + tr("Langue non prise en charge par Apple Intelligence — réponses en : %@. À changer dans les Réglages.", nom)
    }

    /// Une chaîne dans la langue des réponses, pour ce qui part au modèle (« Voici le document à
    /// résumer : ») : écrite dans une langue qu'il ne parle pas, elle le ferait refuser.
    static func texte(_ cle: String) -> String {
        guard let chemin = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: chemin) else { return cle }
        return bundle.localizedString(forKey: cle, value: cle, table: nil)
    }
}
