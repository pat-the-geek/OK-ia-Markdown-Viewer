import Foundation

/// Supprimer un document depuis l'accueil : un document analysé ou un rapport du coffre (1.4,
/// Patrick, 28/10/2026 : « on doit pouvoir supprimer un document analysé ou dans le coffre depuis
/// l'interface »). Sur Mac, le fichier va à la corbeille ; sur iPhone et iPad, il est supprimé
/// (`trashItem` y range le fichier dans un `.Trash` caché de l'app, qui ne se vide jamais).
/// L'écriture est coordonnée : iCloud Drive suit sur les autres appareils.
enum SuppressionDocument {
    static func supprimer(_ url: URL) throws {
        var erreurCoordination: NSError?
        var erreur: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &erreurCoordination) { u in
            do {
                #if targetEnvironment(macCatalyst)
                if (try? FileManager.default.trashItem(at: u, resultingItemURL: nil)) != nil { return }
                #endif
                try FileManager.default.removeItem(at: u)
            } catch {
                erreur = error
            }
        }
        if let e = erreurCoordination ?? erreur { throw e }
    }
}
