import SwiftUI

/// Identifiable URL wrapper to drive `.sheet(item:)`. Available on all platforms.
struct ExternalLink: Identifiable {
    let id = UUID()
    let url: URL
}

#if !targetEnvironment(macCatalyst)
import SafariServices

/// In-app Safari browser (SFSafariViewController) presented over the reader — iOS/iPadOS only.
/// On Mac Catalyst, external links open in the default browser instead (see ReaderView).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        // Pas de teinte orange : dépréciée depuis iOS 26, elle se bat avec les fonds que le
        // système dessine derrière les commandes.
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
