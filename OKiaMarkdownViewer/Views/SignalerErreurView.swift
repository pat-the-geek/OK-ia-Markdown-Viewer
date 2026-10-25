import SwiftUI

/// Option Analytic (1.4) — « Signaler une erreur » : six genres d'erreur dans un menu (Patrick,
/// 25/10/2026). La correction vaut pour tous les documents et se rejoue à chaque analyse
/// (`CorrectionsEntites`).
///
/// Le menu se trouve sur la fiche d'une entité et dans le menu contextuel de la liste et de la
/// galerie. Les deux choix qui demandent une liste (une autre fiche, l'entité qui la reprend)
/// ouvrent une feuille, tenue par la vue qui montre le menu.
struct MenuSignalerErreur: View {
    let entite: EntiteDocument
    @ObservedObject var analyse: AnalyseEntites
    /// Ouvre le choix d'une autre fiche Wikidata.
    var autreFiche: () -> Void
    /// Ouvre le choix de l'entité qui reprend celle-ci.
    var memeQue: () -> Void
    /// L'entité vient de disparaître de la liste (« ce n'est pas une entité ») : une fiche ouverte
    /// se referme.
    var retiree: () -> Void = {}

    var body: some View {
        Menu {
            // 1. La fiche Wikidata : seulement quand l'utilisateur a accepté Wikidata.
            if analyse.wikidataAccepte {
                Button(action: autreFiche) {
                    Label(entite.qid == nil ? tr("Choisir une fiche Wikidata…") : tr("Ce n’est pas la bonne fiche…"),
                          systemImage: "rectangle.stack.badge.minus")
                }
            }
            // 2. Le genre.
            Menu {
                ForEach(AnalyseEntites.typesMontres, id: \.self) { t in
                    Button { analyse.corriger(entite) { $0.type = t } } label: {
                        Label(tr(t.libelle), systemImage: t.symbole)
                    }
                    .disabled(t == entite.type)
                }
            } label: {
                Label(tr("Mauvais genre"), systemImage: "tag")
            }
            // 3. Source ou entité du texte.
            Button { analyse.corriger(entite) { $0.source = !entite.source } } label: {
                Label(entite.source ? tr("Ce n’est pas une source") : tr("C’est une source (journal, site)"),
                      systemImage: "newspaper")
            }
            // 4. Un doublon.
            Button(action: memeQue) {
                Label(tr("C’est la même que…"), systemImage: "arrow.triangle.merge")
            }
            // 5. La photo.
            if entite.image != nil {
                Button { analyse.corriger(entite) { $0.sansImage = true } } label: {
                    Label(tr("Mauvaise photo"), systemImage: "photo.badge.exclamationmark")
                }
            }
            // 6. Pas une entité du tout.
            Button(role: .destructive) {
                analyse.corriger(entite) { $0.ignorer = true }
                retiree()
            } label: {
                Label(tr("Ce n’est pas une entité"), systemImage: "nosign")
            }
            if analyse.correction(entite) != nil {
                Divider()
                Button { analyse.oublierCorrections(entite) } label: {
                    Label(tr("Annuler mes corrections"), systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Label(tr("Signaler une erreur"), systemImage: "exclamationmark.bubble")
        }
    }
}

/// « Ce n'est pas la bonne fiche » : les fiches que Wikidata connaît pour ce nom, toutes, les plus
/// anciennes d'abord ; un autre terme peut être cherché (« palais de l'Élysée » pour « Elysée »).
struct ChoixFicheView: View {
    let entite: EntiteDocument
    @ObservedObject var analyse: AnalyseEntites

    @State private var terme = ""
    @State private var propositions: [WikidataCandidat] = []
    @State private var enCours = true
    @State private var erreur: String?
    @State private var choixEnCours: String?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = Localization.shared
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        analyse.retirerFiche(entite)
                        dismiss()
                    } label: {
                        Label(tr("Aucune ne convient"), systemImage: "xmark.circle")
                    }
                } footer: {
                    Text(tr("Le nom reste dans la liste, sans fiche. md Viewer ne la cherchera plus."))
                }
                Section {
                    if enCours {
                        HStack { ProgressView(); Text(tr("Recherche dans Wikidata…")).foregroundStyle(.secondary) }
                    } else if let erreur {
                        Label(erreur, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else if propositions.isEmpty {
                        Text(tr("Wikidata ne connaît aucune fiche à ce nom.")).foregroundStyle(.secondary)
                    }
                    ForEach(propositions, id: \.id) { c in
                        Button { choisir(c) } label: { ligne(c) }
                            .buttonStyle(.plain)
                            .disabled(choixEnCours != nil)
                    }
                } header: {
                    Text(tr("Fiches Wikidata"))
                }
            }
            .searchable(text: $terme, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(tr("Chercher un autre nom")))
            .onSubmit(of: .search) { Task { await chercher() } }
            .navigationTitle(entite.nom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Annuler")) { dismiss() }.tint(orange) }
            }
            .task { await chercher() }
        }
    }

    private func ligne(_ c: WikidataCandidat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.label).font(.body.weight(.semibold))
                if let d = c.description, !d.isEmpty {
                    Text(d).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(c.id).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if choixEnCours == c.id {
                ProgressView()
            } else if c.id == entite.qid {
                Text(tr("actuelle")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func chercher() async {
        enCours = true
        erreur = nil
        defer { enCours = false }
        do {
            let t = terme.trimmingCharacters(in: .whitespaces)
            propositions = try await analyse.propositions(pour: entite, terme: t.isEmpty ? nil : t)
        } catch {
            propositions = []
            self.erreur = tr("Wikidata ne répond pas.")
        }
    }

    private func choisir(_ c: WikidataCandidat) {
        choixEnCours = c.id
        Task {
            do {
                try await analyse.choisirFiche(c, pour: entite)
                dismiss()
            } catch {
                erreur = tr("Wikidata ne répond pas.")
                choixEnCours = nil
            }
        }
    }
}

/// « C'est la même que… » : les autres entités du document. Le nom choisi reprend les mentions
/// de celui-ci, dans ce document et dans les suivants.
struct ChoixMemeEntiteView: View {
    let entite: EntiteDocument
    @ObservedObject var analyse: AnalyseEntites
    /// L'entité a rejoint une autre : une fiche ouverte se referme.
    var reunie: () -> Void = {}

    @State private var filtre = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = Localization.shared
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    private var autres: [EntiteDocument] {
        let l = analyse.entites.filter { $0.id != entite.id }
        let f = EntiteDocument.cle(filtre)
        return f.isEmpty ? l : l.filter { $0.id.contains(f) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(autres) { e in
                        Button {
                            analyse.corriger(entite) { $0.memeQue = e.nom }
                            dismiss()
                            reunie()
                        } label: {
                            HStack(spacing: 12) {
                                VignetteEntite(entite: e, taille: 32)
                                Text(e.nom)
                                Spacer(minLength: 8)
                                if e.mentions > 1 { PastilleMentions(n: e.mentions) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(tr("« %@ » sera réunie à l’entité choisie, ici et dans les autres documents.", entite.nom))
                }
            }
            .searchable(text: $filtre, prompt: Text(tr("Filtrer")))
            .navigationTitle(tr("C’est la même que…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Annuler")) { dismiss() }.tint(orange) }
            }
        }
    }
}
