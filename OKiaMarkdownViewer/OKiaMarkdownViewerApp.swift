import SwiftUI

extension Notification.Name {
    /// Posted by the macOS File ▸ Open menu command; observed by RootView.
    static let okiaOpenFile = Notification.Name("okia.openFile")
}

/// Holds the currently displayed document and any load error.
@MainActor
final class DocumentStore: ObservableObject {
    @Published var document: MarkdownDocument?
    @Published var errorMessage: String?

    let recents = RecentFilesStore()
    let vault = VaultStore()

    #if targetEnvironment(macCatalyst)
    private lazy var vaultWatcher = VaultWatcher(vault: vault) { [weak self] report in
        self?.openVaultReport(report)
    }
    /// macOS: begin (or restart) watching the vault folder for newly arrived reports.
    func startVaultWatch() { vaultWatcher.start() }
    #else
    func startVaultWatch() {}
    #endif

    /// Entry point for every incoming URL: custom scheme (mdviewer://) or a file URL.
    func handleIncoming(_ url: URL) {
        if url.scheme?.lowercased() == "mdviewer" {
            handleScheme(url)
        } else {
            open(url: url)
        }
    }

    /// mdviewer://open?url=<https .md>   — fetch a remote report and render it
    /// mdviewer://render?name=<f>&content=<percent-encoded markdown>  — render inline
    private func handleScheme(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            errorMessage = "Lien invalide."; return
        }
        let action = (comps.host ?? "").lowercased()
        func value(_ names: String...) -> String? {
            for n in names { if let v = comps.queryItems?.first(where: { $0.name == n })?.value { return v } }
            return nil
        }
        switch action {
        case "open", "url":
            if let s = value("url", "u"), let remote = URL(string: s), remote.scheme?.hasPrefix("http") == true {
                openRemote(remote)
            } else {
                errorMessage = "URL du rapport manquante ou invalide (https requis)."
            }
        case "render", "content":
            let name = value("name", "title") ?? "Rapport.md"
            if let content = value("content", "text"), !content.isEmpty {
                document = MarkdownDocument(filename: sanitize(name), text: content)
                errorMessage = nil
            } else {
                errorMessage = "Contenu du rapport manquant."
            }
        default:
            errorMessage = "Action inconnue : « \(action) »."
        }
    }

    /// Downloads a remote Markdown report (HTTPS) and renders it.
    func openRemote(_ url: URL) {
        let name = url.lastPathComponent.isEmpty ? "Rapport.md" : url.lastPathComponent
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.errorMessage = "Le serveur a répondu \(http.statusCode) pour le rapport."
                    return
                }
                if let data, error == nil {
                    let safeName = self.sanitize(name)
                    self.document = MarkdownDocument(filename: safeName,
                                                     text: MarkdownLoader.decode(data),
                                                     sourceURL: url)
                    self.recents.addRemote(url: url, name: safeName)
                    self.errorMessage = nil
                } else {
                    self.errorMessage = "Impossible de télécharger le rapport (\(error?.localizedDescription ?? "réseau"))."
                }
            }
        }.resume()
    }

    private func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "Rapport.md" : cleaned
    }

    /// Opens a user-selected file (importer / open-in / cold launch) and remembers it.
    func open(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            document = try MarkdownLoader.load(from: url)
            recents.add(url: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reopens a previously stored recent entry (local file or remote report).
    func openRecent(_ item: RecentFile) {
        if let remote = item.remoteURLString, let url = URL(string: remote) {
            openRemote(url)
            return
        }
        guard let url = recents.resolve(item) else {
            errorMessage = "Ce fichier n’est plus accessible."
            recents.remove(item)
            return
        }
        open(url: url)
    }

    /// Opens a report from the watched vault folder (downloading from iCloud if needed).
    func openVaultReport(_ report: VaultReport) {
        guard let folder = vault.resolveFolder() else {
            errorMessage = "Le dossier du coffre n’est plus accessible."; return
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let fileURL = folder.appendingPathComponent(report.name)
        // Materialise an iCloud placeholder if needed (NSFileCoordinator in the loader also handles this).
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        }
        do {
            document = try MarkdownLoader.load(from: fileURL)
            recents.add(url: fileURL)
            errorMessage = nil
        } catch {
            errorMessage = "Impossible d’ouvrir « \(report.name) » (synchronisation iCloud en cours ?)."
        }
    }

    func openSample() {
        guard let url = Bundle.main.url(forResource: "Demo", withExtension: "md", subdirectory: "Samples")
            ?? Bundle.main.url(forResource: "Demo", withExtension: "md") else {
            errorMessage = "Exemple introuvable dans le bundle."
            return
        }
        // Don't pollute recents with the bundled sample.
        do {
            document = try MarkdownLoader.load(from: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@main
struct OKiaMarkdownViewerApp: App {
    @StateObject private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                // Handles file URLs (cold + warm "Open in…") and the mdviewer:// scheme.
                .onOpenURL { url in
                    store.handleIncoming(url)
                }
        }
        .commands {
            // macOS: replace the default "New" with "Ouvrir…" (⌘O).
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir…") {
                    NotificationCenter.default.post(name: .okiaOpenFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
