import SwiftUI

/// Les thèmes de lecture (1.3) : cinq habillages pensés pour lire un rapport, choisis dans le
/// menu « Aa » du lecteur.
///
/// La clé est celle de `style.css` (`html[data-okia-theme="…"]`) ; c'est la feuille de style qui
/// fait le travail, l'app ne fait que la retenir et la transmettre. Les exports — PDF, Word,
/// PowerPoint — gardent la charte OK-ia quel que soit le thème : décidé avec Patrick, ce qui sort
/// de l'app est un document transmis, pas l'écran de son auteur.
enum ReaderTheme: String, CaseIterable, Identifiable {
    case okia, administratif, editorial, lecture, contraste

    var id: String { rawValue }

    var nom: String {
        switch self {
        case .okia:          return "OK-ia"
        case .administratif: return tr("Administratif")
        case .editorial:     return tr("Éditorial")
        case .lecture:       return tr("Lecture longue")
        case .contraste:     return tr("Contraste élevé")
        }
    }

    /// Le dessin des titres, pour que la vignette du menu montre le caractère du thème : arrondi
    /// pour Nunito, à empattements pour les thèmes qui en portent.
    var dessinTitre: Font.Design {
        switch self {
        case .okia:                               return .rounded
        case .administratif, .editorial, .lecture: return .serif
        case .contraste:                          return .default
        }
    }

    /// Fond, titre et accent de la vignette.
    /// ⚠️ À garder en accord avec `style.css` : ce sont les mêmes valeurs, en clair et en sombre.
    func vignette(_ schema: ColorScheme) -> (fond: Color, titre: Color, accent: Color) {
        let sombre = schema == .dark
        switch self {
        case .okia:
            return sombre ? (Color(hex: 0x16161A), Color(hex: 0xECEAE3), Color(hex: 0xE8972E))
                          : (Color(hex: 0xFAFAF8), Color(hex: 0x111111), Color(hex: 0xE8972E))
        case .administratif:
            return sombre ? (Color(hex: 0x15181C), Color(hex: 0xE9EEF4), Color(hex: 0x8DB4DD))
                          : (Color(hex: 0xFFFFFF), Color(hex: 0x10243A), Color(hex: 0x1F4E79))
        case .editorial:
            return sombre ? (Color(hex: 0x121212), Color(hex: 0xF2F2F2), Color(hex: 0xF0707C))
                          : (Color(hex: 0xFFFFFF), Color(hex: 0x111111), Color(hex: 0xA61E2D))
        case .lecture:
            return sombre ? (Color(hex: 0x1C1915), Color(hex: 0xE6DCCB), Color(hex: 0xD9A066))
                          : (Color(hex: 0xF6F0E3), Color(hex: 0x2E2922), Color(hex: 0x9A5B2A))
        case .contraste:
            return sombre ? (Color(hex: 0x000000), Color(hex: 0xFFFFFF), Color(hex: 0xFFD60A))
                          : (Color(hex: 0xFFFFFF), Color(hex: 0x000000), Color(hex: 0x0033B3))
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
