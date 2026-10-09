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

    @State private var showAbout = false
    @State private var showSettings = false
    @ObservedObject private var loc = Localization.shared

    private var recents: [RecentFile] { recentsStore.items }
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        // L'allure d'une app, pas d'une page : la barre du système porte les actions, et les
        // fichiers sont des listes groupées — la maison du Mac, de l'iPad et de l'iPhone.
        NavigationStack {
            List {
                if recents.isEmpty && !vault.hasFolder {
                    accueilVide
                }
                ForEach(Array(groupesRecents.enumerated()), id: \.element.id) { rang, groupe in
                    Section {
                        ForEach(groupe.elements) { item in ligneRecente(item) }
                            .onDelete { positions in positions.map { groupe.elements[$0] }.forEach(recentsStore.remove) }
                    } header: {
                        Text(rang == 0 ? tr("Récents") + " · " + groupe.titre : groupe.titre)
                    }
                }
                VaultSectionView(vault: vault, onPick: onPickVault, onOpen: onOpenVault)
                Section {
                    EmptyView()
                } footer: {
                    signature
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("md Viewer")
            .toolbar { barreAccueil }
        }
        .onAppear { vault.refresh() }
        .sheet(isPresented: $showAbout) { AboutLibrariesView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
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
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onSample) { Image(systemName: "doc.text.image") }
                .teinteBarre()
                .accessibilityLabel(tr("Voir un exemple"))
            Button(action: onOpen) { Image(systemName: "folder") }
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

    private func ligneRecente(_ item: RecentFile) -> some View {
        Button { onRecent(item) } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(DecoupageParDate.mention(pour: item.openedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
