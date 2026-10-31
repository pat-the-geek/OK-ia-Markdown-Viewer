import SwiftUI

/// Shown when no document is loaded: OK-ia branded landing with open + sample
/// actions and a list of recently opened files.
struct EmptyStateView: View {
    @ObservedObject var recentsStore: RecentFilesStore
    @ObservedObject var vault: VaultStore
    var onOpen: () -> Void
    var onSample: () -> Void
    var onRecent: (RecentFile) -> Void
    var onPickVault: () -> Void
    var onOpenVault: (VaultReport) -> Void
    /// Un document analysé (option Analytic, 1.4) : « Documents analysés », à part du coffre.
    var onOpenAnalyse: (URL) -> Void = { _ in }

    @State private var showAbout = false
    @State private var analyses: [DocumentsAnalysesSection.DocumentAnalyse] = []
    /// La lecture des documents analysés en cours : seule la dernière demandée remplit la liste.
    @State private var lectureAnalyses = 0
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var achat = AchatAnalytic.partage
    @EnvironmentObject private var store: DocumentStore
    @State private var showSettings = false
    /// L'accueil montre des cartes avec vignettes, sauf aux tailles de texte d'accessibilité.
    @Environment(\.dynamicTypeSize) private var tailleTexte
    /// Le document dont on demande la suppression, en attente de confirmation.
    @State private var aSupprimer: Suppression?
    @State private var erreurSuppression: String?
    @ObservedObject private var loc = Localization.shared
    /// Sur Mac, la taille des cartes et de leur texte (`TailleAccueil`).
    @AppStorage(TailleAccueil.cle) private var taille = 1.0

    struct Suppression: Identifiable {
        let nom: String
        /// Ce qui distingue deux documents du même nom : sa date (et, au coffre, son dossier).
        let precision: String
        let duCoffre: Bool
        let action: () throws -> Void
        let id = UUID()
    }

    private var recents: [RecentFile] { recentsStore.items }
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        // L'allure d'une app, pas d'une page : la barre du système porte les actions, et les
        // fichiers sont des listes groupées — la maison du Mac, de l'iPad et de l'iPhone.
        NavigationStack {
            // Les cartes hors d'une `List` : une rangée de cartes y est UNE ligne, et la liste ne
            // gardait qu'un menu contextuel pour toute la ligne, celui d'une seule carte — « Supprimer »
            // sur une carte supprimait sa voisine (Patrick, 31/10/2026, deux documents du même nom).
            Group {
                if enGrille {
                    ScrollView {
                        // Le premier en-tête, plus près du titre, comme dans la liste.
                        LazyVStack(alignment: .leading, spacing: 0) { sections }
                            .padding(.horizontal, 16)
                            .padding(.top, -19)
                            .padding(.bottom, 20)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                } else {
                    List { sections }
                        .listStyle(.insetGrouped)
                }
            }
            .modifier(TexteAccueil(taille: taille))
            .environment(\.accueilEnGrille, enGrille)
            .navigationTitle("md Viewer")
            .toolbar { barreAccueil }
        }
        .onAppear { vault.refresh() }
        // Les documents analysés, relus à chaque retour à l'accueil (un import vient peut-être d'y entrer).
        .task(id: achat.acces) { rechargerAnalyses() }
        .onAppear { rechargerAnalyses() }
        // Revenir à l'app (sur Mac, à sa fenêtre) relit aussi : un document a pu arriver d'ailleurs.
        .onChange(of: phase) { _, p in if p == .active { rechargerAnalyses() } }
        .confirmationDialog(tr("Supprimer « %@ » ?", aSupprimer?.nom ?? ""),
                            isPresented: Binding(get: { aSupprimer != nil }, set: { if !$0 { aSupprimer = nil } }),
                            titleVisibility: .visible, presenting: aSupprimer) { s in
            Button(tr("Supprimer"), role: .destructive) {
                do { try s.action() } catch { erreurSuppression = error.localizedDescription }
            }
            Button(tr("Annuler"), role: .cancel) {}
        } message: { s in
            Text(s.precision + "\n" + (s.duCoffre
                 ? tr("Le rapport est retiré du coffre « %@ », sur tous vos appareils.", vault.folderName ?? "")
                 : tr("Le document est retiré du dossier « Documents analysés », sur tous vos appareils.")))
        }
        .alert(tr("Impossible de supprimer le document."),
               isPresented: Binding(get: { erreurSuppression != nil }, set: { if !$0 { erreurSuppression = nil } })) {
            Button("OK") {}
        } message: {
            Text(erreurSuppression ?? "")
        }
        .sheet(isPresented: $showAbout) { AboutLibrariesView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// La date entière d'un document, dans la confirmation de sa suppression.
    private func dateComplete(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Localization.shared.locale).day().month(.abbreviated).year().hour().minute())
    }

    /// Les sections de l'accueil, les mêmes en cartes et en liste.
    @ViewBuilder private var sections: some View {
        if recents.isEmpty && !vault.hasFolder {
            accueilVide
        }
        ForEach(Array(groupesRecents.enumerated()), id: \.element.id) { rang, groupe in
            Section {
                if enGrille {
                    GrilleCartes { ForEach(groupe.elements) { item in carteRecente(item) } }
                } else {
                    ForEach(groupe.elements) { item in ligneRecente(item) }
                        .onDelete { positions in positions.map { groupe.elements[$0] }.forEach(recentsStore.remove) }
                }
            } header: {
                Text(rang == 0 ? tr("Récents") + " · " + groupe.titre : groupe.titre)
                    .foregroundStyle(.secondary)
                    .enTeteAccueil()
            }
        }
        DocumentsAnalysesSection(documents: analyses, ouvrir: onOpenAnalyse, supprimer: { d in
            aSupprimer = Suppression(nom: d.nom, precision: dateComplete(d.date), duCoffre: false) {
                RecentFilesStore.partage.retirer(url: d.url)
                try SuppressionDocument.supprimer(d.url)
                analyses.removeAll { $0.url == d.url }
                RechercheCoffre.partage.indexerSpotlight()
            }
        })
        VaultSectionView(vault: vault, onPick: onPickVault, onOpen: onOpenVault, onDelete: { r in
            aSupprimer = Suppression(nom: (r.name as NSString).deletingPathExtension,
                                     precision: r.subfolder + " · " + dateComplete(r.modified),
                                     duCoffre: true) {
                try vault.supprimer(r)
            }
        })
        Section {
            EmptyView()
        } footer: {
            signature
        }
    }

    @ToolbarContentBuilder private var barreAccueil: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { showSettings = true } label: { Label(tr("Réglages"), systemImage: "gearshape") }
                Button { showAbout = true } label: {
                    Label(tr("Librairies & licences"), systemImage: "info.circle")
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .teinteBarre()
            .accessibilityLabel(tr("Réglages"))
        }
        // Sur Mac : réduire et agrandir l'accueil, comme la taille des icônes du Finder.
        if TailleAccueil.surMac {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { taille = TailleAccueil.voisin(de: taille, plus: false) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .teinteBarre()
                .keyboardShortcut("-", modifiers: .command)
                .disabled(taille <= TailleAccueil.crans.first!)
                .accessibilityLabel(tr("Réduire l’affichage"))
                Button { taille = TailleAccueil.voisin(de: taille, plus: true) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .teinteBarre()
                .keyboardShortcut("+", modifiers: .command)
                .disabled(taille >= TailleAccueil.crans.last!)
                .accessibilityLabel(tr("Agrandir l’affichage"))
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        // Option Analytic (1.4) : la recherche et l'analyse de tout le coffre, en vue dans la barre
        // plutôt que dans les en-têtes des listes (Patrick, 28/10/2026 : « les mettre en valeur »).
        // Sans l'option, elles mènent à la vitrine.
        if !vault.reports.isEmpty || !analyses.isEmpty {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { NotificationCenter.default.post(name: .okiaRechercheCoffre, object: store) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .teinteBarre()
                .accessibilityLabel(tr("Rechercher dans le coffre"))
                Button { NotificationCenter.default.post(name: .okiaAnalyseCoffre, object: store) } label: {
                    Image(systemName: "chart.dots.scatter")
                }
                .teinteBarre()
                .accessibilityLabel(tr("Analyser le coffre"))
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onSample) { Image(systemName: "doc.text.image") }
                .teinteBarre()
                .accessibilityLabel(tr("Voir un exemple"))
            Menu {
                Button(action: onOpen) { Label(tr("Ouvrir un fichier"), systemImage: "folder") }
                Button { ImportEnCours.demander(pour: store) } label: {
                    Label(tr("Importer Word, PDF ou PowerPoint…"), systemImage: "square.and.arrow.down.on.square")
                }
            } label: {
                Image(systemName: "folder")
            } primaryAction: {
                onOpen()
            }
                .teinteBarre()
                .accessibilityLabel(tr("Ouvrir un fichier"))
        }
    }

    /// Rien d'ouvert encore : l'écran vide du système, avec les deux premiers gestes.
    private var accueilVide: some View {
        Section {
            ContentUnavailableView {
                Label("OK-ia Markdown Viewer", systemImage: "flowchart")
            } description: {
                Text(tr("Ce que les algorithmes ignorent encore."))
            } actions: {
                Button(tr("Ouvrir un fichier"), action: onOpen)
                    .buttonStyle(.borderedProminent)
                Button(tr("Voir un exemple"), action: onSample)
                // Option Analytic : un Word, un PDF, un PowerPoint devient un document md Viewer.
                Button(tr("Importer Word, PDF ou PowerPoint…")) { ImportEnCours.demander(pour: store) }
                    .font(.subheadline)
            }
            .tint(orange)
        }
        .listRowBackground(Color.clear)
    }

    /// La signature, au pied de la liste : la devise et le logo OK-ia.
    private var signature: some View {
        VStack(spacing: 8) {
            Image("OKiaWideLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64)
                .opacity(0.6)
                .accessibilityLabel("OK-ia")
            // La devise, sauf quand l'écran vide la porte déjà.
            if !(recents.isEmpty && !vault.hasFolder) {
                Text(tr("Ce que les algorithmes ignorent encore."))
                    .font(.caption)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    /// Les récents, découpés par date d'ouverture. Une liste de douze noms ne dit pas
    /// d'elle-même ce qui date d'aujourd'hui et ce qui remonte au mois dernier ; les
    /// intitulés le disent, et la mention de chaque ligne n'a plus qu'à préciser l'heure.
    private var groupesRecents: [GroupeDate<RecentFile>] {
        DecoupageParDate.grouper(recents, date: \.openedAt)
    }

    /// Les cartes partout, l'iPhone compris (Patrick, 28/10/2026 : « il faut utiliser des
    /// thumbnails aussi sur iPhone petit écran ») ; la liste revient aux tailles de texte
    /// d'accessibilité, où deux cartes côte à côte ne laissent plus lire les noms.
    private var enGrille: Bool { !tailleTexte.isAccessibilitySize }

    /// Un récent en carte : mêmes gestes que la ligne.
    private func carteRecente(_ item: RecentFile) -> some View {
        CarteDocument(nom: (item.name as NSString).deletingPathExtension,
                      mention: DecoupageParDate.mention(pour: item.openedAt),
                      resoudre: { recentsStore.resolve(item).map { ($0, $0) } },
                      action: { onRecent(item) }) {
            BoutonNouvelleFenetre {
                DocumentAOuvrir(nom: item.name, signet: item.bookmark, adresse: item.remoteURLString)
            }
            Button(role: .destructive) { recentsStore.remove(item) } label: {
                Label(tr("Retirer de la liste"), systemImage: "trash")
            }
        }
    }

    /// Relit les documents analysés. Au lancement, la liste restait vide sur Mac alors que la
    /// recherche les trouvait (Patrick, 30/10/2026 : pas de section « Documents analysés ») : une
    /// lecture partie avant les droits ou avant le conteneur iCloud ne trouvait rien, et rien ne la
    /// refaisait. Désormais la dernière lecture demandée l'emporte, et une liste vide alors qu'iCloud
    /// est là est relue un peu plus tard, le temps que le conteneur réponde.
    private func rechargerAnalyses() {
        lectureAnalyses += 1
        let lecture = lectureAnalyses
        Task {
            var lus = await DocumentsAnalysesSection.charger()
            var essai = 0
            while lus.isEmpty, essai < 3, achat.acces, FileManager.default.ubiquityIdentityToken != nil {
                essai += 1
                try? await Task.sleep(for: .seconds(2 * essai))
                guard lecture == lectureAnalyses else { return }
                lus = await DocumentsAnalysesSection.charger()
            }
            guard lecture == lectureAnalyses else { return }
            analyses = lus
        }
    }

    private func ligneRecente(_ item: RecentFile) -> some View {
        Button { onRecent(item) } label: {
            Label {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(DecoupageParDate.mention(pour: item.openedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    MarqueAnnoteeLigne(resoudre: { recentsStore.resolve(item).map { ($0, $0) } })
                }
            } icon: {
                Image(systemName: item.isRemote ? "arrow.down.doc" : "doc.richtext")
                    .foregroundStyle(orange)
            }
        }
        // Le nom en noir, l'icône seule en orange : un bouton de liste prendrait sinon la couleur
        // de l'app pour tout son libellé.
        .tint(.primary)
        .contextMenu {
            // Pour comparer (1.4) : le document dans une autre fenêtre, à côté de celle-ci.
            BoutonNouvelleFenetre {
                DocumentAOuvrir(nom: item.name, signet: item.bookmark, adresse: item.remoteURLString)
            }
            Button(role: .destructive) { recentsStore.remove(item) } label: {
                Label(tr("Retirer de la liste"), systemImage: "trash")
            }
        }
    }
}

// MARK: - À propos des librairies

/// One third-party component the viewer relies on.
private struct LibraryInfo: Identifiable {
    let id = UUID()
    let name: String
    let version: String?
    let role: String
    let license: String
    let availability: Availability
    let url: URL?

    enum Availability {
        case offline    // bundled in the app, works with no network
        case network    // needs a connection (map tiles)
        case system     // provided by the OS

        var label: String {
            switch self {
            case .offline: return tr("Hors-ligne")
            case .network: return tr("En ligne")
            case .system:  return tr("Système")
            }
        }
        var icon: String {
            switch self {
            case .offline: return "wifi.slash"
            case .network: return "wifi"
            case .system:  return "apple.logo"
            }
        }
    }
}

/// Information panel listing the libraries the viewer uses, with versions,
/// roles, licenses and whether they run offline. Presented as a sheet.
struct AboutLibrariesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = Localization.shared
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    private var libraries: [LibraryInfo] {
        [
        LibraryInfo(name: "marked", version: "18.0.5",
                    role: tr("Conversion Markdown → HTML (le cœur du rendu)."),
                    license: "MIT", availability: .offline,
                    url: URL(string: "https://marked.js.org")),
        LibraryInfo(name: "Mermaid", version: "11.15.0",
                    role: tr("Diagrammes : flowchart, séquence, gantt, pie, mindmap."),
                    license: "MIT", availability: .offline,
                    url: URL(string: "https://mermaid.js.org")),
        LibraryInfo(name: "Leaflet", version: "1.9.4",
                    role: tr("Cartes géographiques interactives et marqueurs (blocs ```leaflet)."),
                    license: "BSD-2-Clause", availability: .offline,
                    url: URL(string: "https://leafletjs.com")),
        LibraryInfo(name: "MapLibre GL JS", version: "5.24.0",
                    role: tr("Rendu des fonds de carte vectoriels."),
                    license: "BSD-3-Clause", availability: .offline,
                    url: URL(string: "https://maplibre.org")),
        LibraryInfo(name: "maplibre-gl-leaflet", version: "0.1.4",
                    role: tr("Liaison entre Leaflet et MapLibre."),
                    license: "ISC", availability: .offline,
                    url: URL(string: "https://github.com/maplibre/maplibre-gl-leaflet")),
        LibraryInfo(name: "OpenFreeMap & OpenStreetMap", version: nil,
                    role: tr("Fonds de carte (tuiles) affichés par Leaflet."),
                    license: "ODbL", availability: .network,
                    url: URL(string: "https://www.openstreetmap.org/copyright")),
        LibraryInfo(name: "Nunito", version: nil,
                    role: tr("Police d'affichage des titres (charte OK-ia)."),
                    license: "SIL OFL 1.1", availability: .offline,
                    url: URL(string: "https://fonts.google.com/specimen/Nunito")),
        LibraryInfo(name: "WebKit · WKWebView", version: nil,
                    role: tr("Moteur web qui exécute le pipeline de rendu."),
                    license: "Apple", availability: .system,
                    url: nil)
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(libraries) { lib in row(lib) }
                } header: {
                    Text(tr("Librairies utilisées"))
                } footer: {
                    Text(tr("Le rendu Markdown, les diagrammes et les cartes fonctionnent **100 % hors-ligne** — seules les tuiles de fond de carte nécessitent une connexion."))
                        .padding(.top, 4)
                }
            }
            .navigationTitle(tr("Librairies & licences"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Fermer")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ lib: LibraryInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(lib.name)
                    .font(.headline)
                if let v = lib.version {
                    Text("v\(v)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                availabilityBadge(lib.availability)
            }

            Text(lib.role)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label(lib.license, systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = lib.url {
                    Link(destination: url) {
                        Label(tr("Site"), systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .tint(orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func availabilityBadge(_ a: LibraryInfo.Availability) -> some View {
        Label(a.label, systemImage: a.icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor(a).opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor(a))
    }

    private func badgeColor(_ a: LibraryInfo.Availability) -> Color {
        switch a {
        case .offline: return .green
        case .network: return orange
        case .system:  return .secondary
        }
    }
}

/// Sur Mac, le texte de l'accueil suit la taille choisie ; ailleurs, celle du système.
private struct TexteAccueil: ViewModifier {
    let taille: Double

    func body(content: Content) -> some View {
        if TailleAccueil.surMac {
            content.dynamicTypeSize(TailleAccueil.texte(taille))
        } else {
            content
        }
    }
}
