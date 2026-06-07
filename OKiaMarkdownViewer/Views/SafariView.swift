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
        controller.preferredControlTintColor = UIColor(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255, alpha: 1)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
