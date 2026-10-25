import Foundation
import UIKit

// Option Analytic (1.4) — ce que les imports Word, PDF et PowerPoint ont en commun : le résultat,
// l'avancement, les images et l'échappement du Markdown.

/// Un document importé, prêt à être ouvert par le lecteur.
struct DocumentImporte {
    enum Genre { case rapport, presentation }
    var genre: Genre
    var titre: String
    var markdown: String
    /// Ce qui a été lu : « 12 diapositives, 8 images ».
    var resume: String
    /// Les commentaires de relecture, chacun marqué dans le Markdown (`ConsigneImport.marque`) :
    /// l'utilisateur peut, à l'import, demander qu'Apple Intelligence rédige ce qu'ils demandent.
    var consignes: [ConsigneImport] = []
}

/// Un commentaire de relecture et ce qu'il commente.
struct ConsigneImport: Sendable {
    var numero: Int
    var auteur: String
    var commentaire: String
    /// Le texte commenté : le paragraphe, la cellule, la diapositive.
    var passage: String
    /// Le titre de la partie où il se trouve.
    var section: String?

    /// La marque posée dans le Markdown après le passage, remplacée à la fin de l'import par le
    /// texte rédigé, ou retirée.
    static func marque(_ n: Int) -> String { "<!--consigne:\(n)-->" }
}

/// Ce que l'import a fait jusqu'ici, pour le compte à rebours : l'étape, sa part du tout, et les
/// éléments au fur et à mesure qu'ils sont repérés.
struct AvancementImport: Equatable {
    var etape: String
    var fait: Int
    var total: Int
    /// Le dernier élément repéré : un titre de diapositive, de section, une image.
    var dernier: String?
}

typealias SuiviImport = @MainActor (AvancementImport) -> Void

enum ImagesImport {
    /// Au-delà, l'image est réduite : un document très illustré deviendrait lourd à ouvrir. 1600 px,
    /// c'est la pleine largeur d'une diapositive sur un écran Retina ; une image qui n'en occupe
    /// qu'une part n'a pas besoin de plus (`cote(pourPart:)`).
    static let coteMax: CGFloat = 1600
    static let coteMin: CGFloat = 480
    /// Qualité JPEG : à 0,82, un PowerPoint réel de 41 images pesait 11 Mo de Markdown.
    static let qualite: CGFloat = 0.72

    /// Le côté utile d'une image qui occupe `part` (0…1) de la largeur ou de la hauteur de sa page.
    static func cote(pourPart part: Double?) -> CGFloat {
        guard let part, part > 0 else { return coteMax }
        return min(coteMax, max(coteMin, (coteMax * CGFloat(part)).rounded()))
    }

    /// Une image du document en `data:` Markdown, réduite au besoin. Les formats que WebKit ne lit
    /// pas (EMF, WMF des vieux Office) sont laissés de côté : nil.
    static func dataURI(_ donnees: Data, nom: String, coteMax: CGFloat = coteMax) -> String? {
        let ext = (nom as NSString).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"].contains(ext),
              let image = UIImage(data: donnees) else { return nil }
        let cote = max(image.size.width, image.size.height)
        // Petite et dans un format du Web : telle quelle.
        if cote <= coteMax, ["png", "jpg", "jpeg", "gif", "webp"].contains(ext), donnees.count < 250_000 {
            let type = ext == "jpg" ? "jpeg" : ext
            return "data:image/\(type);base64,\(donnees.base64EncodedString())"
        }
        let echelle = min(1, coteMax / cote)
        let taille = CGSize(width: (image.size.width * echelle).rounded(), height: (image.size.height * echelle).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Un JPEG n'a pas de transparence : le rendu est opaque, sur fond blanc (PowerPoint pose
        // ses images sur une diapositive claire).
        let transparent = ext == "png" || ext == "gif" || ext == "webp" ? aDeLaTransparence(image) : false
        format.opaque = !transparent
        let reduite = UIGraphicsImageRenderer(size: taille, format: format).image { ctx in
            if !transparent { UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: taille)) }
            image.draw(in: CGRect(origin: .zero, size: taille))
        }
        // Le PNG garde la transparence des schémas ; une photo enregistrée en PNG (1 Mo dans un
        // PowerPoint réel) passe en JPEG, bien plus léger.
        if transparent, let png = reduite.pngData(), png.count < 900_000 {
            return "data:image/png;base64,\(png.base64EncodedString())"
        }
        guard let jpeg = reduite.jpegData(compressionQuality: qualite) else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }
}

extension ImagesImport {
    /// De la transparence VISIBLE : beaucoup de PNG déclarent une couche alpha sans s'en servir. On
    /// regarde l'image réduite à 48 × 48 : un seul pixel nettement transparent suffit.
    static func aDeLaTransparence(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage, ![.none, .noneSkipFirst, .noneSkipLast].contains(cg.alphaInfo) else { return false }
        let c = 48
        var pixels = [UInt8](repeating: 255, count: c * c * 4)
        let espace = CGColorSpaceCreateDeviceRGB()
        let rendu = pixels.withUnsafeMutableBytes { tampon -> Bool in
            guard let ctx = CGContext(data: tampon.baseAddress, width: c, height: c, bitsPerComponent: 8,
                                      bytesPerRow: c * 4, space: espace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.clear(CGRect(x: 0, y: 0, width: c, height: c))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: c, height: c))
            return true
        }
        guard rendu else { return true }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 240 }
    }
}

/// Les images d'un document importé, chacune écrite UNE fois : en référence Markdown
/// (`![…][img3]`), la définition (`[img3]: data:…`) à la fin du document. Un PowerPoint réel
/// répétait un visuel de 1 Mo sur onze diapositives, et un logo sur vingt : 26 Mo de Markdown.
/// Le diaporama reporte les définitions sur chaque diapositive (`partagerReferences`).
final class ReservoirImages {
    private var parSource: [String: String] = [:]
    private(set) var definitions: [String] = []

    /// La référence d'une image (son chemin dans l'archive), convertie la première fois ; nil si
    /// le format n'est pas lisible.
    /// `part` : la part de la page qu'elle occupe à sa première apparition (nil : inconnue).
    func reference(_ source: String, part: Double? = nil, donnees: () -> Data?) -> String? {
        if let id = parSource[source] { return id.isEmpty ? nil : id }
        guard let d = donnees(),
              let uri = ImagesImport.dataURI(d, nom: source, coteMax: ImagesImport.cote(pourPart: part)) else {
            parSource[source] = ""; return nil
        }
        let id = "img\(definitions.count + 1)"
        parSource[source] = id
        definitions.append("[\(id)]: \(uri)")
        return id
    }

    var nombre: Int { definitions.count }
}

enum MarkdownImport {
    /// Ce qui, dans du texte ordinaire, ferait du Markdown sans le vouloir.
    static func echapper(_ s: String) -> String {
        var r = ""
        for c in s {
            if "\\`*_[]<>|".contains(c) { r.append("\\") }
            r.append(c)
        }
        return r
    }

    /// Un paragraphe ordinaire qui, en tête de ligne, passerait pour un titre, une liste ou une
    /// citation (« 1. », « # », « - », « > ») : sa première marque échappée.
    static func debutDeLigne(_ s: String) -> String {
        if let r = s.range(of: #"^(\d+)([.)])(\s)"#, options: .regularExpression) {
            let m = s[r]
            return String(m.dropLast(2)) + "\\" + String(m.suffix(2)) + s[r.upperBound...]
        }
        if let c = s.first, "#-+>=".contains(c) { return "\\" + s }
        return s
    }

    /// Une cellule de tableau : sur une ligne, les barres échappées.
    static func cellule(_ s: String) -> String {
        echapper(s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))
    }

    static func tableau(_ lignes: [[String]]) -> String {
        guard let entete = lignes.first, !entete.isEmpty else { return "" }
        let n = lignes.map(\.count).max() ?? entete.count
        func ligne(_ l: [String]) -> String {
            "| " + (0..<n).map { $0 < l.count ? cellule(l[$0]) : "" }.joined(separator: " | ") + " |"
        }
        var r = [ligne(entete), "| " + Array(repeating: "---", count: n).joined(separator: " | ") + " |"]
        r += lignes.dropFirst().map(ligne)
        return r.joined(separator: "\n")
    }

    /// L'en-tête YAML d'un document importé.
    static func entete(titre: String, source: String, genre: String, extra: [String: String] = [:]) -> String {
        let jour = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        var l = ["---", "title: \"\(titre.replacingOccurrences(of: "\"", with: "'"))\"", "date: \(jour)",
                 "type: \(genre)", "source: \"\(source.replacingOccurrences(of: "\"", with: "'"))\"",
                 "importe-par: md Viewer"]
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { l.append("\(k): \(v)") }
        l.append("---")
        return l.joined(separator: "\n")
    }

    /// Le chemin d'une cible de relation, à partir de la partie qui la cite
    /// (`ppt/slides/slide1.xml` + `../media/image1.png` → `ppt/media/image1.png`).
    static func cheminRelatif(_ cible: String, depuis partie: String) -> String {
        if cible.hasPrefix("/") { return String(cible.dropFirst()) }
        var dossier = partie.split(separator: "/").dropLast().map(String.init)
        for morceau in cible.split(separator: "/") {
            if morceau == ".." { _ = dossier.popLast() } else if morceau != "." { dossier.append(String(morceau)) }
        }
        return dossier.joined(separator: "/")
    }

    /// Les relations d'une partie : identifiant → (cible, type).
    static func relations(de partie: String, dans zip: LecteurZip) -> [String: (cible: String, type: String)] {
        let morceaux = partie.split(separator: "/").map(String.init)
        let rels = (morceaux.dropLast() + ["_rels", morceaux.last! + ".rels"]).joined(separator: "/")
        guard let xml = try? zip.donnees(rels), let racine = NoeudXML.lire(xml) else { return [:] }
        var r: [String: (String, String)] = [:]
        for rel in racine.enfants("Relationship") {
            guard let id = rel["Id"], let cible = rel["Target"] else { continue }
            if rel["TargetMode"] == "External" { r[id] = (cible, rel["Type"] ?? ""); continue }
            r[id] = (cheminRelatif(cible, depuis: partie), rel["Type"] ?? "")
        }
        return r
    }
}
