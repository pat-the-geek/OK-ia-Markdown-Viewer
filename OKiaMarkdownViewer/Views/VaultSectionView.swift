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

    /// Le coffre, en sections de la liste d'accueil : l'en-tête porte ses réglages, puis une
    /// section par tranche de dates.
    var body: some View {
        Section {
            if !vault.hasFolder {
                Button(action: onPick) {
                    Label(tr("Choisir le dossier du coffre…"), systemImage: "folder.badge.gearshape")
                }
                .tint(orange)
            } else if vault.reports.isEmpty {
                Text(tr("Aucun rapport trouvé dans les dossiers « %@ » de « %@ ».",
                        vault.pattern, vault.folderName ?? ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 12) {
                Text(tr("Coffre") + (vault.folderName.map { " · \($0)" } ?? ""))
                Spacer()
                Button { patternDraft = vault.pattern; showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(tr("Réglages du coffre"))
                .popover(isPresented: $showSettings) {
                    settingsControls.presentationCompactAdaptation(.popover)
                }
                Button(vault.hasFolder ? tr("Changer") : tr("Choisir…"), action: onPick)
            }
            .tint(orange)
            .textCase(nil)
        }
        if vault.hasFolder {
            ForEach(groupes) { groupe in
                Section(groupe.titre) {
                    ForEach(groupe.elements) { report in ligne(report) }
                }
            }
        }
    }

    /// Les rapports du coffre, découpés comme les récents. Le coffre montre les quinze
    /// derniers ; sans intitulé de date, rien ne distingue un rapport du matin d'un rapport
    /// de mai.
    private var groupes: [GroupeDate<VaultReport>] {
        DecoupageParDate.grouper(Array(vault.reports.prefix(15)), date: \.modified)
    }

    private func ligne(_ report: VaultReport) -> some View {
        Button { onOpen(report) } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(report.subfolder) · \(DecoupageParDate.mention(pour: report.modified))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: report.downloaded ? "doc.text" : "arrow.down.doc")
                    .foregroundStyle(orange)
            }
        }
        .tint(.primary)
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
