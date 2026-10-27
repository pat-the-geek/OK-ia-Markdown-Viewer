import SwiftUI

/// Option Analytic (1.4) — l'analyse de tout le coffre (`AnalyseCoffre`) : les entités de tous les
/// rapports, les plus répandues d'abord, et leur carte. Une entité ouvre ses documents et les noms
/// qui l'accompagnent le plus souvent.
struct AnalyseCoffreView: View {
    @ObservedObject var vault: VaultStore
    /// Ouvre un rapport du coffre (la feuille se ferme).
    var ouvrir: (VaultReport) -> Void
    @ObservedObject private var analyse = AnalyseCoffre.partage
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss
    @State private var vue: Vue = .entites
    @State private var recherche = ""
    @State private var genre: TypeEntite?
    @State private var chemin: [AnalyseCoffre.EntiteCoffre] = []
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    enum Vue: String, CaseIterable, Identifiable {
        case entites, carte
        var id: String { rawValue }
        var libelle: String { self == .entites ? tr("Entités") : tr("Carte") }
    }

    var body: some View {
        NavigationStack(path: $chemin) {
            Group {
                switch vue {
                case .entites: liste
                case .carte: carte
                }
            }
            .navigationTitle(tr("Analyse du coffre"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { barre }
            .safeAreaInset(edge: .top, spacing: 0) { resume }
            .navigationDestination(for: AnalyseCoffre.EntiteCoffre.self) { e in
                DetailEntiteCoffre(entite: e, vault: vault, ouvrir: { r in dismiss(); ouvrir(r) })
            }
        }
        .onAppear { analyse.analyser(vault) }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 640, minHeight: 620)
        #endif
    }

    @ToolbarContentBuilder private var barre: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(tr("Fermer")) { dismiss() }
        }
        ToolbarItem(placement: .principal) {
            Picker(tr("Affichage"), selection: $vue) {
                ForEach(Vue.allCases) { v in Text(v.libelle).tag(v) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(tr("Genre"), selection: $genre) {
                    Text(tr("Tous les genres")).tag(TypeEntite?.none)
                    ForEach(genresPresents, id: \.self) { t in
                        Label(tr(t.libelle), systemImage: t.symbole).tag(TypeEntite?.some(t))
                    }
                }
                Divider()
                Button { analyse.oublier(); analyse.analyser(vault) } label: {
                    Label(tr("Relire tout le coffre"), systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: genre == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .tint(orange)
            .accessibilityLabel(tr("Filtrer"))
        }
    }

    /// Ce que l'analyse couvre, et où elle en est.
    private var resume: some View {
        VStack(spacing: 6) {
            if case .lecture(let fait, let total) = analyse.etat {
                ProgressView(value: Double(fait), total: Double(max(total, 1))) {
                    Text(tr("Lecture des documents… %d sur %d", fait, total)).font(.caption)
                }
                .tint(orange)
            }
            HStack {
                Text(tr("%d documents", analyse.nombreDocuments) + " · " + tr("%d entités", analyse.entites.count))
                if analyse.nonTelecharges > 0 {
                    Text("· " + tr("%d dans iCloud, pas téléchargés", analyse.nonTelecharges))
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var genresPresents: [TypeEntite] {
        let presents = Set(analyse.entites.map(\.entite.type))
        return TypeEntite.allCases.filter { presents.contains($0) }
    }

    private var filtrees: [AnalyseCoffre.EntiteCoffre] {
        let q = recherche.trimmingCharacters(in: .whitespaces)
        return analyse.entites.filter { e in
            (genre == nil || e.entite.type == genre)
                && (q.isEmpty || e.entite.nom.localizedCaseInsensitiveContains(q))
        }
    }

    @ViewBuilder private var liste: some View {
        if analyse.entites.isEmpty, analyse.etat == .fini {
            ContentUnavailableView(tr("Aucune entité"), systemImage: "person.2",
                                   description: Text(tr("Les rapports du coffre ne nomment encore personne.")))
        } else {
            List(filtrees) { e in
                NavigationLink(value: e) { LigneEntiteCoffre(entite: e) }
            }
            .listStyle(.plain)
            .searchable(text: $recherche, prompt: tr("Chercher un nom"))
        }
    }

    @ViewBuilder private var carte: some View {
        let situees = analyse.situees.filter { genre == nil || $0.type == genre }
        if situees.isEmpty {
            ContentUnavailableView(tr("Aucun lieu situé"), systemImage: "map",
                                   description: Text(tr("Aucune entité du coffre n’a de position. Les fiches Wikidata déjà trouvées en donnent.")))
        } else {
            CarteWebView(cfg: AnalyseEntites.configurationCarte(situees),
                         surMarqueur: { nom in if let e = analyse.entite(nommee: nom) { chemin.append(e) } },
                         sousBoutonFermer: false)
                .overlay(alignment: .bottomLeading) {
                    Text(tr("%d lieux sur la carte", situees.count))
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                        .padding(12)
                        .padding(.bottom, EntitesView.margeSources)
                }
        }
    }
}

/// Une ligne : la vignette, le nom, combien de documents et depuis quand.
private struct LigneEntiteCoffre: View {
    let entite: AnalyseCoffre.EntiteCoffre

    var body: some View {
        HStack(spacing: 12) {
            VignetteEntite(entite: entite.entite, taille: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(entite.entite.nom).font(.body.weight(.medium)).lineLimit(1)
                Text(tr("%d documents", entite.presences.count) + " · "
                     + tr("depuis le %@", entite.premiere.formatted(date: .abbreviated, time: .omitted)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            PastilleMentions(n: entite.mentions)
        }
    }
}

/// Une entité du coffre : sa fiche, ses documents (du plus récent au plus ancien), et les noms qui
/// l'accompagnent le plus souvent.
private struct DetailEntiteCoffre: View {
    let entite: AnalyseCoffre.EntiteCoffre
    @ObservedObject var vault: VaultStore
    var ouvrir: (VaultReport) -> Void
    @ObservedObject private var analyse = AnalyseCoffre.partage

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    VignetteEntite(entite: entite.entite, taille: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr(entite.entite.type.libelle)).font(.caption).foregroundStyle(.secondary)
                        if let d = entite.entite.description, !d.isEmpty {
                            Text(d).font(.subheadline)
                        }
                        Text(tr("Du %@ au %@",
                                entite.premiere.formatted(date: .abbreviated, time: .omitted),
                                entite.derniere.formatted(date: .abbreviated, time: .omitted)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section(tr("Documents") + " · \(entite.presences.count)") {
                ForEach(entite.presences) { p in
                    Button { if let r = vault.reports.first(where: { $0.id == p.document }) { ouvrir(r) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.nom).lineLimit(2)
                                Text(p.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            PastilleMentions(n: p.mentions)
                        }
                    }
                    .tint(.primary)
                }
            }
            let compagnons = analyse.compagnons(de: entite)
            if !compagnons.isEmpty {
                Section(tr("Souvent avec")) {
                    ForEach(compagnons, id: \.0.id) { autre, communs in
                        NavigationLink(value: autre) {
                            HStack(spacing: 12) {
                                VignetteEntite(entite: autre.entite, taille: 30)
                                Text(autre.entite.nom)
                                Spacer()
                                Text(tr("%d documents", communs)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(entite.entite.nom)
    }
}
