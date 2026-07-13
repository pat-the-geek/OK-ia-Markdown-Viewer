import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var showImporter = false
    /// Which kind of item the single importer is currently picking.
    /// SwiftUI does not reliably support two `.fileImporter`s on one view, so we
    /// drive both the file-open and the vault-folder pickers through one importer.
    @State private var importFolder = false

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
                           onOpen: { importFolder = false; showImporter = true },
                           onHome: { store.document = nil })
            } else {
                EmptyStateView(
                    recentsStore: store.recents,
                    vault: store.vault,
                    onOpen: { importFolder = false; showImporter = true },
                    onSample: { store.openSample() },
                    onRecent: { store.openRecent($0) },
                    onPickVault: { importFolder = true; showImporter = true },
                    onOpenVault: { store.openVaultReport($0) }
                )
            }
        }
        // One importer for both modes — `importFolder` selects file vs. vault folder.
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importFolder ? [.folder] : RootView.importedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if importFolder { store.vault.setFolder(url) } else { store.open(url: url) }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .alert(tr("Erreur", "Error"),
               isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        // macOS: File ▸ Open (⌘O) menu command.
        .onReceive(NotificationCenter.default.publisher(for: .okiaOpenFile)) { _ in
            importFolder = false
            showImporter = true
        }
        // macOS: auto-open new reports landing in the vault folder.
        .task { store.startVaultWatch() }
        .onChange(of: store.vault.folderName) { _, _ in store.startVaultWatch() }
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
                windowScene.title = "md Viewer"
                #if DEBUG
                // Screenshot harness: pin the window to a fixed size for pixel-exact captures.
                if ProcessInfo.processInfo.environment["OKIA_SHOT_SIZE"] != nil {
                    let fixed = CGSize(width: 1360, height: 860)
                    windowScene.sizeRestrictions?.minimumSize = fixed
                    windowScene.sizeRestrictions?.maximumSize = fixed
                }
                #endif
            }
        }
        #endif
    }
}
