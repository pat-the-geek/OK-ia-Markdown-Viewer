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

    /// Reopens a previously stored recent file.
    func openRecent(_ item: RecentFile) {
        guard let url = recents.resolve(item) else {
            errorMessage = "Ce fichier n’est plus accessible."
            recents.remove(item)
            return
        }
        open(url: url)
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
                // Handles both cold launch (file passed at startup) and warm "Open in…".
                .onOpenURL { url in
                    store.open(url: url)
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
