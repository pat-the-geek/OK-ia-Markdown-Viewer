import SwiftUI

/// Shown when no document is loaded: OK-ia branded landing with open + sample
/// actions and a list of recently opened files.
struct EmptyStateView: View {
    @ObservedObject var recentsStore: RecentFilesStore
    var onOpen: () -> Void
    var onSample: () -> Void
    var onRecent: (RecentFile) -> Void

    private var recents: [RecentFile] { recentsStore.items }
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "flowchart")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(orange)

                VStack(spacing: 6) {
                    Text("OK-ia Markdown Viewer")
                        .font(.system(size: 25, weight: .heavy))
                    Text("Ce que les algorithmes ignorent encore.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .multilineTextAlignment(.center)

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

                if !recents.isEmpty {
                    recentsSection
                }

                Spacer(minLength: 24)
                Image("OKiaWideLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .frame(height: 50)
                    .accessibilityLabel("OK-ia")
                    .padding(.bottom, 16)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Récents")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(recents) { item in
                    Button { onRecent(item) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .foregroundStyle(orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(item.openedAt, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { recentsStore.remove(item) } label: {
                            Label("Retirer de la liste", systemImage: "trash")
                        }
                    }
                    if item.id != recents.last?.id { Divider().padding(.leading, 44) }
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: 480)
        .padding(.top, 8)
    }
}
