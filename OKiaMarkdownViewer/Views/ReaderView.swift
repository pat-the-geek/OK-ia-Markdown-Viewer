import SwiftUI

/// Displays a rendered Markdown document with a slim title bar, and presents the
/// full-screen diagram zoom overlay when a Mermaid diagram is tapped.
struct ReaderView: View {
    let document: MarkdownDocument
    var onOpen: () -> Void

    @State private var tapped: TappedDiagram?
    @State private var title: String = ""

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        ZStack(alignment: .top) {
            MarkdownWebView(document: document, tapped: $tapped, onTitle: { title = $0 })
                .ignoresSafeArea(edges: .bottom)

            titleBar
        }
        .fullScreenCover(item: $tapped) { diagram in
            DiagramZoomView(diagram: diagram)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            Text(title.isEmpty ? document.filename : title)
                .font(.system(size: 16, weight: .heavy))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button(action: onOpen) {
                Image(systemName: "folder")
                    .font(.system(size: 17, weight: .semibold))
            }
            .tint(orange)
            .accessibilityLabel("Ouvrir un fichier")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }
}
