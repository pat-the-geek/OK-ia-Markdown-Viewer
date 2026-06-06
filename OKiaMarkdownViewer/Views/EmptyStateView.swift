import SwiftUI

/// Shown when no document is loaded. OK-ia branded landing with open + sample actions.
struct EmptyStateView: View {
    var onOpen: () -> Void
    var onSample: () -> Void

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "flowchart")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(orange)

            VStack(spacing: 6) {
                Text("OK-ia Markdown Viewer")
                    .font(.system(size: 26, weight: .heavy))
                Text("Ce que les algorithmes ignorent encore.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .multilineTextAlignment(.center)

            Text("Ouvrez un fichier Markdown (.md) contenant des diagrammes Mermaid, ou essayez l’exemple.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button(action: onOpen) {
                    Label("Ouvrir un fichier", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(orange)

                Button(action: onSample) {
                    Label("Voir un exemple", systemImage: "doc.text")
                        .frame(maxWidth: 280)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(orange)
            }

            Spacer()
            Text("ok-ia.ch")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
