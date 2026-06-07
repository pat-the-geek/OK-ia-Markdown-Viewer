import SwiftUI

/// Home-screen section listing the Markdown reports found in the watched vault folder.
struct VaultSectionView: View {
    @ObservedObject var vault: VaultStore
    var onPick: () -> Void
    var onOpen: (VaultReport) -> Void

    @State private var showSettings = false
    @State private var patternDraft = ""

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Coffre")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { patternDraft = vault.pattern; showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .tint(orange)
                .accessibilityLabel("Réglages du coffre")
                .popover(isPresented: $showSettings) {
                    settingsControls.presentationCompactAdaptation(.popover)
                }
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
                Text("Aucun rapport trouvé dans les dossiers « \(vault.pattern) » de « \(vault.folderName ?? "") ».")
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
                                    Text("\(report.subfolder) · \(report.modified.formatted(.relative(presentation: .named)))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
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

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dossiers à inclure")
                .font(.headline)
            Text("Motif des sous-dossiers du coffre à lire (jokers * et ?). Les autres dossiers sont ignorés.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(VaultStore.defaultPattern, text: $patternDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
                .onSubmit { apply() }
            HStack {
                Button("Par défaut") { patternDraft = VaultStore.defaultPattern }
                    .font(.caption)
                Spacer()
                Button("Appliquer") { apply() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .tint(orange)
        .padding(16)
        .frame(maxWidth: 320)
    }

    private func apply() {
        vault.setPattern(patternDraft)
        showSettings = false
    }
}
