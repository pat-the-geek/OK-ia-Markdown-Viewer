import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var showImporter = false
    /// Which kind of item the single importer is currently picking.
    /// SwiftUI does not reliably support two `.fileImporter`s on one view, so we
    /// drive both the file-open and the vault-folder pickers through one importer.
    @State private var importFolder = false
    /// Le même sélecteur, pour un document Word, PDF ou PowerPoint à importer (Mac, Analytic).
    @State private var importOffice = false
    /// L'import demandé sans l'option : on la présente.
    @State private var vitrineImport = false
    @ObservedObject private var achat = AchatAnalytic.partage

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
                           onOpen: { importFolder = false; importOffice = false; showImporter = true },
                           onHome: { store.document = nil })
            } else {
                EmptyStateView(
                    recentsStore: store.recents,
                    vault: store.vault,
                    onOpen: { importFolder = false; importOffice = false; showImporter = true },
                    onSample: { store.openSample() },
                    onRecent: { store.openRecent($0) },
                    onPickVault: { importFolder = true; importOffice = false; showImporter = true },
                    onOpenVault: { store.openVaultReport($0) }
                )
            }
        }
        // One importer for both modes — `importFolder` selects file vs. vault folder.
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importFolder ? [.folder] : importOffice ? ImportEnCours.types : RootView.importedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if importFolder { store.vault.setFolder(url) }
                else if importOffice { store.importer(url: url) }
                else { store.open(url: url) }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .alert(tr("Erreur"),
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
            importOffice = false
            showImporter = true
        }
        // macOS : Fichier ▸ Importer Word, PDF ou PowerPoint (⇧⌘I), réservé à l'option Analytic.
        .onReceive(NotificationCenter.default.publisher(for: .okiaImporter)) { _ in
            guard achat.acces else { vitrineImport = true; return }
            importFolder = false
            importOffice = true
            showImporter = true
        }
        .sheet(item: $store.importEnCours) { i in
            ImportView(import_: i, annuler: { store.annulerImport() })
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $vitrineImport) {
            ScrollView { OptionAnalyticView().padding(24) }
                .frame(minWidth: 460, minHeight: 520)
        }
        // macOS: auto-open new reports landing in the vault folder.
        .task { store.startVaultWatch() }
        .onChange(of: store.vault.folderName) { _, _ in store.startVaultWatch() }
        // Drag a .md from Finder onto the window to open it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            // Un Word, un PDF, un PowerPoint déposé s'importe — avec l'option, sur Mac.
            if ImportEnCours.estImportable(url) {
                #if targetEnvironment(macCatalyst)
                if achat.acces { store.importer(url: url) } else { vitrineImport = true }
                return true
                #else
                return false
                #endif
            }
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
                // Harnais de capture : fenêtre figée, pour une capture aux pixels près.
                // La valeur donne la taille en points, « 1660x1036 » — l'écran de capture
                // décide de ce qui tient, et un point ne vaut pas partout le même nombre de
                // pixels. Sans valeur lisible, on garde l'ancienne taille.
                if let demande = ProcessInfo.processInfo.environment["OKIA_SHOT_SIZE"] {
                    let parts = demande.split(separator: "x").compactMap { Double($0) }
                    let fixed = parts.count == 2 ? CGSize(width: parts[0], height: parts[1])
                                                 : CGSize(width: 1360, height: 860)
                    windowScene.sizeRestrictions?.minimumSize = fixed
                    windowScene.sizeRestrictions?.maximumSize = fixed
                }
                #endif
            }
        }
        #endif
    }
}
