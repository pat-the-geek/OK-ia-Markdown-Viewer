import SwiftUI

/// Holds the currently displayed document and any load error.
@MainActor
final class DocumentStore: ObservableObject {
    @Published var document: MarkdownDocument?
    @Published var errorMessage: String?

    func open(url: URL) {
        do {
            document = try MarkdownLoader.load(from: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSample() {
        guard let url = Bundle.main.url(forResource: "Demo", withExtension: "md", subdirectory: "Samples")
            ?? Bundle.main.url(forResource: "Demo", withExtension: "md") else {
            errorMessage = "Exemple introuvable dans le bundle."
            return
        }
        open(url: url)
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
    }
}
