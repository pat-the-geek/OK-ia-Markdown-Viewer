import SwiftUI
import UIKit

/// Wraps UIActivityViewController for sharing files (PDF export, original .md).
///
/// `enregistrer` (1.5.1) : sur Mac, un fichier exporté (PDF, Word, ePub) s'enregistre par un
/// panneau, où l'on choisit son dossier et son nom (Patrick, 19/11/2026, par la session fornews :
/// « un panneau d'enregistrement (macOS) »). Sur iPhone et iPad, la feuille de partage, qui
/// propose aussi « Enregistrer dans Fichiers ».
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var enregistrer = false
    /// Appelé quand le panneau d'enregistrement se ferme : la feuille qui le porte se retire.
    var fini: () -> Void = {}

    func makeUIViewController(context: Context) -> UIViewController {
        #if targetEnvironment(macCatalyst)
        if enregistrer, let url = items.first as? URL {
            let p = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            p.shouldShowFileExtensions = true
            p.delegate = context.coordinator
            return p
        }
        #endif
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(fini: fini) }

    final class Coordinateur: NSObject, UIDocumentPickerDelegate {
        let fini: () -> Void
        init(fini: @escaping () -> Void) { self.fini = fini }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { fini() }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { fini() }
    }
}

/// Identifiable wrapper so we can drive `.sheet(item:)` with a URL.
struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
    /// Un fichier exporté, à enregistrer (panneau sur Mac) plutôt qu'à partager.
    var enregistrer = false
}
