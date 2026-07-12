import SwiftUI
import AppIntents

extension Notification.Name {
    /// Posted by the macOS File ▸ Open menu command; observed by RootView.
    static let okiaOpenFile = Notification.Name("okia.openFile")
}

/// Holds the currently displayed document and any load error.
@MainActor
final class DocumentStore: ObservableObject {
    @Published var document: MarkdownDocument?
    @Published var errorMessage: String?
    /// Set by an App Intent to ask the reader to present the Apple Intelligence summary.
    @Published var summaryRequested = false

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
            errorMessage = tr("Lien invalide.", "Invalid link."); return
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
                errorMessage = tr("URL du rapport manquante ou invalide (https requis).",
                                  "Missing or invalid report URL (https required).")
            }
        case "render", "content":
            let name = value("name", "title") ?? tr("Rapport.md", "Report.md")
            if let content = value("content", "text"), !content.isEmpty {
                document = MarkdownDocument(filename: sanitize(name), text: content)
                errorMessage = nil
            } else {
                errorMessage = tr("Contenu du rapport manquant.", "Missing report content.")
            }
        default:
            errorMessage = tr("Action inconnue : « \(action) ».", "Unknown action: “\(action)”.")
        }
    }

    /// Downloads a remote Markdown report (HTTPS) and renders it.
    func openRemote(_ url: URL) {
        let name = url.lastPathComponent.isEmpty ? tr("Rapport.md", "Report.md") : url.lastPathComponent
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.errorMessage = tr("Le serveur a répondu \(http.statusCode) pour le rapport.",
                                           "The server answered \(http.statusCode) for the report.")
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
                    self.errorMessage = tr("Impossible de télécharger le rapport (\(error?.localizedDescription ?? "réseau")).",
                                           "The report could not be downloaded (\(error?.localizedDescription ?? "network")).")
                }
            }
        }.resume()
    }

    private func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? tr("Rapport.md", "Report.md") : cleaned
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
            errorMessage = tr("Ce fichier n’est plus accessible.", "This file is no longer accessible.")
            recents.remove(item)
            return
        }
        open(url: url)
    }

    /// Opens a report from the watched vault folder (downloading from iCloud if needed).
    func openVaultReport(_ report: VaultReport) {
        guard let folder = vault.resolveFolder() else {
            errorMessage = tr("Le dossier du coffre n’est plus accessible.",
                              "The vault folder is no longer accessible."); return
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let fileURL = folder.appendingPathComponent(report.subfolder).appendingPathComponent(report.name)
        // Materialise an iCloud placeholder if needed (NSFileCoordinator in the loader also handles this).
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        }
        do {
            document = try MarkdownLoader.load(from: fileURL)
            recents.add(url: fileURL)
            errorMessage = nil
        } catch {
            errorMessage = tr("Impossible d’ouvrir « \(report.name) » (synchronisation iCloud en cours ?).",
                              "Could not open “\(report.name)” (iCloud sync in progress?).")
        }
    }

    // MARK: - App Intents support

    /// Open a vault report by its entity id ("subfolder/name").
    func openReport(id: String) {
        vault.refresh()
        if let report = vault.reports.first(where: { $0.id == id }) {
            openVaultReport(report)
        } else {
            errorMessage = tr("Rapport introuvable dans le coffre.", "Report not found in the vault.")
        }
    }

    /// Open the most recent vault report.
    func openLatestReport() {
        vault.refresh()
        if let report = vault.reports.first {
            openVaultReport(report)
        } else {
            errorMessage = tr("Aucun rapport dans le coffre.", "No report in the vault.")
        }
    }

    /// Open a report then ask the reader to summarise it with Apple Intelligence.
    func openReportAndSummarize(id: String) {
        openReport(id: id)
        if document != nil { summaryRequested = true }
    }

    func openSample() {
        guard let url = Bundle.main.url(forResource: "Demo", withExtension: "md", subdirectory: "Samples")
            ?? Bundle.main.url(forResource: "Demo", withExtension: "md") else {
            errorMessage = tr("Exemple introuvable dans le bundle.", "Sample not found in the bundle.")
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
    @StateObject private var store: DocumentStore

    init() {
        let store = DocumentStore()
        _store = StateObject(wrappedValue: store)
        // Share the running store with App Intents (Siri / Spotlight / Shortcuts).
        AppDependencyManager.shared.add(dependency: store)
    }

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
            // macOS: replace the default "New" with "Ouvrir…" / "Open…" (⌘O).
            CommandGroup(replacing: .newItem) {
                Button(tr("Ouvrir…", "Open…")) {
                    NotificationCenter.default.post(name: .okiaOpenFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

// MARK: - App Intents (Siri · Spotlight · Raccourcis · Apple Intelligence)

/// A vault report exposed to Shortcuts/Siri so it can be picked as a parameter.
struct VaultReportEntity: AppEntity, Identifiable {
    let id: String          // "subfolder/name"
    let name: String
    let subfolder: String

    init(_ r: VaultReport) { id = r.id; name = r.name; subfolder = r.subfolder }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Rapport" }
    static var defaultQuery = VaultReportQuery()

    var displayRepresentation: DisplayRepresentation {
        let title = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        return DisplayRepresentation(title: "\(title)", subtitle: "\(subfolder)")
    }
}

/// Lists/searches vault reports for the entity picker. Reads the vault directly
/// (from the shared bookmark) so it also works while configuring a shortcut.
struct VaultReportQuery: EntityQuery, EntityStringQuery {
    @MainActor private func allReports() -> [VaultReport] {
        let vault = VaultStore()
        vault.refresh()
        return vault.reports
    }

    func entities(for identifiers: [String]) async throws -> [VaultReportEntity] {
        let reports = await allReports()
        return reports.filter { identifiers.contains($0.id) }.map(VaultReportEntity.init)
    }

    func suggestedEntities() async throws -> [VaultReportEntity] {
        let reports = await allReports()
        return reports.prefix(30).map(VaultReportEntity.init)
    }

    func entities(matching string: String) async throws -> [VaultReportEntity] {
        let needle = string.lowercased()
        let reports = await allReports()
        return reports.filter { $0.name.lowercased().contains(needle) }.map(VaultReportEntity.init)
    }
}

/// Open a chosen report in md Viewer.
struct OpenReportIntent: AppIntent {
    // App Intents metadata must be compile-time static; the English translations
    // live in Localizable.xcstrings (resolved by the system language).
    static var title: LocalizedStringResource = "Ouvrir un rapport"
    static var description = IntentDescription("Ouvre un rapport du coffre dans md Viewer.")
    static var openAppWhenRun = true

    @Parameter(title: "Rapport") var report: VaultReportEntity
    @Dependency var store: DocumentStore

    static var parameterSummary: some ParameterSummary { Summary("Ouvrir \(\.$report)") }

    @MainActor func perform() async throws -> some IntentResult {
        store.openReport(id: report.id)
        return .result()
    }
}

/// Open the most recent report.
struct OpenLatestReportIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir le dernier rapport"
    static var description = IntentDescription("Ouvre le rapport le plus récent du coffre.")
    static var openAppWhenRun = true

    @Dependency var store: DocumentStore

    @MainActor func perform() async throws -> some IntentResult {
        store.openLatestReport()
        return .result()
    }
}

/// Open a report and present its Apple Intelligence summary (gracefully degrades
/// when Apple Intelligence is unavailable).
struct SummarizeReportIntent: AppIntent {
    static var title: LocalizedStringResource = "Résumer un rapport"
    static var description = IntentDescription("Ouvre un rapport et génère son résumé sur l’appareil.")
    static var openAppWhenRun = true

    @Parameter(title: "Rapport") var report: VaultReportEntity
    @Dependency var store: DocumentStore

    static var parameterSummary: some ParameterSummary { Summary("Résumer \(\.$report)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if DocumentSummarizer.isAvailable {
            store.openReportAndSummarize(id: report.id)
            return .result(dialog: "Résumé de « \(report.name) » dans md Viewer.")
        } else {
            store.openReport(id: report.id)
            return .result(dialog: "Le résumé n’est pas disponible sur cet appareil ; j’ouvre le rapport.")
        }
    }
}

/// Auto-registers spoken phrases in Siri / Spotlight / the Shortcuts app.
struct MdViewerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenLatestReportIntent(),
                    phrases: ["Ouvre le dernier rapport dans \(.applicationName)",
                              "Dernier rapport \(.applicationName)",
                              "Open the latest report in \(.applicationName)",
                              "Latest report \(.applicationName)"],
                    shortTitle: "Dernier rapport",
                    systemImageName: "doc.text")
        AppShortcut(intent: SummarizeReportIntent(),
                    phrases: ["Résume un rapport dans \(.applicationName)",
                              "Résumé \(.applicationName)",
                              "Summarise a report in \(.applicationName)",
                              "Summarize a report in \(.applicationName)"],
                    shortTitle: "Résumer un rapport",
                    systemImageName: "sparkles")
        AppShortcut(intent: OpenReportIntent(),
                    phrases: ["Ouvre un rapport dans \(.applicationName)",
                              "Open a report in \(.applicationName)"],
                    shortTitle: "Ouvrir un rapport",
                    systemImageName: "folder")
    }
}
