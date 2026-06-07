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
                ReaderView(document: doc, onOpen: { showImporter = true })
            } else {
                EmptyStateView(
                    recents: store.recents.items,
                    onOpen: { showImporter = true },
                    onSample: { store.openSample() },
                    onRecent: { store.openRecent($0) },
                    onRemoveRecent: { store.recents.remove($0) }
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
    }
}
