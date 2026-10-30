import SwiftUI
import UIKit

/// 1.4 — ouvrir un dossier de md Viewer là où l'utilisateur range ses fichiers : dans Fichiers sur
/// iPhone et iPad, dans le Finder sur Mac (Patrick, 30/10/2026 : « devant “Documents analysés” et
/// “Coffre · Documents”, un bouton qui ouvre le répertoire dans Fichiers ou le Finder »).
enum OuvrirDossier {

    /// Fichiers s'ouvre sur un dossier par son adresse `shareddocuments://` ; le Finder, sur Mac,
    /// par l'adresse du dossier elle-même.
    @MainActor
    static func ouvrir(_ dossier: URL) {
        let acces = dossier.startAccessingSecurityScopedResource()
        defer { if acces { dossier.stopAccessingSecurityScopedResource() } }
        if TailleAccueil.surMac {
            UIApplication.shared.open(dossier) { ok in if !ok { dansFichiers(dossier) } }
        } else {
            dansFichiers(dossier)
        }
    }

    @MainActor
    private static func dansFichiers(_ dossier: URL) {
        guard let chemin = dossier.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let u = URL(string: "shareddocuments://" + chemin) else { return }
        UIApplication.shared.open(u)
    }

    /// Le libellé du bouton, selon l'appareil.
    static var libelle: String {
        TailleAccueil.surMac ? tr("Ouvrir dans le Finder") : tr("Ouvrir dans Fichiers")
    }
}

/// Le bouton dossier, posé devant le titre d'une section de l'accueil.
struct BoutonDossier: View {
    /// Le dossier, trouvé au moment du toucher : celui des documents analysés demande le conteneur
    /// iCloud, qui peut attendre (hors du fil principal).
    let dossier: @Sendable () async -> URL?

    var body: some View {
        Button {
            Task {
                guard let u = await dossier() else { return }
                await MainActor.run { OuvrirDossier.ouvrir(u) }
            }
        } label: {
            Image(systemName: "folder")
        }
        .buttonStyle(.borderless)
        .help(OuvrirDossier.libelle)
        .accessibilityLabel(OuvrirDossier.libelle)
    }
}
