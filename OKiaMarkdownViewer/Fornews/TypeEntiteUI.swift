// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsFeatures/Components/TypeEntiteUI.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import SwiftUI

/// Présentation UI des types d'entités (libellé, symbole SF, couleur). Garde les modèles UI-free.
public extension TypeEntite {
    var libelle: String {
        switch self {
        case .person:  return "Personnes"
        case .org:     return "Organisations"
        case .gpe:     return "Entités géopolitiques"
        case .loc:     return "Lieux"
        case .product: return "Produits"
        case .event:   return "Événements"
        case .date:    return "Dates"
        case .money:   return "Montants"
        case .work:    return "Œuvres"
        case .maladie: return "Maladies"
        case .autre:   return "Autres"
        }
    }

    /// Clé localisable du libellé (résolue contre le catalogue de l'app).
    var libelleKey: LocalizedStringKey { LocalizedStringKey(libelle) }

    var symbole: String {
        switch self {
        case .person:  return "person.fill"
        case .org:     return "building.2.fill"
        case .gpe:     return "globe.europe.africa.fill"
        case .loc:     return "mappin.and.ellipse"
        case .product: return "shippingbox.fill"
        case .event:   return "calendar"
        case .date:    return "clock"
        case .money:   return "eurosign.circle"
        case .work:    return "book.closed.fill"
        case .maladie: return "cross.case.fill"
        case .autre:   return "tag.fill"
        }
    }

    var couleur: Color {
        switch self {
        case .person:  return .blue
        case .org:     return .purple
        case .gpe:     return .teal
        case .loc:     return .green
        case .product: return .orange
        case .event:   return .pink
        case .date:    return .gray
        case .money:   return .mint
        case .work:    return .indigo
        // Rouge : couleur de la santé publique, et distincte des neuf autres à l'œil.
        case .maladie: return .red
        case .autre:   return .secondary
        }
    }
}
