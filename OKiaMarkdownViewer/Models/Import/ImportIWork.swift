import Foundation

/// Option Analytic (1.7) — un document Pages, Keynote ou Numbers s'importe par l'aperçu qu'il porte,
/// comme un PDF (Patrick, 13/11/2026 : « Apple's documents import through the preview they carry,
/// like a PDF »).
///
/// Le format d'iWork (fichiers `.iwa`) n'est pas documenté. Dans l'ordre :
/// 1. un ancien document (iWork '09) porte un vrai PDF, `QuickLook/Preview.pdf` : l'import PDF ;
/// 2. Pages : le texte du document, lu dans ses fichiers (`LecteurIWA`), et l'image de sa première
///    page (`preview.jpg`) ;
/// 3. Keynote et Numbers : l'image de la première diapositive ou feuille.
/// WebKit n'affiche pas ces documents sur iPhone et iPad (essayé au simulateur le 12/11/2026) : on
/// ne passe pas par lui. Le document est un fichier zip, ou un paquet (un dossier).
@MainActor
enum ImportIWork {
    static let extensions: Set<String> = ["pages", "key", "numbers"]

    enum Erreur: Error, LocalizedError {
        case sansApercu(String)
        var errorDescription: String? {
            switch self {
            case .sansApercu(let nom):
                return tr("« %@ » ne porte pas d’aperçu lisible. Exportez-le en PDF depuis Pages, Keynote ou Numbers, puis importez le PDF.", nom)
            }
        }
    }

    static func convertir(_ url: URL, nom: String, suivi: SuiviImport? = nil) async throws -> DocumentImporte {
        let lire = try lecteur(url)
        // 1. Un ancien document : son PDF.
        if let pdf = lire("QuickLook/Preview.pdf") {
            return try await ImportPDF.convertir(pdf, nom: nom, suivi: suivi)
        }
        // 2. Pages : le texte du document, lu dans ses fichiers (`LecteurIWA`), le corps d'abord ;
        //    l'image de la première page à la suite. Keynote et Numbers : l'image seule.
        let titre = (nom as NSString).deletingPathExtension
        let image = lire("preview.jpg") ?? lire("QuickLook/Thumbnail.jpg") ?? lire("preview-web.jpg")
        var corps = ""
        if (nom as NSString).pathExtension.lowercased() == "pages" {
            let fichiers = try entrees(url).filter { $0.hasPrefix("Index/") && $0.hasSuffix(".iwa") && !$0.contains("Stylesheet") }
            let textes = LecteurIWA.textes(fichiers.compactMap(lire))
            // Le corps (genre 0), puis les zones de texte et les notes ; les en-têtes et pieds de page
            // (1, 2) ne disent rien du document.
            let gardes = textes.filter { $0.genre == 0 } + textes.filter { [3, 4, 6].contains($0.genre) }
            corps = gardes.map { t in
                t.texte.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }.joined(separator: "\n\n---\n\n")
        }
        guard !corps.isEmpty || image != nil else { throw Erreur.sansApercu(nom) }
        var md = "# " + titre + "\n\n"
        if !corps.isEmpty { md += corps + "\n\n" }
        if let image {
            md += "*" + (corps.isEmpty
                ? tr("Aperçu de la première page : le reste du document ne s’importe pas de cette façon. Exportez-le en PDF pour l’importer en entier.")
                : tr("La première page, telle que Pages l’a enregistrée :")) + "*\n\n"
            md += "![" + titre + "][apercu]\n\n"
            md += "[apercu]: data:image/jpeg;base64," + image.base64EncodedString() + "\n"
        }
        let mots = corps.split { $0.isWhitespace }.count
        return DocumentImporte(genre: .rapport, titre: titre, markdown: md,
                               resume: mots > 0 ? tr("%d mots", mots) : tr("1 image"))
    }

    /// Les noms des entrées du document.
    private static func entrees(_ url: URL) throws -> [String] {
        var dossier: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &dossier), dossier.boolValue {
            let index = url.appendingPathComponent("Index")
            return ((try? FileManager.default.contentsOfDirectory(atPath: index.path)) ?? []).map { "Index/" + $0 }
        }
        return try LecteurZip(Data(contentsOf: url)).noms
    }

    /// Lit une entrée du document, qu'il soit un zip ou un paquet.
    private static func lecteur(_ url: URL) throws -> (String) -> Data? {
        var dossier: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &dossier), dossier.boolValue {
            return { try? Data(contentsOf: url.appendingPathComponent($0)) }
        }
        let zip = try LecteurZip(Data(contentsOf: url))
        return { (try? zip.donnees($0)) ?? nil }
    }
}
