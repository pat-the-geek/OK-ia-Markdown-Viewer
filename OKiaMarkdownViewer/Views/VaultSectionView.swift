import SwiftUI

/// Home-screen section listing the Markdown reports found in the watched vault folder.
struct VaultSectionView: View {
    @ObservedObject var vault: VaultStore
    var onPick: () -> Void
    var onOpen: (VaultReport) -> Void

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Coffre")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(vault.hasFolder ? "Changer" : "Choisir…", action: onPick)
                    .font(.caption.weight(.semibold))
                    .tint(orange)
            }
            .padding(.horizontal, 4)

            if !vault.hasFolder {
                Button(action: onPick) {
                    Label("Choisir le dossier du coffre…", systemImage: "folder.badge.gearshape")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(orange)
            } else if vault.reports.isEmpty {
                Text("Aucun rapport dans « \(vault.folderName ?? "") ».")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(vault.reports.prefix(15)) { report in
                        Button { onOpen(report) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: report.downloaded ? "doc.text" : "arrow.down.doc")
                                    .foregroundStyle(orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(report.name)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(report.modified, format: .relative(presentation: .named))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if report.id != vault.reports.prefix(15).last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                if let name = vault.folderName {
                    Text(name).font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 4)
                }
            }
        }
        .frame(maxWidth: 480)
        .padding(.top, 8)
    }
}
