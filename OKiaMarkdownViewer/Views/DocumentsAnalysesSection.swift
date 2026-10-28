import SwiftUI

/// Option Analytic (1.4) — les documents analysés sur l'accueil : ce que md Viewer a importé et
/// analysé (Word, PDF, PowerPoint, fiches de pages web), rangé dans « Documents analysés »
/// (`RangementDocuments`). À part du coffre, le dossier de rapports que l'utilisateur a choisi en
/// 1.3 (Patrick, 27/10/2026 : « il faut faire une différence entre le coffre de la version
/// précédente et le lieu de stockage des documents analysés »). Réservée à l'option.
/// La liste est chargée par l'accueil (`charger`) : une section vide dans une liste ne s'affiche
/// jamais, et son propre chargement ne partait donc pas.
struct DocumentsAnalysesSection: View {
    let documents: [DocumentAnalyse]
    var ouvrir: (URL) -> Void
    @ObservedObject private var achat = AchatAnalytic.partage
    @ObservedObject private var loc = Localization.shared
    /// Au-delà, la liste renvoie à Fichiers.
    private let plafond = 30

    struct DocumentAnalyse: Identifiable {
        let url: URL
        let nom: String
        let date: Date
        var id: URL { url }
    }

    var body: some View {
        Group {
            if achat.acces, !documents.isEmpty {
                ForEach(Array(groupes.enumerated()), id: \.element.id) { rang, groupe in
                    Section {
                        ForEach(groupe.elements) { d in ligne(d) }
                    } header: {
                        // La recherche et l'analyse du coffre sont dans la barre de l'accueil.
                        if rang == 0 {
                            Text(tr("Documents analysés") + " · " + groupe.titre)
                        } else {
                            Text(groupe.titre)
                        }
                    } footer: {
                        if rang == groupes.count - 1, documents.count > plafond {
                            // Sur Mac, c'est le Finder, pas l'app Fichiers.
                            Text(AchatAnalytic.surMac
                                 ? tr("Les plus anciens sont dans le Finder : iCloud Drive, dossier « md Viewer ».")
                                 : tr("Les plus anciens sont dans Fichiers, dossier « md Viewer »."))
                        }
                    }
                }
            }
        }
    }

    private var groupes: [GroupeDate<DocumentAnalyse>] {
        DecoupageParDate.grouper(Array(documents.prefix(plafond)), date: \.date)
    }

    private func ligne(_ d: DocumentAnalyse) -> some View {
        Button { ouvrir(d.url) } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.nom).foregroundStyle(.primary).lineLimit(1)
                    Text(DecoupageParDate.mention(pour: d.date)).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255))
            }
        }
        // Comme les récents : le nom en noir, l'icône seule en orange.
        .tint(.primary)
    }

    /// Le dossier se lit hors du fil principal : le conteneur iCloud peut se faire attendre. Rien
    /// sans l'option : le dossier lui est réservé.
    static func charger() async -> [DocumentAnalyse] {
        guard await AchatAnalytic.partage.acces else { return [] }
        let lus = await Task.detached { RangementDocuments.documents() }.value
        return lus.map { DocumentAnalyse(url: $0.url, nom: $0.nom, date: $0.date) }
    }
}
