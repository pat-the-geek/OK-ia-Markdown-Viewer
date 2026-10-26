import SwiftUI

/// Document outline; tapping a heading scrolls the reader to that section.
struct TableOfContentsView: View {
    let items: [TOCItem]
    var onSelect: (TOCItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fermerPanneau) private var fermerPanneau
    @ObservedObject private var loc = Localization.shared

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(tr("Aucun titre"), systemImage: "list.bullet.indent",
                                           description: Text(tr("Ce document ne contient pas de titres.")))
                } else {
                    List(items) { item in
                        Button {
                            onSelect(item)
                            // Dans la seconde partie du Duo, le sommaire reste ouvert à côté du
                            // document : on y revient d'un titre à l'autre.
                            if fermerPanneau == nil { dismiss() }
                        } label: {
                            Text(item.text)
                                .font(item.level <= 1 ? .headline : .body)
                                .fontWeight(item.level <= 2 ? .semibold : .regular)
                                .foregroundStyle(item.level <= 1 ? Color.primary : Color.secondary)
                                .padding(.leading, CGFloat(max(0, item.level - 1)) * 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(tr("Sommaire"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Dans la seconde partie, à gauche : voir `fermerPanneau` (TableOfContentsView).
                ToolbarItem(placement: fermerPanneau != nil ? .topBarLeading : .topBarTrailing) {
                    Button(tr("Fermer")) { (fermerPanneau ?? { dismiss() })() }.tint(orange)
                }
            }
        }
    }
}

/// Ferme la seconde partie du Duo, quand une vue y est montrée au lieu d'une feuille : son bouton
/// « Fermer » ou « OK » appelle cette action plutôt que `dismiss`, qui n'y ferait rien.
///
/// ⛔ Dans la seconde partie, les boutons vont À GAUCHE. Sur le vrai Duo, la colonne du système
/// (heure, batterie) borde la seconde partie à droite : elle y range les commandes de la barre et
/// prend les touchers bien au-delà de ce qu'elle dessine — « Fermer » et « OK » posés contre elle
/// ne répondaient pas (Patrick, B88 puis B92 ; de B89 à B91 le Duo n'était plus reconnu, et la
/// correction de B88 n'avait jamais été éprouvée). Une marge de la partie entière se cumulait à la
/// zone sûre et lui volait un tiers de sa largeur (essai du 26/10).
private struct FermerPanneauKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var fermerPanneau: (() -> Void)? {
        get { self[FermerPanneauKey.self] }
        set { self[FermerPanneauKey.self] = newValue }
    }
}
