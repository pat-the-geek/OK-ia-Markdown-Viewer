import SwiftUI

/// The language the app UI speaks. `.system` follows the device when its language is one
/// the app ships, and falls back to English otherwise. The user can override the choice in
/// Réglages/Settings. Dix langues de plus en 1.4 (27/10/2026, d'après les pays qui
/// téléchargent sans traduction) : japonais, coréen, chinois simplifié, portugais du Brésil,
/// néerlandais, russe, ukrainien, turc, vietnamien et hindi.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case french  = "fr"
    case english = "en"
    case german  = "de"
    case spanish = "es"
    case italian = "it"
    case japonais = "ja"
    case coreen = "ko"
    case chinois = "zh-Hans"
    case portugais = "pt-BR"
    case neerlandais = "nl"
    case russe = "ru"
    case ukrainien = "uk"
    case turc = "tr"
    case vietnamien = "vi"
    case hindi = "hi"

    var id: String { rawValue }

    /// Un drapeau devant le nom, pour repérer la langue d'un coup d'œil dans le menu de
    /// traduction. Ce sont les drapeaux d'usage des langues, pas des pays où on les parle :
    /// l'allemand, le français et l'italien sont aussi des langues suisses, et aucun
    /// drapeau ne dirait cela. Ils servent de repère visuel, pas de revendication.
    var drapeau: String {
        switch self {
        case .system:  return "⚙️"
        case .french:  return "🇫🇷"
        case .english: return "🇬🇧"
        case .german:  return "🇩🇪"
        case .spanish: return "🇪🇸"
        case .italian: return "🇮🇹"
        case .japonais: return "🇯🇵"
        case .coreen: return "🇰🇷"
        case .chinois: return "🇨🇳"
        case .portugais: return "🇧🇷"
        case .neerlandais: return "🇳🇱"
        case .russe: return "🇷🇺"
        case .ukrainien: return "🇺🇦"
        case .turc: return "🇹🇷"
        case .vietnamien: return "🇻🇳"
        case .hindi: return "🇮🇳"
        }
    }

    /// Each language names itself — a German speaker looks for « Deutsch », not « Allemand ».
    /// `.system` has no native name; the picker labels it with a translated string.
    var nativeName: String {
        switch self {
        case .system:  return ""
        case .french:  return "Français"
        case .english: return "English"
        case .german:  return "Deutsch"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .japonais: return "日本語"
        case .coreen: return "한국어"
        case .chinois: return "简体中文"
        case .portugais: return "Português (Brasil)"
        case .neerlandais: return "Nederlands"
        case .russe: return "Русский"
        case .ukrainien: return "Українська"
        case .turc: return "Türkçe"
        case .vietnamien: return "Tiếng Việt"
        case .hindi: return "हिन्दी"
        }
    }

    /// Le nom anglais de la langue, pour les consignes au modèle : les cinq premières langues ont
    /// leurs consignes écrites dans la langue même ; les autres reçoivent la consigne anglaise,
    /// qui nomme la langue de la réponse.
    static func nomAnglais(_ code: String) -> String {
        ["fr": "French", "en": "English", "de": "German", "es": "Spanish", "it": "Italian",
         "ja": "Japanese", "ko": "Korean", "zh-Hans": "Simplified Chinese",
         "pt-BR": "Brazilian Portuguese", "nl": "Dutch", "ru": "Russian", "uk": "Ukrainian",
         "tr": "Turkish", "vi": "Vietnamese", "hi": "Hindi"][code] ?? "English"
    }
}

/// Single source of truth for the app language. Views observe it so that changing the
/// language in Settings re-renders the whole UI immediately (no restart needed).
final class Localization: ObservableObject {
    static let shared = Localization()
    private static let defaultsKey = "okia.language"

    /// The languages present in `Localizable.xcstrings` — keep in sync with the catalogue
    /// and with `knownRegions` in project.yml.
    static let supported = AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue)
    static let fallback = "en"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            cachedBundle = nil          // the .lproj to read from just changed
        }
    }

    private var cachedBundle: Bundle?

    /// Le recours des chaînes qui manquent dans une langue (voir `tr`).
    static let anglais = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
        #if DEBUG
        // Harnais de capture : une app sandboxée ne voit pas les préférences écrites de
        // l'extérieur, donc un lancement scripté n'a que l'environnement pour fixer la
        // langue. Après la lecture ci-dessus pour que le réglage reste la source normale.
        if let forcee = ProcessInfo.processInfo.environment["OKIA_UI_LANG"],
           let choix = AppLanguage(rawValue: forcee) {
            language = choix
        }
        #endif
    }

    /// The device's preferred language, when the app speaks it — English otherwise.
    static var systemCode: String {
        for tag in Locale.preferredLanguages {
            if let code = langueDeLApp(tag) { return code }
        }
        return fallback
    }

    /// La langue de l'app pour une langue de l'appareil (« zh-Hans-CN », « pt-PT », « ko-KR »).
    /// Le chinois traditionnel n'est pas le simplifié : il passe à l'anglais. Le portugais du
    /// Portugal lit celui du Brésil plutôt que l'anglais.
    static func langueDeLApp(_ tag: String) -> String? {
        let l = Locale.Language(identifier: tag)
        guard let langue = l.languageCode?.identifier else { return nil }
        switch langue {
        case "zh": return l.script?.identifier == "Hant" || ["TW", "HK", "MO"].contains(l.region?.identifier ?? "")
            ? nil : "zh-Hans"
        case "pt": return "pt-BR"
        default:   return supported.contains(langue) ? langue : nil
        }
    }

    /// Code handed to the summariser and the translator: « fr », « ja », « zh-Hans », « pt-BR »…
    var code: String { language == .system ? Self.systemCode : language.rawValue }

    /// La langue des pages web : `render.js` et le diaporama lisent `window.OKIA_LANG_APP` d'abord.
    /// Depuis fornews 1.7.4, `render.js` connaît les quinze langues de l'app ; `window.OKIA_LANG`
    /// reçoit la même, pour qui ne lirait que lui.
    var scriptLangue: String {
        "window.OKIA_LANG = '\(code)'; window.OKIA_LANG_APP = '\(code)';"
    }

    /// La locale des dates affichées. Elle suit le réglage de l'app, pas l'appareil : un
    /// utilisateur qui a choisi l'italien lirait sinon « Giugno » sous un intitulé français.
    var locale: Locale { Locale(identifier: code) }

    /// The `.lproj` bundle strings are read from. Because Settings can override the
    /// language at runtime, strings cannot be resolved against `Bundle.main` — that one
    /// follows the *device* language and would ignore the user's choice.
    var bundle: Bundle {
        if let cached = cachedBundle { return cached }
        let resolved = Bundle.main.path(forResource: code, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        cachedBundle = resolved
        return resolved
    }
}

/// Resolves a key against the current app language. Keys are the French strings themselves
/// (`Localizable.xcstrings` has French as its source language), so a missing translation
/// degrades to readable French rather than to a raw identifier.
///
/// Extra arguments are substituted into the translation's placeholders (`%@`, `%lld`).
/// Without arguments the string is returned as-is — important for texts that contain a
/// literal `%`, which `String(format:)` would eat.
func tr(_ key: String, _ args: CVarArg...) -> String {
    var format = NSLocalizedString(key, bundle: Localization.shared.bundle, comment: "")
    // Une chaîne pas encore traduite dans l'une des dix langues ajoutées en 1.4 : l'anglais se lit
    // mieux que le français pour qui a choisi le japonais ou le turc.
    if format == key, !["fr", "en"].contains(Localization.shared.code) {
        format = Localization.anglais.localizedString(forKey: key, value: key, table: nil)
    }
    return args.isEmpty ? format : String(format: format, arguments: args)
}

// MARK: - Settings sheet

/// App settings: the language choice (System + the five shipped languages) and
/// automatic document translation.
struct SettingsView: View {
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss
    /// Éteinte par défaut : un document arrive dans sa langue, et la traduire est un
    /// choix du lecteur, pas une surprise à l'ouverture.
    @AppStorage("okia.autoTranslate") private var autoTranslate = false
    @ObservedObject private var achat = AchatAnalytic.partage
    /// 1.4 : la langue des réponses d'Apple Intelligence, quand il ne parle pas celle de l'app.
    @AppStorage(LangueIA.cle) private var langueIA = Localization.fallback

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("Langue"), selection: $loc.language) {
                        Text(tr("Système")).tag(AppLanguage.system)
                        ForEach(AppLanguage.allCases.filter { $0 != .system }) { lang in
                            Text(lang.nativeName).tag(lang)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(tr("Langue de l’app"))
                } footer: {
                    Text(tr("« Système » : la langue de l’appareil si elle est prise en charge, anglais sinon."))
                }

                // 1.4 : Apple Intelligence ne parle pas toutes les langues de l'app. Quand il ne
                // parle pas celle-ci, on propose celles qu'il parle (Patrick, 27/10/2026).
                if !LangueIA.parleLaLangueDeLApp {
                    Section {
                        Picker(tr("Langue des réponses"), selection: $langueIA) {
                            ForEach(LangueIA.prisesEnCharge, id: \.self) { code in
                                Text(AppLanguage(rawValue: code)?.nativeName ?? code).tag(code)
                            }
                        }
                    } header: {
                        Text(tr("Réponses d’Apple Intelligence"))
                    } footer: {
                        Text(tr("Apple Intelligence ne prend pas encore en charge la langue de l’app : ses résumés et ses réponses viennent dans la langue choisie ici."))
                    }
                }

                // Option Analytic (1.4) : l'acheter ou la restaurer hors d'un document.
                Section {
                    NavigationLink {
                        ScrollView { OptionAnalyticView().padding(20) }
                            .navigationTitle("Analytic")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent {
                            Text(achat.acces ? tr("Active") : achat.prix)
                        } label: {
                            Label("Analytic", systemImage: "sparkle.magnifyingglass")
                        }
                    }
                } footer: {
                    Text(tr("Lisez plus loin que le texte."))
                }

                Section {
                    Toggle(tr("Traduire les documents"), isOn: $autoTranslate)
                } header: {
                    Text(tr("Traduction automatique"))
                } footer: {
                    Text(tr("Un document ouvert dans une autre langue est traduit sur l’appareil, sans rien envoyer sur le réseau. L’original reste accessible d’un geste."))
                }
            }
            .navigationTitle(tr("Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Fermer")) { dismiss() }.tint(orange)
                }
            }
        }
    }
}
