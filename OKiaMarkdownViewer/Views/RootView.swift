import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var showImporter = false

    /// UTTypes we accept in the in-app importer.
    static let importedTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let md = UTType("net.daringfireball.markdown") { types.insert(md, at: 0) }
        if let mdAlt = UTType(filenameExtension: "md") { types.append(mdAlt) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        return types
    }()

    var body: some View {
        Group {
            if let doc = store.document {
                ReaderView(document: doc,
                           onOpen: { showImporter = true },
                           onHome: { store.document = nil })
            } else {
                EmptyStateView(
                    recentsStore: store.recents,
                    onOpen: { showImporter = true },
                    onSample: { store.openSample() },
                    onRecent: { store.openRecent($0) }
                )
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: RootView.importedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { store.open(url: url) }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .alert("Erreur",
               isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        // macOS: File ▸ Open (⌘O) menu command.
        .onReceive(NotificationCenter.default.publisher(for: .okiaOpenFile)) { _ in
            showImporter = true
        }
        // Drag a .md from Finder onto the window to open it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            store.open(url: url)
            return true
        }
        .onAppear(perform: configureMacWindow)
    }

    private func configureMacWindow() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                windowScene.sizeRestrictions?.minimumSize = CGSize(width: 480, height: 600)
                windowScene.title = "OK-ia - Markdown Viewer"
            }
        }
        #endif
    }
}
