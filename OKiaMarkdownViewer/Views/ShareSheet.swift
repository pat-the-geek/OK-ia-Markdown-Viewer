import SwiftUI
import UIKit

/// Wraps UIActivityViewController for sharing files (PDF export, original .md).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so we can drive `.sheet(item:)` with a URL.
struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}
