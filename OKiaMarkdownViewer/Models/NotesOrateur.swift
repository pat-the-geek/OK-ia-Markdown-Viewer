import Foundation

// Option Analytic (1.5) — écrire les notes de l'orateur dans l'app (Patrick, 1er novembre 2026 :
// « Je ne trouve pas comment ajouter les notes de l'orateur », puis « Prend note pour une prochaine
// version »).
//
// La note vit dans le fichier lui-même, en commentaire HTML à la fin de sa diapositive — le format
// que l'import PowerPoint écrit déjà, et que tout éditeur Markdown garde. Le texte du fichier est
// retouché par le diaporama (`presentation.js`, `ecrireNote`), avec son propre découpage en
// diapositives ; ici, on l'enregistre.
//
// Les annotations du document ne bougent pas : son empreinte ne compte pas les commentaires
// (`IdentiteDocument.sansMarques`).

@MainActor
enum NotesOrateur {
    enum Erreur: LocalizedError {
        case pasDeFichier, diapositiveIntrouvable
        var errorDescription: String? {
            switch self {
            case .pasDeFichier: return tr("Ce document n’a pas de fichier où écrire ses notes.")
            case .diapositiveIntrouvable: return tr("La diapositive ne se retrouve pas dans le fichier.")
            }
        }
    }

    /// Le texte que l'app a écrit en dernier dans chaque fichier, depuis son lancement : le lecteur
    /// garde le texte qu'il a ouvert, le diaporama suivant repart de celui-ci.
    private static var ecrits: [URL: String] = [:]

    /// Les fichiers que l'on peut retoucher : du Markdown, hors de l'app. Jamais un Word, un PDF ou
    /// un PowerPoint, que le lecteur montre converti.
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]

    /// Le document peut-il recevoir des notes ?
    static func modifiable(_ d: MarkdownDocument) -> Bool {
        guard let u = d.sourceURL, u.isFileURL, extensions.contains(u.pathExtension.lowercased()) else { return false }
        return !u.standardizedFileURL.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path)
    }

    /// Le document avec les notes écrites depuis son ouverture.
    static func aJour(_ d: MarkdownDocument) -> MarkdownDocument {
        guard let u = d.sourceURL?.standardizedFileURL, let t = ecrits[u], t != d.text else { return d }
        return MarkdownDocument(filename: d.filename, text: t, sourceURL: d.sourceURL)
    }

    /// Enregistre `texte` — le fichier entier, avec la note — à la place du document.
    static func enregistrer(_ texte: String, document d: MarkdownDocument) throws {
        guard let u = d.sourceURL, modifiable(d) else { throw Erreur.pasDeFichier }
        // L'accès au fichier : le sien (un fichier choisi, un récent), ou celui du coffre qui le
        // contient.
        let fichier = u.startAccessingSecurityScopedResource()
        var coffre: URL?
        if let racine = VaultStore.partage.resolveFolder(),
           u.standardizedFileURL.path.hasPrefix(racine.standardizedFileURL.path + "/"),
           racine.startAccessingSecurityScopedResource() {
            coffre = racine
        }
        defer {
            if fichier { u.stopAccessingSecurityScopedResource() }
            coffre?.stopAccessingSecurityScopedResource()
        }
        // Coordonné : le fichier est souvent dans iCloud Drive.
        var erreur: NSError?
        var ecriture: Error?
        NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &erreur) { cible in
            // Les annotations inscrites à la fin du fichier y restent (`AnnotationsIntegrees`).
            let complet = AnnotationsIntegrees.reporter(texte, depuis: cible)
            do { try complet.write(to: cible, atomically: true, encoding: .utf8) } catch { ecriture = error }
        }
        if let erreur { throw erreur }
        if let ecriture { throw ecriture }
        ecrits[u.standardizedFileURL] = texte
    }
}
