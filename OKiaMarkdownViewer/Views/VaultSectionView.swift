import SwiftUI

/// Home-screen section listing the Markdown reports found in the watched vault folder.
struct VaultSectionView: View {
    @ObservedObject var vault: VaultStore
    var onPick: () -> Void
    var onOpen: (VaultReport) -> Void

    @State private var showSettings = false
    @State private var patternDraft = ""
    @ObservedObject private var loc = Localization.shared

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(tr("Coffre"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { patternDraft = vault.pattern; showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .tint(orange)
                .accessibilityLabel(tr("Réglages du coffre"))
                .popover(isPresented: $showSettings) {
                    settingsControls.presentationCompactAdaptation(.popover)
                }
                Button(vault.hasFolder ? tr("Changer") : tr("Choisir…"), action: onPick)
                    .font(.caption.weight(.semibold))
                    .tint(orange)
            }
            .padding(.horizontal, 4)

            if !vault.hasFolder {
                Button(action: onPick) {
                    Label(tr("Choisir le dossier du coffre…"),
                          systemImage: "folder.badge.gearshape")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(orange)
            } else if vault.reports.isEmpty {
                Text(tr("Aucun rapport trouvé dans les dossiers « %@ » de « %@ ».",
                        vault.pattern, vault.folderName ?? ""))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(groupes) { groupe in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(groupe.titre)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(groupe.elements) { report in
                                ligne(report)
                                if report.id != groupe.elements.last?.id {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 6)
                }

                if let name = vault.folderName {
                    Text(name).font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 4)
                }
            }
        }
        .frame(maxWidth: 480)
        .padding(.top, 8)
    }

    /// Les rapports du coffre, découpés comme les récents. Le coffre montre les quinze
    /// derniers ; sans intitulé de date, rien ne distingue un rapport du matin d'un rapport
    /// de mai.
    private var groupes: [GroupeDate<VaultReport>] {
        DecoupageParDate.grouper(Array(vault.reports.prefix(15)), date: \.modified)
    }

    private func ligne(_ report: VaultReport) -> some View {
        Button { onOpen(report) } label: {
            HStack(spacing: 12) {
                Image(systemName: report.downloaded ? "doc.text" : "arrow.down.doc")
                    .foregroundStyle(orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(report.subfolder) · \(DecoupageParDate.mention(pour: report.modified))")
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
    }

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Dossiers à inclure"))
                .font(.headline)
            Text(tr("Motif des sous-dossiers du coffre à lire (jokers * et ?). Les autres dossiers sont ignorés."))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(VaultStore.defaultPattern, text: $patternDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
                .onSubmit { apply() }
            HStack {
                Button(tr("Par défaut")) { patternDraft = VaultStore.defaultPattern }
                    .font(.caption)
                Spacer()
                Button(tr("Appliquer")) { apply() }
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
