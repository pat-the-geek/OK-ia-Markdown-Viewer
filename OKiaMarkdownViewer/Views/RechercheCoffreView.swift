import SwiftUI

/// Option Analytic (1.4) — chercher dans tout le coffre et les documents analysés
/// (`RechercheCoffre`). Un document trouvé s'ouvre sur sa première occurrence, surlignée.
struct RechercheCoffreView: View {
    /// Ouvre un document trouvé, et y cherche le texte donné (la feuille se ferme).
    var ouvrir: (RechercheCoffre.Resultat) -> Void
    @ObservedObject private var recherche = RechercheCoffre.partage
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss
    @State var requete = ""
    @State private var portee: Portee = .tout
    @State private var resultats: [RechercheCoffre.Resultat] = []
    @State private var cherche = false
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    enum Portee: Hashable { case tout, coffre, analyse }

    var body: some View {
        NavigationStack {
            contenu
                .navigationTitle(tr("Rechercher dans le coffre"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(tr("Fermer")) { dismiss() } }
                }
                .searchable(text: $requete, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: tr("Mots, ou « expression exacte »"))
                .searchScopes($portee, activation: .onSearchPresentation) {
                    if deuxSources {
                        Text(tr("Tout")).tag(Portee.tout)
                        Text(tr("Coffre")).tag(Portee.coffre)
                        Text(tr("Documents analysés")).tag(Portee.analyse)
                    }
                }
        }
        .tint(orange)
        .onAppear { recherche.actualiser() }
        // Une recherche par pause dans la frappe, et de nouveau quand la lecture avance.
        .task(id: Cle(requete: requete, portee: portee, documents: recherche.documents.count)) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let docs = recherche.documents.values.filter { d in
                switch portee { case .tout: true; case .coffre: d.source == .coffre; case .analyse: d.source == .analyse }
            }
            let q = requete
            cherche = true
            let trouves = await Task.detached { RechercheCoffre.chercher(q, dans: Array(docs)) }.value
            guard !Task.isCancelled else { return }
            resultats = trouves
            cherche = false
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 560, minHeight: 600)
        #endif
    }

    private struct Cle: Equatable { let requete: String; let portee: Portee; let documents: Int }

    private var deuxSources: Bool {
        let sources = Set(recherche.documents.values.map(\.source))
        return sources.count > 1
    }

    @ViewBuilder private var contenu: some View {
        let vide = RechercheCoffre.termes(requete).isEmpty
        if recherche.documents.isEmpty, recherche.etat == .pret {
            ContentUnavailableView(tr("Rien à chercher"), systemImage: "tray",
                                   description: Text(tr("Ni le coffre ni les documents analysés ne contiennent de document.")))
        } else if vide {
            ContentUnavailableView {
                Label(tr("Chercher dans tous les documents"), systemImage: "magnifyingglass")
            } description: {
                Text(tr("Plusieurs mots : chacun doit se trouver dans le document. Entre guillemets : l’expression exacte. Sans tenir compte des majuscules ni des accents."))
            } actions: {
                lecture
            }
        } else if resultats.isEmpty, !cherche, recherche.etat == .pret {
            ContentUnavailableView.search(text: requete)
        } else {
            List {
                Section {
                    ForEach(resultats) { r in ligne(r) }
                } header: {
                    HStack {
                        Text(resultats.count == 1 ? tr("1 document") : tr("%d documents", resultats.count))
                        Spacer()
                        lecture
                    }
                    .textCase(nil)
                }
            }
        }
    }

    /// Où en est la lecture des documents.
    @ViewBuilder private var lecture: some View {
        if case .lecture(let fait, let total) = recherche.etat {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(tr("Lecture des documents… %d sur %d", fait, total))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if !recherche.documents.isEmpty {
            Text(recherche.documents.count == 1 ? tr("1 document lu") : tr("%d documents lus", recherche.documents.count))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func ligne(_ r: RechercheCoffre.Resultat) -> some View {
        Button { dismiss(); ouvrir(r) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: r.source == .coffre ? "doc.text" : "doc.text.magnifyingglass")
                        .foregroundStyle(orange)
                    Text(r.titre).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Spacer()
                    Text("\(r.occurrences)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(r.occurrences == 1 ? tr("1 occurrence") : tr("%d occurrences", r.occurrences))
                }
                Text((r.source == .coffre ? tr("Coffre") : tr("Documents analysés")) + " · "
                     + DecoupageParDate.mention(pour: r.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(surligne(r.extrait))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(.vertical, 2)
        }
        .tint(.primary)
    }

    /// L'extrait, les termes cherchés en gras sur fond orange pâle.
    private func surligne(_ extrait: String) -> AttributedString {
        var a = AttributedString(extrait)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for t in RechercheCoffre.termes(requete) {
            var debut = extrait.startIndex
            while let r = extrait.range(of: t, options: options, range: debut..<extrait.endIndex) {
                if let ar = Range(r, in: a) {
                    a[ar].foregroundColor = .primary
                    a[ar].backgroundColor = orange.opacity(0.25)
                    a[ar].inlinePresentationIntent = .stronglyEmphasized
                }
                debut = r.upperBound
            }
        }
        return a
    }
}
