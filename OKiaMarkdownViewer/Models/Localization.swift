import SwiftUI

/// The language the app UI speaks. `.system` follows the device when its language is one
/// of the five the app ships, and falls back to English otherwise. The user can override
/// the choice in Réglages/Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case french  = "fr"
    case english = "en"
    case german  = "de"
    case spanish = "es"
    case italian = "it"

    var id: String { rawValue }

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
        }
    }
}

/// Single source of truth for the app language. Views observe it so that changing the
/// language in Settings re-renders the whole UI immediately (no restart needed).
final class Localization: ObservableObject {
    static let shared = Localization()
    private static let defaultsKey = "okia.language"

    /// The languages present in `Localizable.xcstrings` — keep in sync with the catalogue
    /// and with `CFBundleLocalizations` in Info.plist.
    static let supported = ["fr", "en", "de", "es", "it"]
    static let fallback = "en"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            cachedBundle = nil          // the .lproj to read from just changed
        }
    }

    private var cachedBundle: Bundle?

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The device's preferred language, when the app speaks it — English otherwise.
    static var systemCode: String {
        for tag in Locale.preferredLanguages {
            let code = String(tag.prefix(2)).lowercased()
            if supported.contains(code) { return code }
        }
        return fallback
    }

    /// Two-letter code handed to the web renderer (window.OKIA_LANG) and the summariser.
    var code: String { language == .system ? Self.systemCode : language.rawValue }

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
    let format = NSLocalizedString(key, bundle: Localization.shared.bundle, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

// MARK: - Settings sheet

/// App settings: today just the language choice (System + the five shipped languages).
struct SettingsView: View {
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss

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
