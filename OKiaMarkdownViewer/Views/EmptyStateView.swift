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
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "flowchart")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(orange)

                VStack(spacing: 6) {
                    Text("OK-ia Markdown Viewer")
                        .font(.system(size: 25, weight: .heavy))
                    Text(tr("Ce que les algorithmes ignorent encore.",
                            "What the algorithms still miss."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Button(action: onOpen) {
                        Label(tr("Ouvrir un fichier", "Open a file"), systemImage: "folder")
                            .font(.headline)
                            .frame(maxWidth: 280)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(orange)

                    Button(action: onSample) {
                        Label(tr("Voir un exemple", "View a sample"), systemImage: "doc.text")
                            .frame(maxWidth: 280)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(orange)
                }

                if !recents.isEmpty {
                    recentsSection
                }

                VaultSectionView(vault: vault, onPick: onPickVault, onOpen: onOpenVault)

                Spacer(minLength: 24)

                HStack(spacing: 20) {
                    Button { showSettings = true } label: {
                        Label(tr("Réglages", "Settings"), systemImage: "gearshape")
                            .font(.footnote)
                    }
                    Button { showAbout = true } label: {
                        Label(tr("Librairies & licences", "Libraries & licenses"),
                              systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Image("OKiaWideLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72)
                    .opacity(0.7)
                    .accessibilityLabel("OK-ia")
                    .padding(.bottom, 16)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
        }
        .onAppear { vault.refresh() }
        .sheet(isPresented: $showAbout) { AboutLibrariesView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Récents", "Recent"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(recents) { item in
                    Button { onRecent(item) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.isRemote ? "arrow.down.doc" : "doc.richtext")
                                .foregroundStyle(orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(item.openedAt, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { recentsStore.remove(item) } label: {
                            Label(tr("Retirer de la liste", "Remove from list"), systemImage: "trash")
                        }
                    }
                    if item.id != recents.last?.id { Divider().padding(.leading, 44) }
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: 480)
        .padding(.top, 8)
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
            case .offline: return tr("Hors-ligne", "Offline")
            case .network: return tr("En ligne", "Online")
            case .system:  return tr("Système", "System")
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
                    role: tr("Conversion Markdown → HTML (le cœur du rendu).",
                             "Markdown → HTML conversion (the heart of the renderer)."),
                    license: "MIT", availability: .offline,
                    url: URL(string: "https://marked.js.org")),
        LibraryInfo(name: "Mermaid", version: "11.15.0",
                    role: tr("Diagrammes : flowchart, séquence, gantt, pie, mindmap.",
                             "Diagrams: flowchart, sequence, gantt, pie, mindmap."),
                    license: "MIT", availability: .offline,
                    url: URL(string: "https://mermaid.js.org")),
        LibraryInfo(name: "Leaflet", version: "1.9.4",
                    role: tr("Cartes géographiques interactives et marqueurs (blocs ```leaflet).",
                             "Interactive maps and markers (```leaflet blocks)."),
                    license: "BSD-2-Clause", availability: .offline,
                    url: URL(string: "https://leafletjs.com")),
        LibraryInfo(name: "OpenStreetMap & CARTO", version: nil,
                    role: tr("Fonds de carte (tuiles) affichés par Leaflet.",
                             "Base map tiles displayed by Leaflet."),
                    license: "ODbL · CC BY", availability: .network,
                    url: URL(string: "https://www.openstreetmap.org/copyright")),
        LibraryInfo(name: "Nunito", version: nil,
                    role: tr("Police d'affichage des titres (charte OK-ia).",
                             "Display typeface for headings (OK-ia brand)."),
                    license: "SIL OFL 1.1", availability: .offline,
                    url: URL(string: "https://fonts.google.com/specimen/Nunito")),
        LibraryInfo(name: "WebKit · WKWebView", version: nil,
                    role: tr("Moteur web qui exécute le pipeline de rendu.",
                             "Web engine running the rendering pipeline."),
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
                    Text(tr("Librairies utilisées", "Libraries used"))
                } footer: {
                    Text(tr("Le rendu Markdown, les diagrammes et les cartes fonctionnent **100 % hors-ligne** — seules les tuiles de fond de carte nécessitent une connexion.",
                            "Markdown rendering, diagrams and maps work **100% offline** — only the base map tiles need a connection."))
                        .padding(.top, 4)
                }
            }
            .navigationTitle(tr("Librairies & licences", "Libraries & licenses"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Fermer", "Done")) { dismiss() }
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
                        Label(tr("Site", "Website"), systemImage: "arrow.up.right.square")
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
