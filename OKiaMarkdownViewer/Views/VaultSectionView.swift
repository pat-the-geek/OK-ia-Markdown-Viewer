import SwiftUI

/// Home-screen section listing the Markdown reports found in the watched vault folder.
struct VaultSectionView: View {
    @ObservedObject var vault: VaultStore
    var onPick: () -> Void
    var onOpen: (VaultReport) -> Void
    /// Demande la suppression d'un rapport (l'accueil confirme).
    var onDelete: (VaultReport) -> Void = { _ in }

    @State private var showSettings = false
    @State private var patternDraft = ""
    @ObservedObject private var loc = Localization.shared
    @Environment(\.accueilEnGrille) private var enGrille

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
                .ligneAccueil()
            } else if vault.injoignable {
                // Le plus souvent un dossier partagé d'un autre Mac, déconnecté (Patrick, 11/11/2026).
                Text(tr("Le dossier du coffre ne répond pas. S’il est partagé par un autre ordinateur, vérifiez que celui-ci est allumé et que le partage est connecté, puis rechargez le coffre (↻)."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .ligneAccueil()
            } else if vault.reports.isEmpty && vault.enLecture {
                // Un partage lointain met du temps à répondre : on le dit, plutôt qu'un coffre vide.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("Lecture du coffre…"))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .ligneAccueil()
            } else if vault.reports.isEmpty {
                Text(tr("Aucun fichier Markdown dans « %@ », ni dans ses dossiers « %@ ».",
                        vault.folderName ?? "", vault.pattern))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .ligneAccueil()
            } else if vault.tronque {
                // Un dossier partagé immense : la lecture s'est arrêtée à une borne.
                Text(tr("Le coffre est grand : la lecture s’est arrêtée à %d fichiers. Le motif des réglages vise les bons dossiers.",
                        vault.reports.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .ligneAccueil()
            }
        } header: {
            HStack(spacing: 12) {
                if vault.hasFolder {
                    BoutonDossier { [vault] in await vault.resolveFolder() }
                        .padding(.trailing, -4)
                }
                Text(tr("Coffre") + (vault.folderName.map { " · \($0)" } ?? ""))
                    .foregroundStyle(.secondary)
                Spacer()
                if vault.hasFolder {
                    // Relire le coffre sans attendre la relecture suivante (Patrick, 12/11/2026) :
                    // un partage lointain n'est relu que toutes les 60 s, et un partage déconnecté
                    // ne se remonte qu'ici. Pendant une lecture, la roue tourne à sa place.
                    if vault.enLecture {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(tr("Lecture du coffre…"))
                    } else {
                        Button { Task { await vault.rafraichirEnArrierePlan(forcee: true) } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel(tr("Recharger le coffre"))
                        .help(tr("Recharger le coffre"))
                    }
                }
                Button { patternDraft = vault.pattern; showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(tr("Réglages du coffre"))
                .popover(isPresented: $showSettings) {
                    settingsControls.presentationCompactAdaptation(.popover)
                }
                Button(vault.hasFolder ? tr("Changer") : tr("Choisir…"), action: onPick)
                    .fontWeight(.regular)
            }
            .tint(orange)
            .textCase(nil)
            .enTeteAccueil()
        }
        if vault.hasFolder {
            ForEach(groupes) { groupe in
                Section {
                    if enGrille {
                        GrilleCartes { ForEach(groupe.elements) { report in carte(report) } }
                    } else {
                        ForEach(groupe.elements) { report in ligne(report) }
                    }
                } header: {
                    Text(groupe.titre).foregroundStyle(.secondary).enTeteAccueil()
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

    private func carte(_ report: VaultReport) -> some View {
        CarteDocument(nom: (report.name as NSString).deletingPathExtension,
                      mention: report.mentionDossier + DecoupageParDate.mention(pour: report.modified),
                      resoudre: { await resoudre(report) },
                      action: { onOpen(report) }) {
            Button(role: .destructive) { onDelete(report) } label: { Label(tr("Supprimer"), systemImage: "trash") }
        }
    }

    /// Le fichier d'une carte et la racine dont il faut ouvrir l'accès, résolus hors du fil principal.
    private func resoudre(_ report: VaultReport) async -> (url: URL, portee: URL?)? {
        guard report.downloaded, let r = await vault.racineHorsFil() else { return nil }
        return (r.appendingPathComponent(report.subfolder).appendingPathComponent(report.name), r)
    }

    private func ligne(_ report: VaultReport) -> some View {
        Button { onOpen(report) } label: {
            Label {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(report.mentionDossier + DecoupageParDate.mention(pour: report.modified))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    MarqueAnnoteeLigne(resoudre: { await resoudre(report) })
                }
            } icon: {
                Image(systemName: report.downloaded ? "doc.text" : "arrow.down.doc")
                    .foregroundStyle(orange)
            }
        }
        .tint(.primary)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete(report) } label: { Label(tr("Supprimer"), systemImage: "trash") }
        }
        .contextMenu {
            Button(role: .destructive) { onDelete(report) } label: { Label(tr("Supprimer"), systemImage: "trash") }
        }
    }

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Dossiers à inclure"))
                .font(.headline)
            Text(tr("Les fichiers à la racine du coffre sont toujours lus. Le motif choisit les sous-dossiers à lire, à tous leurs niveaux (jokers * et ? ; * : tous)."))
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
