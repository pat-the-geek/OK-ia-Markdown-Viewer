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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Fermer")) { (fermerPanneau ?? { dismiss() })() }.tint(orange)
                }
            }
        }
    }
}

/// Ferme la seconde partie du Duo, quand une vue y est montrée au lieu d'une feuille : son bouton
/// « Fermer » ou « OK » appelle cette action plutôt que `dismiss`, qui n'y ferait rien.
private struct FermerPanneauKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var fermerPanneau: (() -> Void)? {
        get { self[FermerPanneauKey.self] }
        set { self[FermerPanneauKey.self] = newValue }
    }
}
