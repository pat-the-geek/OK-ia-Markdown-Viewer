import SwiftUI

/// Document outline; tapping a heading scrolls the reader to that section.
struct TableOfContentsView: View {
    let items: [TOCItem]
    var onSelect: (TOCItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = Localization.shared

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(tr("Aucun titre", "No headings"), systemImage: "list.bullet.indent",
                                           description: Text(tr("Ce document ne contient pas de titres.",
                                                                "This document contains no headings.")))
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
            .navigationTitle(tr("Sommaire", "Contents"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Fermer", "Done")) { dismiss() }.tint(orange)
                }
            }
        }
    }
}
