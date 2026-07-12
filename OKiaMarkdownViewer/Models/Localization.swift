import SwiftUI

/// The language the app UI speaks. `.system` follows the device: French devices get
/// French, every other language gets English. The user can override in Réglages/Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case french  = "fr"
    case english = "en"

    var id: String { rawValue }
}

/// Single source of truth for the app language. Views observe it so that changing the
/// language in Settings re-renders the whole UI immediately (no restart needed).
final class Localization: ObservableObject {
    static let shared = Localization()
    private static let defaultsKey = "okia.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// True when the device's preferred language is French.
    static var systemIsFrench: Bool {
        (Locale.preferredLanguages.first ?? Locale.current.identifier)
            .lowercased().hasPrefix("fr")
    }

    var isFrench: Bool {
        switch language {
        case .french:  return true
        case .english: return false
        case .system:  return Self.systemIsFrench
        }
    }

    /// Two-letter code handed to the web renderer (window.OKIA_LANG) and the summariser.
    var code: String { isFrench ? "fr" : "en" }
}

/// Resolves a French/English string pair against the current app language.
func tr(_ fr: String, _ en: String) -> String {
    Localization.shared.isFrench ? fr : en
}

// MARK: - Settings sheet

/// App settings: today just the language choice (System / Français / English).
struct SettingsView: View {
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("Langue", "Language"), selection: $loc.language) {
                        Text(tr("Système", "System")).tag(AppLanguage.system)
                        Text("Français").tag(AppLanguage.french)
                        Text("English").tag(AppLanguage.english)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(tr("Langue de l’app", "App language"))
                } footer: {
                    Text(tr("« Système » : français si l’appareil est en français, anglais sinon.",
                            "“System”: French when the device is set to French, English otherwise."))
                }
            }
            .navigationTitle(tr("Réglages", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Fermer", "Done")) { dismiss() }.tint(orange)
                }
            }
        }
    }
}
