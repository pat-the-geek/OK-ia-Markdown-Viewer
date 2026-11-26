import Foundation

// ============================================================================
//  Export ePub 3 (1.5.1) — demandé par Patrick le 19/11/2026, par la session
//  fornews : « l'export d'un dossier fornews en ePub et en PDF se fait dans
//  md Viewer ». fornews compose le Markdown, md Viewer produit le fichier.
//
//  Les blocs sont ceux de l'export Word (`OOXMLBlock`, remplis par
//  `exportModel` de render.js) : diagrammes en PNG, cartes en JPEG, images
//  téléchargées puis embarquées — le livre se lit hors connexion. Le paquet est
//  écrit par `OOXMLZip` (entrées non compressées), `mimetype` en premier, comme
//  le veut la norme. Pur Foundation : vérifiable hors de l'app.
// ============================================================================

/// Les métadonnées du livre : l'en-tête YAML du document d'abord (`titre`, `langue`, `date`,
/// `auteur`), sinon ce que l'app sait du document.
struct EpubMeta: Equatable {
    var titre: String
    var langue: String
    /// AAAA-MM-JJ.
    var date: String
    var auteur: String?

    /// Lit l'en-tête YAML d'un Markdown ; les clés absentes prennent les valeurs de repli.
    static func depuis(markdown: String, titre: String, langue: String, maintenant: Date = Date()) -> EpubMeta {
        var entete: [String: String] = [:]
        if markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n"),
           let fin = markdown.dropFirst(4).range(of: "\n---") {
            for ligne in markdown[markdown.index(markdown.startIndex, offsetBy: 4)..<fin.lowerBound]
                .split(whereSeparator: \.isNewline) {
                guard let deux = ligne.firstIndex(of: ":") else { continue }
                let cle = ligne[..<deux].trimmingCharacters(in: .whitespaces).lowercased()
                let valeur = ligne[ligne.index(after: deux)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !valeur.isEmpty { entete[cle] = valeur }
            }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        var date = entete["date"].map { String($0.prefix(10)) } ?? ""
        if f.date(from: date) == nil { date = f.string(from: maintenant) }
        let lang = (entete["langue"] ?? entete["lang"] ?? entete["language"] ?? langue)
            .trimmingCharacters(in: .whitespaces)
        return EpubMeta(titre: entete["titre"] ?? entete["title"] ?? titre,
                        langue: lang.isEmpty ? "fr" : lang,
                        date: date,
                        auteur: entete["auteur"] ?? entete["author"])
    }
}

enum EpubBuilder {

    /// Le paquet ePub complet.
    static func build(meta: EpubMeta, blocks: [OOXMLBlock], identifiant: String = UUID().uuidString,
                      maintenant: Date = Date()) -> Data {
        var images: [(nom: String, image: OOXMLImage)] = []
        var toc: [(niveau: Int, id: String, texte: String)] = []
        var corps = ""
        var n = 0

        // Le titre en tête du livre, sauf si le document commence déjà par lui.
        let premier: String? = {
            if case .heading(_, let r)? = blocks.first { return texte(r) }
            return nil
        }()
        if premier?.trimmingCharacters(in: .whitespaces) != meta.titre.trimmingCharacters(in: .whitespaces) {
            corps += "<h1 class=\"titre\" id=\"titre\">\(esc(meta.titre))</h1>\n"
            toc.append((1, "titre", meta.titre))
        }

        for b in blocks {
            switch b {
            case .heading(let niveau, let r):
                n += 1
                let id = "t\(n)"
                let h = min(max(niveau, 1), 6)
                corps += "<h\(h) id=\"\(id)\">\(html(r))</h\(h)>\n"
                if h <= 2 { toc.append((h, id, texte(r))) }
            case .paragraph(let r):
                corps += "<p>\(html(r))</p>\n"
            case .quote(let r):
                corps += "<blockquote><p>\(html(r))</p></blockquote>\n"
            case .list(let ordonnee, let items):
                let tag = ordonnee ? "ol" : "ul"
                corps += "<\(tag)>\n" + items.map { "<li>\(html($0))</li>\n" }.joined() + "</\(tag)>\n"
            case .table(let lignes):
                corps += "<div class=\"tableau\"><table>\n"
                for (i, ligne) in lignes.enumerated() {
                    let cellule = i == 0 ? "th" : "td"
                    corps += "<tr>" + ligne.map { "<\(cellule)>\(html($0))</\(cellule)>" }.joined() + "</tr>\n"
                }
                corps += "</table></div>\n"
            case .image(let img, let legende):
                let nom = "image-\(images.count + 1).\(img.isPNG ? "png" : "jpg")"
                images.append((nom, img))
                let alt = attr(img.alt.isEmpty ? texte(legende) : img.alt)
                corps += "<figure><img src=\"images/\(nom)\" alt=\"\(alt)\"/>"
                if !legende.isEmpty { corps += "<figcaption>\(html(legende))</figcaption>" }
                corps += "</figure>\n"
            case .notes(let titre, let items):
                corps += "<section class=\"notes\" epub:type=\"endnotes\" role=\"doc-endnotes\">\n"
                if !titre.isEmpty { corps += "<h2>\(html(titre))</h2>\n" }
                corps += "<ol>\n"
                for note in items {
                    corps += "<li id=\"note-\(attr(note.id))\" epub:type=\"endnote\" role=\"doc-endnote\">\(html(sansAdresseRepetee(note.runs)))</li>\n"
                }
                corps += "</ol></section>\n"
            }
        }

        var zip = OOXMLZip()
        zip.add("mimetype", Data("application/epub+zip".utf8))
        zip.add("META-INF/container.xml", xml: """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """)
        zip.add("OEBPS/content.opf", xml: opf(meta: meta, images: images.map { ($0.nom, $0.image.isPNG) },
                                              identifiant: identifiant, maintenant: maintenant,
                                              mathml: corps.contains("<math")))
        zip.add("OEBPS/nav.xhtml", xml: nav(meta: meta, toc: toc))
        zip.add("OEBPS/style.css", xml: style)
        zip.add("OEBPS/texte.xhtml", xml: page(titre: meta.titre, langue: meta.langue, corps: corps))
        for (nom, img) in images { zip.add("OEBPS/images/\(nom)", img.data) }
        return zip.finalize()
    }

    // MARK: - Parties

    private static func opf(meta: EpubMeta, images: [(String, Bool)], identifiant: String, maintenant: Date,
                            mathml: Bool = false) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let modifie = f.string(from: maintenant)
        let auteur = meta.auteur.map { "    <dc:creator>\(esc($0))</dc:creator>\n" } ?? ""
        let manifesteImages = images.enumerated().map { i, e in
            "    <item id=\"img\(i + 1)\" href=\"images/\(e.0)\" media-type=\"\(e.1 ? "image/png" : "image/jpeg")\"/>\n"
        }.joined()
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="\(attr(meta.langue))">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="uid">urn:uuid:\(attr(identifiant))</dc:identifier>
                <dc:title>\(esc(meta.titre))</dc:title>
                <dc:language>\(esc(meta.langue))</dc:language>
                <dc:date>\(esc(meta.date))</dc:date>
            \(auteur)    <dc:contributor>md Viewer</dc:contributor>
                <meta property="dcterms:modified">\(modifie)</meta>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="texte" href="texte.xhtml" media-type="application/xhtml+xml"\(mathml ? " properties=\"mathml\"" : "")/>
                <item id="style" href="style.css" media-type="text/css"/>
            \(manifesteImages)  </manifest>
              <spine>
                <itemref idref="texte"/>
              </spine>
            </package>
            """
    }

    private static func nav(meta: EpubMeta, toc: [(niveau: Int, id: String, texte: String)]) -> String {
        // Les ## sous leur #, les # au premier niveau ; un ## sans # au-dessus reste au premier.
        var liste = ""
        var ouvert = false   // une sous-liste ouverte sous le dernier #
        var item = false     // un <li> de premier niveau ouvert
        for e in toc {
            let lien = "<a href=\"texte.xhtml#\(e.id)\">\(esc(e.texte))</a>"
            if e.niveau == 2 && item {
                if !ouvert { liste += "<ol>"; ouvert = true }
                liste += "<li>\(lien)</li>"
            } else {
                if ouvert { liste += "</ol>"; ouvert = false }
                if item { liste += "</li>\n" }
                liste += "<li>\(lien)"
                item = true
            }
        }
        if ouvert { liste += "</ol>" }
        if item { liste += "</li>\n" }
        if liste.isEmpty { liste = "<li><a href=\"texte.xhtml\">\(esc(meta.titre))</a></li>\n" }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(attr(meta.langue))" xml:lang="\(attr(meta.langue))">
            <head><meta charset="UTF-8"/><title>\(esc(meta.titre))</title></head>
            <body>
            <nav epub:type="toc" id="toc"><h1>\(esc(meta.titre))</h1>
            <ol>
            \(liste)</ol>
            </nav>
            </body>
            </html>
            """
    }

    private static func page(titre: String, langue: String, corps: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(attr(langue))" xml:lang="\(attr(langue))">
        <head><meta charset="UTF-8"/><title>\(esc(titre))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body>
        \(corps)</body>
        </html>
        """
    }

    private static let style = """
        body { font-family: serif; line-height: 1.5; margin: 0 1em; }
        h1, h2, h3, h4 { font-family: sans-serif; line-height: 1.25; page-break-after: avoid; }
        h1.titre { margin-top: 2em; }
        a { color: #B5651D; text-decoration: none; }
        figure { margin: 1em 0; text-align: center; page-break-inside: avoid; }
        figure img { max-width: 100%; height: auto; }
        figcaption { font-size: 0.85em; font-style: italic; color: #555; }
        blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid #E8972E; color: #444; }
        code { font-family: monospace; font-size: 0.9em; }
        .tableau { overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; font-size: 0.85em; }
        th, td { border: 1px solid #ccc; padding: 0.3em 0.4em; vertical-align: top; text-align: left; overflow-wrap: anywhere; }
        th { background: #f3efe8; }
        .notes { font-size: 0.85em; border-top: 1px solid #ccc; margin-top: 2em; }
        sup a { font-size: 0.8em; }
        """

    // MARK: - Texte

    /// Le modèle ajoute « — adresse » au bout d'une note, pour Word qui perdait le lien ; l'ePub
    /// garde le lien cliquable, l'adresse répétée en clair est retirée.
    private static func sansAdresseRepetee(_ runs: [OOXMLRun]) -> [OOXMLRun] {
        guard let dernier = runs.last, dernier.text.hasPrefix(" — ") else { return runs }
        let adresse = String(dernier.text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return runs.dropLast().contains { $0.lien == adresse } ? Array(runs.dropLast()) : runs
    }

    private static func texte(_ r: [OOXMLRun]) -> String {
        r.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func html(_ runs: [OOXMLRun]) -> String {
        runs.map { r -> String in
            if let note = r.note {
                return "<sup><a href=\"#note-\(attr(note))\" epub:type=\"noteref\" role=\"doc-noteref\">\(esc(r.text))</a></sup>"
            }
            // Une formule (26/11/2026) : son MathML, que Livres affiche et que VoiceOver lit.
            if let m = r.mathml, r.formuleEntiere, m.hasPrefix("<math") { return m }
            var s = esc(r.text).replacingOccurrences(of: "\n", with: "<br/>")
            if r.code { s = "<code>\(s)</code>" }
            if r.italic { s = "<em>\(s)</em>" }
            if r.bold { s = "<strong>\(s)</strong>" }
            if let lien = r.lien, lien.lowercased().hasPrefix("http") || lien.lowercased().hasPrefix("mailto:") {
                s = "<a href=\"\(attr(lien))\">\(s)</a>"
            }
            return s
        }.joined()
    }

    /// Le texte échappé pour XML, sans les caractères de contrôle que XML refuse.
    static func esc(_ s: String) -> String {
        var propre = String.UnicodeScalarView()
        for u in s.unicodeScalars where u.value >= 0x20 || u == "\n" || u == "\t" || u == "\r" {
            propre.append(u)
        }
        return String(propre)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func attr(_ s: String) -> String {
        esc(s).replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "\n", with: " ")
    }
}
