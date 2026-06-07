import SwiftUI

/// Document outline; tapping a heading scrolls the reader to that section.
struct TableOfContentsView: View {
    let items: [TOCItem]
    var onSelect: (TOCItem) -> Void
    @Environment(\.dismiss) private var dismiss

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("Aucun titre", systemImage: "list.bullet.indent",
                                           description: Text("Ce document ne contient pas de titres."))
                } else {
                    List(items) { item in
                        Button {
                            onSelect(item)
                            dismiss()
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
            .navigationTitle("Sommaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.tint(orange)
                }
            }
        }
    }
}
