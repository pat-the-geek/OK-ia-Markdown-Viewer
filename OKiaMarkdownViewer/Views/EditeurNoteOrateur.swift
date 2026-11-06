import SwiftUI

/// La note de l'orateur qu'on écrit : la diapositive (son rang à l'écran) et le texte de départ.
struct NoteEnCours: Identifiable {
    let id = UUID()
    let index: Int
    let texte: String
}

/// L'éditeur d'une note de l'orateur (option Analytic, 1.5) : depuis le bouton « Notes » du
/// diaporama, ou le crayon de la colonne du présentateur. La note s'enregistre dans le fichier,
/// sous sa diapositive (`NotesOrateur`). Vide, elle est retirée.
struct EditeurNoteOrateur: View {
    let note: NoteEnCours
    var enregistrer: (String) -> Void
    @State private var texte = ""
    @FocusState private var focus: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $texte)
                    .font(.title3)
                    .focused($focus)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                Text(tr("Seul l’orateur voit ses notes, dans le mode présentateur. Elles s’enregistrent dans le fichier, sous la diapositive, et partent dans l’export PowerPoint."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle(tr("Notes — diapositive %@", String(note.index + 1)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Enregistrer")) {
                        enregistrer(texte)
                        dismiss()
                    }
                    .disabled(texte == note.texte)
                }
            }
        }
        .onAppear {
            texte = note.texte
            focus = true
        }
        .presentationDetents([.medium, .large])
    }
}
