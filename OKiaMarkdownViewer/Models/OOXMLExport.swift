import Foundation

// ============================================================================
//  OOXML export — minimal, dependency-free generator for Word (.docx) and
//  PowerPoint (.pptx). Both are ZIP packages of XML; we write the ZIP ourselves
//  (STORED entries, no compression — valid and robust) and build the parts.
//
//  The document/slide model is filled by the JS side (it walks the rendered DOM
//  and returns an ordered list of blocks, with images already rasterised to
//  PNG/JPEG bytes). This file is pure Foundation so it can be unit-validated
//  outside the app.
// ============================================================================

// MARK: - Model

/// One inline run of text with simple formatting.
struct OOXMLRun: Equatable {
    var text: String
    var bold = false
    var italic = false
    var code = false
    /// Un appel de note : l'identifiant de la note (`3` pour `[^3]`), `text` portant le numéro
    /// affiché. Word en fait une vraie note de fin.
    var note: String? = nil
    /// Les annotations de l'utilisateur (1.4) : la couleur de surlignage de Word (`yellow`,
    /// `green`, `magenta`, `cyan`), et la couleur d'un soulignement (hexadécimal).
    var surligne: String? = nil
    var souligne: String? = nil
}

/// Un commentaire de relecture (1.4) : une note manuscrite de l'utilisateur, ancrée à un bloc.
struct OOXMLCommentaire: Equatable {
    var bloc: Int
    var texte: String
    var image: OOXMLImage?
}

/// Une note de bas de page du document, telle que la section Notes la porte.
struct OOXMLNote: Equatable {
    var id: String
    var label: String
    var runs: [OOXMLRun]
}

/// An embedded raster image (already decoded bytes + pixel size + mime).
struct OOXMLImage: Equatable {
    var data: Data
    var widthPx: Int
    var heightPx: Int
    var isPNG: Bool            // true → png, false → jpeg
}

/// A document/slide block in reading order.
enum OOXMLBlock: Equatable {
    case heading(level: Int, runs: [OOXMLRun])
    case paragraph(runs: [OOXMLRun])
    case quote(runs: [OOXMLRun])
    case list(ordered: Bool, items: [[OOXMLRun]])
    case table(rows: [[[OOXMLRun]]])          // rows → cells → runs
    case image(OOXMLImage, caption: [OOXMLRun])
    /// La section Notes : Word la remplace par des notes de fin quand le texte les appelle.
    case notes(title: [OOXMLRun], items: [OOXMLNote])
}

// MARK: - XML helpers

enum XML {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - ZIP writer (STORED)

struct OOXMLZip {
    private struct Entry { let name: String; let data: Data; let crc: UInt32; let offset: Int }
    private var entries: [Entry] = []
    private var buffer = Data()

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    mutating func add(_ name: String, _ data: Data) {
        let crc = Self.crc32(data)
        let offset = buffer.count
        let nameBytes = Array(name.utf8)
        var h = [UInt8]()
        h += le32(0x04034b50)                       // local file header sig
        h += le16(20)                               // version needed
        h += le16(0)                                // flags
        h += le16(0)                                // method: stored
        h += le16(0); h += le16(0)                  // mod time/date
        h += le32(crc)
        h += le32(UInt32(data.count))               // compressed size
        h += le32(UInt32(data.count))               // uncompressed size
        h += le16(UInt16(nameBytes.count))
        h += le16(0)                                // extra len
        h += nameBytes
        buffer.append(contentsOf: h)
        buffer.append(data)
        entries.append(Entry(name: name, data: data, crc: crc, offset: offset))
    }

    mutating func add(_ name: String, xml: String) { add(name, Data(xml.utf8)) }

    func finalize() -> Data {
        var out = buffer
        let cdStart = out.count
        for e in entries {
            let nameBytes = Array(e.name.utf8)
            var h = [UInt8]()
            h += le32(0x02014b50)                   // central dir header sig
            h += le16(20); h += le16(20)            // version made by / needed
            h += le16(0); h += le16(0)              // flags / method
            h += le16(0); h += le16(0)              // time/date
            h += le32(e.crc)
            h += le32(UInt32(e.data.count)); h += le32(UInt32(e.data.count))
            h += le16(UInt16(nameBytes.count))
            h += le16(0); h += le16(0)              // extra / comment len
            h += le16(0); h += le16(0)              // disk / internal attrs
            h += le32(0)                            // external attrs
            h += le32(UInt32(e.offset))
            h += nameBytes
            out.append(contentsOf: h)
        }
        let cdSize = out.count - cdStart
        var eocd = [UInt8]()
        eocd += le32(0x06054b50)
        eocd += le16(0); eocd += le16(0)
        eocd += le16(UInt16(entries.count)); eocd += le16(UInt16(entries.count))
        eocd += le32(UInt32(cdSize)); eocd += le32(UInt32(cdStart))
        eocd += le16(0)
        out.append(contentsOf: eocd)
        return out
    }
}

// MARK: - Units

enum EMU {
    static let perInch = 914_400
    static let perPx = 9525                    // 96 dpi
    static func px(_ p: Int) -> Int { p * perPx }
}

// MARK: - DOCX builder

enum DocxBuilder {
    /// Build a .docx from ordered blocks. `title` becomes a Title-styled heading.
    static func build(title: String, blocks: [OOXMLBlock], commentaires: [OOXMLCommentaire] = []) -> Data {
        var images: [(name: String, img: OOXMLImage)] = []
        var rels = ""
        var relId = 0

        // Les notes du document, par identifiant. Chaque appel devient une note de fin, que
        // Word numérote lui-même : il ne connaît pas la note appelée deux fois, un second appel
        // en fait donc une seconde note, au même texte.
        var notesParId: [String: OOXMLNote] = [:]
        for case .notes(_, let items) in blocks { for n in items { notesParId[n.id] = n } }
        var notesDeFin: [String] = []

        func runXML(_ r: OOXMLRun) -> String {
            if let id = r.note {
                guard let note = notesParId[id] else {
                    return "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:t>\(XML.esc(r.text))</w:t></w:r>"
                }
                let numero = notesDeFin.count + 1
                notesDeFin.append("<w:endnote w:id=\"\(numero)\"><w:p><w:pPr><w:pStyle w:val=\"EndnoteText\"/></w:pPr>" +
                                  "<w:r><w:rPr><w:rStyle w:val=\"EndnoteReference\"/></w:rPr><w:endnoteRef/></w:r>" +
                                  "<w:r><w:t xml:space=\"preserve\"> </w:t></w:r>" +
                                  note.runs.map(runXML).joined() + "</w:p></w:endnote>")
                return "<w:r><w:rPr><w:rStyle w:val=\"EndnoteReference\"/></w:rPr><w:endnoteReference w:id=\"\(numero)\"/></w:r>"
            }
            var props = ""
            if r.bold { props += "<w:b/>" }
            if r.italic { props += "<w:i/>" }
            if r.code { props += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\"/>" }
            // Les annotations (1.4), dans l'ordre du schéma de Word : u, puis highlight.
            if let c = r.souligne { props += "<w:u w:val=\"single\" w:color=\"\(c)\"/>" }
            if let h = r.surligne { props += "<w:highlight w:val=\"\(h)\"/>" }
            let rPr = props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>"
            return "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(XML.esc(r.text))</w:t></w:r>"
        }
        func runsXML(_ runs: [OOXMLRun]) -> String { runs.map(runXML).joined() }

        // Les commentaires du bloc en cours (1.4) : ils encadrent son premier paragraphe.
        var commentairesDuBloc: [Int] = []
        var commentairesXML: [String] = []
        var imagesCommentaires: [(name: String, img: OOXMLImage)] = []
        func encadrer(_ contenu: String) -> String {
            guard !commentairesDuBloc.isEmpty else { return contenu }
            let ids = commentairesDuBloc
            commentairesDuBloc = []
            return ids.map { "<w:commentRangeStart w:id=\"\($0)\"/>" }.joined() + contenu
                + ids.map { "<w:commentRangeEnd w:id=\"\($0)\"/><w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr><w:commentReference w:id=\"\($0)\"/></w:r>" }.joined()
        }

        func para(_ runs: [OOXMLRun], style: String? = nil) -> String {
            let pPr = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
            return "<w:p>\(pPr)\(encadrer(runsXML(runs)))</w:p>"
        }

        /// Un commentaire : son texte, et l'image de la note manuscrite (relation propre à
        /// comments.xml).
        func commentaireXML(_ c: OOXMLCommentaire, id: Int) -> String {
            var corps = "<w:p><w:pPr><w:pStyle w:val=\"CommentText\"/></w:pPr><w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr><w:annotationRef/></w:r><w:r><w:t xml:space=\"preserve\">\(XML.esc(c.texte))</w:t></w:r></w:p>"
            if let img = c.image {
                let n = imagesCommentaires.count + 1
                imagesCommentaires.append(("note\(n).png", img))
                let maxW = EMU.perInch * 3
                var w = EMU.px(img.widthPx), h = EMU.px(img.heightPx)
                if w > maxW { h = h * maxW / max(w, 1); w = maxW }
                let docPrId = 1000 + n
                corps += "<w:p><w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
                    + "<wp:extent cx=\"\(w)\" cy=\"\(h)\"/><wp:docPr id=\"\(docPrId)\" name=\"Note\(n)\"/>"
                    + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
                    + "<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
                    + "<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
                    + "<pic:nvPicPr><pic:cNvPr id=\"\(docPrId)\" name=\"Note\(n)\"/><pic:cNvPicPr/></pic:nvPicPr>"
                    + "<pic:blipFill><a:blip r:embed=\"rIdNote\(n)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
                    + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(w)\" cy=\"\(h)\"/></a:xfrm>"
                    + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>"
                    + "</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
            }
            return "<w:comment w:id=\"\(id)\" w:author=\"md Viewer\" w:initials=\"md\">\(corps)</w:comment>"
        }

        func imageXML(_ img: OOXMLImage) -> String {
            relId += 1
            let rid = "rId\(relId)"
            let name = "image\(images.count + 1).\(img.isPNG ? "png" : "jpeg")"
            images.append((name, img))
            rels += "<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(name)\"/>"
            // Fit within a ~6.0in content width.
            let maxW = EMU.perInch * 6
            var w = EMU.px(img.widthPx), h = EMU.px(img.heightPx)
            if w > maxW { h = h * maxW / max(w, 1); w = maxW }
            let docPrId = images.count
            return """
            <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>\
            <wp:inline distT="0" distB="0" distL="0" distR="0">\
            <wp:extent cx="\(w)" cy="\(h)"/>\
            <wp:docPr id="\(docPrId)" name="Image\(docPrId)"/>\
            <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">\
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
            <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
            <pic:nvPicPr><pic:cNvPr id="\(docPrId)" name="Image\(docPrId)"/><pic:cNvPicPr/></pic:nvPicPr>\
            <pic:blipFill><a:blip r:embed="\(rid)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
            <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(w)" cy="\(h)"/></a:xfrm>\
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>\
            </a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
            """
        }

        func tableXML(_ rows: [[[OOXMLRun]]]) -> String {
            let border = "<w:tblBorders><w:top w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:left w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:bottom w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:right w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:insideH w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/></w:tblBorders>"
            var t = "<w:tbl><w:tblPr><w:tblW w:w=\"5000\" w:type=\"pct\"/>\(border)</w:tblPr>"
            for (ri, row) in rows.enumerated() {
                t += "<w:tr>"
                for cell in row {
                    let shd = ri == 0 ? "<w:tcPr><w:shd w:val=\"clear\" w:fill=\"EAE8E2\"/></w:tcPr>" : ""
                    var runs = cell
                    if ri == 0 { runs = runs.map { var r = $0; r.bold = true; return r } }
                    t += "<w:tc>\(shd)\(para(runs))</w:tc>"
                }
                t += "</w:tr>"
            }
            return t + "</w:tbl>"
        }

        var body = ""
        if !title.isEmpty { body += para([OOXMLRun(text: title)], style: "Title") }
        for (indice, block) in blocks.enumerated() {
            for c in commentaires where c.bloc == indice {
                let id = commentairesXML.count
                commentairesXML.append(commentaireXML(c, id: id))
                commentairesDuBloc.append(id)
            }
            switch block {
            case .heading(let level, let runs):
                body += para(runs, style: "Heading\(min(max(level, 1), 4))")
            case .paragraph(let runs):
                body += para(runs)
            case .quote(let runs):
                body += para(runs, style: "Quote")
            case .list(let ordered, let items):
                for item in items {
                    body += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(ordered ? 2 : 1)\"/></w:numPr></w:pPr>\(encadrer(runsXML(item)))</w:p>"
                }
            case .table(let rows):
                body += tableXML(rows)
                body += "<w:p/>"
            case .image(let img, let caption):
                body += imageXML(img)
                if !caption.isEmpty { body += para(caption, style: "Caption") }
            case .notes(let title, let items):
                // Appelées dans le texte, elles sont déjà des notes de fin ; sinon, une liste.
                let appelees = blocks.contains { b in
                    switch b {
                    case .paragraph(let r), .quote(let r), .heading(_, let r): return r.contains { $0.note != nil }
                    case .list(_, let its): return its.contains { $0.contains { $0.note != nil } }
                    case .table(let rows): return rows.contains { $0.contains { $0.contains { $0.note != nil } } }
                    default: return false
                    }
                }
                if !appelees {
                    if !title.isEmpty { body += para(title, style: "Heading2") }
                    for n in items {
                        body += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"2\"/></w:numPr></w:pPr>\(runsXML(n.runs))</w:p>"
                    }
                }
            }
        }
        let avecNotes = !notesDeFin.isEmpty
        let avecCommentaires = !commentairesXML.isEmpty

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <w:body>\(body)<w:sectPr>\(avecNotes ? "<w:endnotePr><w:numFmt w:val=\"decimal\"/></w:endnotePr>" : "")<w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>
        """

        var zip = OOXMLZip()
        zip.add("[Content_Types].xml", xml: contentTypes(avecNotes: avecNotes, avecCommentaires: avecCommentaires))
        zip.add("_rels/.rels", xml: rootRels)
        zip.add("word/document.xml", xml: document)
        zip.add("word/styles.xml", xml: stylesXML)
        zip.add("word/numbering.xml", xml: numberingXML)
        if avecNotes {
            zip.add("word/endnotes.xml", xml: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:endnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
            <w:endnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:endnote>\
            <w:endnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:endnote>\
            \(notesDeFin.joined())</w:endnotes>
            """)
            zip.add("word/settings.xml", xml: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
            <w:endnotePr><w:numFmt w:val="decimal"/><w:endnote w:id="-1"/><w:endnote w:id="0"/></w:endnotePr></w:settings>
            """)
        }
        if avecCommentaires {
            zip.add("word/comments.xml", xml: "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                + "<w:comments xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
                + commentairesXML.joined() + "</w:comments>")
            let relsNotes = imagesCommentaires.enumerated().map { i, e in
                "<Relationship Id=\"rIdNote\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(e.name)\"/>"
            }.joined()
            zip.add("word/_rels/comments.xml.rels", xml: "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relsNotes)</Relationships>")
            for e in imagesCommentaires { zip.add("word/media/\(e.name)", e.img.data) }
        }
        let commentairesRels = avecCommentaires
            ? "<Relationship Id=\"rIdComments\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments\" Target=\"comments.xml\"/>"
            : ""
        let notesRels = avecNotes
            ? "<Relationship Id=\"rIdEndnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes\" Target=\"endnotes.xml\"/>" +
              "<Relationship Id=\"rIdSettings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>"
            : ""
        let docRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        <Relationship Id="rIdNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>\
        \(notesRels)\(commentairesRels)\(rels)</Relationships>
        """
        zip.add("word/_rels/document.xml.rels", xml: docRels)
        for entry in images { zip.add("word/media/\(entry.name)", entry.img.data) }
        return zip.finalize()
    }

    private static func contentTypes(avecNotes: Bool, avecCommentaires: Bool) -> String { """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Default Extension="png" ContentType="image/png"/>\
    <Default Extension="jpeg" ContentType="image/jpeg"/>\
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
    <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
    \(avecNotes ? "<Override PartName=\"/word/endnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml\"/><Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>" : "")\
    \(avecCommentaires ? "<Override PartName=\"/word/comments.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml\"/>" : "")\
    </Types>
    """ }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Helvetica Neue" w:hAnsi="Helvetica Neue"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>\
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>\
    <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:pPr><w:spacing w:after="240"/></w:pPr><w:rPr><w:b/><w:sz w:val="56"/><w:color w:val="111111"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:color w:val="111111"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:pPr><w:spacing w:before="200" w:after="100"/></w:pPr><w:rPr><w:b/><w:sz w:val="30"/><w:color w:val="1A1A1A"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:pPr><w:spacing w:before="160" w:after="80"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:pPr><w:spacing w:before="140" w:after="80"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:pPr><w:ind w:left="480"/><w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="E8972E"/></w:pBdr><w:spacing w:before="120" w:after="120"/></w:pPr><w:rPr><w:i/><w:color w:val="555555"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="Caption"/><w:pPr><w:jc w:val="center"/><w:spacing w:after="160"/></w:pPr><w:rPr><w:i/><w:sz w:val="18"/><w:color w:val="777777"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:pPr><w:ind w:left="420"/></w:pPr></w:style>\
    <w:style w:type="paragraph" w:styleId="EndnoteText"><w:name w:val="endnote text"/><w:pPr><w:spacing w:after="60"/></w:pPr><w:rPr><w:sz w:val="18"/></w:rPr></w:style>\
    <w:style w:type="character" w:styleId="EndnoteReference"><w:name w:val="endnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="CommentText"><w:name w:val="annotation text"/><w:rPr><w:sz w:val="20"/></w:rPr></w:style>\
    <w:style w:type="character" w:styleId="CommentReference"><w:name w:val="annotation reference"/><w:rPr><w:sz w:val="16"/></w:rPr></w:style>\
    </w:styles>
    """

    private static let numberingXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:pPr><w:ind w:left="420" w:hanging="240"/></w:pPr></w:lvl></w:abstractNum>\
    <w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:pPr><w:ind w:left="420" w:hanging="240"/></w:pPr></w:lvl></w:abstractNum>\
    <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>\
    <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>\
    </w:numbering>
    """
}

// MARK: - PPTX builder (mixed: editable text + tables + images)

/// One slide: a title plus ordered content blocks (text, lists, quotes, native
/// editable tables, and rasterised media images).
struct PptxSlide {
    var title: [OOXMLRun]
    var blocks: [OOXMLBlock]
    /// Les notes de l'orateur (1.5) : elles vont dans la page de notes de la diapositive, celle
    /// que l'import PowerPoint relit.
    var notes: String = ""
}

/// Le thème « à vos couleurs » (1.6) dans le PowerPoint : fond, texte, accent et police dans le
/// thème et le masque, le logo dans la disposition (sur toutes les diapositives). Couleurs sans « # ».
struct MarquePptx {
    var fond: String
    var texte: String
    var accent: String
    var police: String
    var logo: Data?
}

enum PptxBuilder {
    // 16:9 slide, EMU.
    static let slideW = 12192000, slideH = 6858000
    static let marginX = 457200          // 0.5in
    static let titleTop = 274638, titleH = 1106424
    static let contentTop = 1490000
    static var contentW: Int { slideW - marginX * 2 }
    static var contentBottom: Int { slideH - 365760 }
    static var contentH: Int { contentBottom - contentTop }

    private enum Item {
        case text([OOXMLBlock])           // contiguous paragraph/list/quote
        case table([[[OOXMLRun]]])
        case image(OOXMLImage)
    }

    static func build(slides: [PptxSlide], transition: String? = nil, marque: MarquePptx? = nil) -> Data {
        let entree = transitionXML(transition)
        var zip = OOXMLZip()
        var slideOverrides = ""
        var presRels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        var sldIdList = ""
        // Les pages de notes demandent un masque des notes : il n'est écrit que si une diapositive
        // a des notes, et le fichier d'une présentation sans notes reste ce qu'il était.
        let avecNotes = slides.contains { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let ridMasqueNotes = "rId\(slides.count + 2)"

        for (i, slide) in slides.enumerated() {
            let n = i + 1
            let rid = "rId\(n + 1)"
            var images: [(name: String, img: OOXMLImage)] = []
            var xml = slideXML(slide, slideIndex: n, images: &images, transition: entree)
            if let marque { xml = teinter(xml, marque) }
            zip.add("ppt/slides/slide\(n).xml", xml: xml)

            var rels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>"
            for (k, entry) in images.enumerated() {
                rels += "<Relationship Id=\"rIdImg\(k + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(entry.name)\"/>"
                zip.add("ppt/media/\(entry.name)", entry.img.data)
            }
            if !slide.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rels += "<Relationship Id=\"rIdNotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide\" Target=\"../notesSlides/notesSlide\(n).xml\"/>"
                zip.add("ppt/notesSlides/notesSlide\(n).xml", xml: notesXML(slide.notes))
                zip.add("ppt/notesSlides/_rels/notesSlide\(n).xml.rels", xml: relsDoc(
                    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" Target=\"../notesMasters/notesMaster1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"../slides/slide\(n).xml\"/>"))
                slideOverrides += "<Override PartName=\"/ppt/notesSlides/notesSlide\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml\"/>"
            }
            zip.add("ppt/slides/_rels/slide\(n).xml.rels", xml: relsDoc(rels))

            slideOverrides += "<Override PartName=\"/ppt/slides/slide\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
            presRels += "<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(n).xml\"/>"
            sldIdList += "<p:sldId id=\"\(255 + n)\" r:id=\"\(rid)\"/>"
        }

        if avecNotes {
            presRels += "<Relationship Id=\"\(ridMasqueNotes)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" Target=\"notesMasters/notesMaster1.xml\"/>"
            slideOverrides += "<Override PartName=\"/ppt/notesMasters/notesMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml\"/>"
                + "<Override PartName=\"/ppt/theme/theme2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
            zip.add("ppt/notesMasters/notesMaster1.xml", xml: notesMaster)
            zip.add("ppt/notesMasters/_rels/notesMaster1.xml.rels", xml: relsDoc(
                "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme2.xml\"/>"))
            zip.add("ppt/theme/theme2.xml", xml: theme(marque))
        }
        zip.add("[Content_Types].xml", xml: contentTypes(slideOverrides))
        zip.add("_rels/.rels", xml: rootRels)
        zip.add("ppt/presentation.xml", xml: presentationXML(sldIdList, masqueNotes: avecNotes ? ridMasqueNotes : nil))
        zip.add("ppt/_rels/presentation.xml.rels", xml: relsDoc(presRels))
        zip.add("ppt/slideMasters/slideMaster1.xml", xml: masque(marque))
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", xml: relsDoc(
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme1.xml\"/>"))
        // Le logo du thème « à vos couleurs », en bas à droite de chaque diapositive.
        var logoXML = "", logoRel = ""
        if let logo = marque?.logo, let image = UIImageTaille.taille(logo) {
            zip.add("ppt/media/marque-logo.png", logo)
            logoRel = "<Relationship Id=\"rIdLogo\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/marque-logo.png\"/>"
            let hMax = 560_000, wMax = 1_700_000
            let ar = image.width / max(image.height, 1)
            var w = Int(Double(hMax) * ar), h = hMax
            if w > wMax { w = wMax; h = Int(Double(wMax) / max(ar, 0.01)) }
            logoXML = pictureXML(rid: "rIdLogo", id: 90, x: slideW - marginX / 2 - w, y: slideH - 240_000 - h, w: w, h: h)
        }
        zip.add("ppt/slideLayouts/slideLayout1.xml", xml: slideLayout.replacingOccurrences(of: "</p:grpSpPr></p:spTree>", with: "</p:grpSpPr>" + logoXML + "</p:spTree>"))
        zip.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", xml: relsDoc(
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/>" + logoRel))
        zip.add("ppt/theme/theme1.xml", xml: theme(marque))
        return zip.finalize()
    }

    // MARK: transitions

    /// L'élément `<p:transition>` qui rejoue dans PowerPoint la transition choisie au diaporama.
    /// Il se place après `<p:clrMapOvr>`, comme l'exige l'ordre de `CT_Slide`. Chaque transition de
    /// md Viewer a son équivalent natif, dans le sens « suivante » — c'est celui que PowerPoint
    /// joue. Échelle, Retournement, Cube et Damier n'existent qu'à partir de PowerPoint 2010 (espace
    /// `p14`) : ils passent par `mc:AlternateContent`, avec un repli — un fondu, le damier classique
    /// pour le Damier — pour les lecteurs qui ne les connaissent pas, Keynote compris, qui importe
    /// alors le repli plutôt que de refuser le fichier.
    static func transitionXML(_ key: String?) -> String {
        func t(_ vitesse: String, _ effet: String) -> String {
            "<p:transition spd=\"\(vitesse)\">\(effet)</p:transition>"
        }
        func p14(_ vitesse: String, _ effet: String, repli: String = "<p:fade/>") -> String {
            "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\">"
            + "<mc:Choice xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" Requires=\"p14\">"
            + t(vitesse, effet) + "</mc:Choice><mc:Fallback>" + t(vitesse, repli)
            + "</mc:Fallback></mc:AlternateContent>"
        }
        switch key {
        case "dissolve": return t("fast", "<p:fade/>")
        case "push":     return t("med", "<p:push dir=\"l\"/>")
        case "movein":   return t("fast", "<p:cover dir=\"l\"/>")
        // `<p:zoom>` est l'ancienne « boîte » de PowerPoint, pas un zoom — vérifié en le lui
        // faisant lire. Notre « Échelle » est son « Fly Through » : la courante grandit et
        // s'efface, la suivante arrive de plus petit.
        case "scale":    return p14("fast", "<p14:flythrough hasBounce=\"0\"/>")
        case "flip":     return p14("med", "<p14:flip dir=\"l\"/>")
        case "wipe":     return t("med", "<p:wipe dir=\"l\"/>")
        case "reveal":   return t("fast", "<p:pull dir=\"l\"/>")
        case "cube":     return p14("med", "<p14:prism dir=\"l\"/>")
        case "iris":     return t("med", "<p:circle/>")
        case "black":    return t("slow", "<p:fade thruBlk=\"1\"/>")
        // Notre damier fait pivoter des cases au hasard : PowerPoint n'a pas de cases carrées qui
        // tournent, son « Scintillement » en losanges est le plus proche. Le damier classique,
        // un balayage, reste le repli.
        case "checker":  return p14("slow", "<p14:glitter dir=\"l\" pattern=\"diamond\"/>",
                                    repli: "<p:checker dir=\"horz\"/>")
        default:         return ""
        }
    }

    // MARK: per-slide layout

    private static func slideXML(_ slide: PptxSlide, slideIndex: Int, images: inout [(name: String, img: OOXMLImage)],
                                 transition: String = "") -> String {
        var id = 1
        func nextId() -> Int { id += 1; return id }
        var shapes = ""

        // Title placeholder.
        if !slide.title.isEmpty {
            shapes += """
            <p:sp><p:nvSpPr><p:cNvPr id="\(nextId())" name="Title"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>\
            <p:spPr><a:xfrm><a:off x="\(marginX)" y="\(titleTop)"/><a:ext cx="\(contentW)" cy="\(titleH)"/></a:xfrm></p:spPr>\
            <p:txBody><a:bodyPr/><a:lstStyle/><a:p>\(runsAXML(slide.title, size: 3200, bold: true))</a:p></p:txBody></p:sp>
            """
        }

        // Group contiguous text blocks; tables and images are standalone.
        var items: [Item] = []
        var textRun: [OOXMLBlock] = []
        func flush() { if !textRun.isEmpty { items.append(.text(textRun)); textRun = [] } }
        for b in slide.blocks {
            switch b {
            case .heading, .paragraph, .quote, .list: textRun.append(b)
            case .notes(let title, let notes):
                if !title.isEmpty { textRun.append(.heading(level: 2, runs: title)) }
                textRun.append(.list(ordered: true, items: notes.map(\.runs)))
            case .table(let rows): flush(); items.append(.table(rows))
            case .image(let img, _): flush(); items.append(.image(img))
            }
        }
        flush()

        // Natural heights, then scale to fit the content area.
        func natural(_ it: Item) -> Int {
            switch it {
            case .text(let blocks):
                var lines = 0
                for b in blocks {
                    switch b {
                    case .list(_, let items): lines += items.count
                    case .table: break
                    case .image: break
                    default: lines += 1
                    }
                }
                return max(1, lines) * 430000 + 120000
            case .table(let rows): return rows.count * 430000 + 80000
            case .image(let img):
                let ar = Double(img.widthPx) / Double(max(img.heightPx, 1))
                return Int(Double(contentW) / max(ar, 0.1))
            }
        }
        let gap = 160000
        let naturals = items.map(natural)
        let totalNat = naturals.reduce(0, +) + gap * max(0, items.count - 1)
        let scale = totalNat > contentH ? Double(contentH) / Double(totalNat) : 1.0

        var y = contentTop
        for (idx, it) in items.enumerated() {
            let h = max(200000, Int(Double(naturals[idx]) * scale))
            switch it {
            case .text(let blocks):
                shapes += textBoxXML(blocks, id: nextId(), x: marginX, y: y, w: contentW, h: h)
            case .table(let rows):
                shapes += tableXML(rows, id: nextId(), x: marginX, y: y, w: contentW, h: h)
            case .image(let img):
                let ar = Double(img.widthPx) / Double(max(img.heightPx, 1))
                var w = Int(Double(h) * ar)
                var hh = h
                if w > contentW { w = contentW; hh = Int(Double(contentW) / max(ar, 0.1)) }
                let x = marginX + (contentW - w) / 2
                let name = "image\(slideIndex)_\(images.count + 1).\(img.isPNG ? "png" : "jpeg")"
                let rid = "rIdImg\(images.count + 1)"
                images.append((name, img))
                shapes += pictureXML(rid: rid, id: nextId(), x: x, y: y, w: w, h: hh)
            }
            y += h + gap
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">\
        <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
        <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\
        \(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:overrideClrMapping bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:clrMapOvr>\(transition)</p:sld>
        """
    }

    // MARK: DrawingML helpers

    private static func runAXML(_ r: OOXMLRun, size: Int, bold: Bool) -> String {
        var rPr = "<a:rPr lang=\"fr-FR\" sz=\"\(size)\""
        if r.bold || bold { rPr += " b=\"1\"" }
        if r.italic { rPr += " i=\"1\"" }
        if r.note != nil { rPr += " baseline=\"30000\"" }
        rPr += ">"
        if r.code { rPr += "<a:latin typeface=\"Menlo\"/>" }
        rPr += "</a:rPr>"
        return "<a:r>\(rPr)<a:t>\(XML.esc(r.text))</a:t></a:r>"
    }
    private static func runsAXML(_ runs: [OOXMLRun], size: Int, bold: Bool) -> String {
        runs.map { runAXML($0, size: size, bold: bold) }.joined()
    }

    private static func textBoxXML(_ blocks: [OOXMLBlock], id: Int, x: Int, y: Int, w: Int, h: Int) -> String {
        var paras = ""
        for b in blocks {
            switch b {
            case .heading(_, let runs):
                paras += "<a:p>\(runsAXML(runs, size: 2200, bold: true))</a:p>"
            case .paragraph(let runs):
                paras += "<a:p>\(runsAXML(runs, size: 1800, bold: false))</a:p>"
            case .quote(let runs):
                paras += "<a:p><a:pPr><a:lnSpc><a:spcPct val=\"100000\"/></a:lnSpc></a:pPr>" +
                         runs.map { var r = $0; r.italic = true; return runAXML(r, size: 1800, bold: false) }.joined() + "</a:p>"
            case .list(let ordered, let items):
                for item in items {
                    let bu = ordered ? "<a:buAutoNum type=\"arabicPeriod\"/>" : "<a:buChar char=\"•\"/>"
                    paras += "<a:p><a:pPr marL=\"285750\" indent=\"-285750\">\(bu)</a:pPr>\(runsAXML(item, size: 1800, bold: false))</a:p>"
                }
            default: break
            }
        }
        if paras.isEmpty { paras = "<a:p><a:endParaRPr lang=\"fr-FR\"/></a:p>" }
        return """
        <p:sp><p:nvSpPr><p:cNvPr id="\(id)" name="Text \(id)"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>\
        <p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(w)" cy="\(h)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>\
        <p:txBody><a:bodyPr wrap="square" rtlCol="0"><a:normAutofit/></a:bodyPr><a:lstStyle/>\(paras)</p:txBody></p:sp>
        """
    }

    private static func tableXML(_ rows: [[[OOXMLRun]]], id: Int, x: Int, y: Int, w: Int, h: Int) -> String {
        let cols = rows.map { $0.count }.max() ?? 1
        let colW = w / max(cols, 1)
        let rowH = max(300000, h / max(rows.count, 1))
        var grid = ""
        for _ in 0..<cols { grid += "<a:gridCol w=\"\(colW)\"/>" }
        var trs = ""
        for (ri, row) in rows.enumerated() {
            var tcs = ""
            for ci in 0..<cols {
                let runs = ci < row.count ? row[ci] : []
                let header = ri == 0
                let cellRuns = header ? runs.map { var r = $0; r.bold = true; return r } : runs
                let body = "<a:p>\(runsAXML(cellRuns, size: 1600, bold: false))</a:p>"
                let fill = header ? "<a:solidFill><a:srgbClr val=\"EAE8E2\"/></a:solidFill>" : ""
                let bdr = "<a:lnL w=\"6350\"><a:solidFill><a:srgbClr val=\"BFBFBF\"/></a:solidFill></a:lnL><a:lnR w=\"6350\"><a:solidFill><a:srgbClr val=\"BFBFBF\"/></a:solidFill></a:lnR><a:lnT w=\"6350\"><a:solidFill><a:srgbClr val=\"BFBFBF\"/></a:solidFill></a:lnT><a:lnB w=\"6350\"><a:solidFill><a:srgbClr val=\"BFBFBF\"/></a:solidFill></a:lnB>"
                tcs += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>\(body)</a:txBody><a:tcPr marL=\"45720\" marR=\"45720\" marT=\"22860\" marB=\"22860\">\(bdr)\(fill)</a:tcPr></a:tc>"
            }
            trs += "<a:tr h=\"\(rowH)\">\(tcs)</a:tr>"
        }
        let cy = rowH * rows.count
        return """
        <p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="\(id)" name="Table \(id)"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>\
        <p:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(w)" cy="\(cy)"/></p:xfrm>\
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">\
        <a:tbl><a:tblPr firstRow="1"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr>\
        <a:tblGrid>\(grid)</a:tblGrid>\(trs)</a:tbl></a:graphicData></a:graphic></p:graphicFrame>
        """
    }

    private static func pictureXML(rid: String, id: Int, x: Int, y: Int, w: Int, h: Int) -> String {
        """
        <p:pic><p:nvPicPr><p:cNvPr id="\(id)" name="Image \(id)"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>\
        <p:blipFill><a:blip r:embed="\(rid)"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>\
        <p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(w)" cy="\(h)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>
        """
    }

    // MARK: boilerplate

    private static func relsDoc(_ inner: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(inner)</Relationships>"
    }

    private static func contentTypes(_ slideOverrides: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Default Extension="png" ContentType="image/png"/>\
        <Default Extension="jpeg" ContentType="image/jpeg"/>\
        <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>\
        <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>\
        <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>\
        <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\
        \(slideOverrides)</Types>
        """
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>\
    </Relationships>
    """

    private static func presentationXML(_ sldIdList: String, masqueNotes: String? = nil) -> String {
        // L'ordre de `CT_Presentation` : le masque des notes suit celui des diapositives.
        let notes = masqueNotes.map { "<p:notesMasterIdLst><p:notesMasterId r:id=\"\($0)\"/></p:notesMasterIdLst>" } ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">\
        <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>\(notes)\
        <p:sldIdLst>\(sldIdList)</p:sldIdLst>\
        <p:sldSz cx="\(slideW)" cy="\(slideH)" type="screen16x9"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>
        """
    }

    // MARK: notes de l'orateur (1.5)

    /// La page de notes d'une diapositive : l'image de la diapositive, puis le texte, un paragraphe
    /// par ligne.
    private static func notesXML(_ notes: String) -> String {
        let paras = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { l -> String in
                let t = l.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? "<a:p><a:endParaRPr lang=\"fr-FR\"/></a:p>"
                    : "<a:p><a:r><a:rPr lang=\"fr-FR\" dirty=\"0\"/><a:t>\(XML.esc(t))</a:t></a:r></a:p>"
            }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">\
        <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>\
        <p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>\
        <p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>\
        <p:txBody><a:bodyPr/><a:lstStyle/>\(paras)</p:txBody></p:sp>\
        </p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>
        """
    }

    /// Le masque des notes : la place de l'image de la diapositive et celle du texte, sur une page
    /// portrait (`notesSz`).
    private static let notesMaster = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">\
    <p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
    <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\
    <p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr>\
    <p:spPr><a:xfrm><a:off x="381000" y="685800"/><a:ext cx="6096000" cy="3429000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="12700"><a:solidFill><a:prstClr val="black"/></a:solidFill></a:ln></p:spPr></p:sp>\
    <p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" sz="quarter" idx="3"/></p:nvPr></p:nvSpPr>\
    <p:spPr><a:xfrm><a:off x="685800" y="4343400"/><a:ext cx="5486400" cy="4114800"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>\
    <p:txBody><a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0"/><a:lstStyle/><a:p><a:endParaRPr lang="fr-FR"/></a:p></p:txBody></p:sp>\
    </p:spTree></p:cSld>\
    <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>\
    <p:notesStyle><a:lvl1pPr marL="0" algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1"><a:defRPr sz="1200" kern="1200"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl1pPr></p:notesStyle>\
    </p:notesMaster>
    """

    /// Le masque, aux couleurs et à la police du thème « à vos couleurs » quand il y en a un.
    /// Les tableaux, avec un thème « à vos couleurs » : l'en-tête clair (EAE8E2) et les filets gris
    /// (BFBFBF) deviennent des nuances entre le fond et le texte, sinon un texte clair sur un fond
    /// sombre disparaissait dans l'en-tête.
    private static func teinter(_ xml: String, _ m: MarquePptx) -> String {
        // La couleur et la police sur chaque passage de texte : les zones de texte ne suivent pas le
        // masque dans Keynote ni dans Aperçu (texte noir en Helvetica sur le fond choisi). Le code
        // garde sa police à chasse fixe.
        let couleur = "<a:solidFill><a:srgbClr val=\"\(m.texte)\"/></a:solidFill>"
        return xml
            .replacingOccurrences(of: "><a:latin typeface=\"Menlo\"/></a:rPr>", with: ">\(couleur)<a:latin typeface=\"Menlo\"/></a:rPr>")
            .replacingOccurrences(of: "></a:rPr>", with: ">\(couleur)<a:latin typeface=\"\(XML.esc(m.police))\"/></a:rPr>")
            .replacingOccurrences(of: "srgbClr val=\"EAE8E2\"", with: "srgbClr val=\"\(melange(m.fond, m.texte, 0.16))\"")
            .replacingOccurrences(of: "srgbClr val=\"BFBFBF\"", with: "srgbClr val=\"\(melange(m.fond, m.texte, 0.35))\"")
    }

    /// Une couleur entre deux autres (« RRGGBB ») : `t` = 0 donne `a`, 1 donne `b`.
    static func melange(_ a: String, _ b: String, _ t: Double) -> String {
        func rvb(_ h: String) -> [Double] {
            let v = UInt32(h, radix: 16) ?? 0
            return [Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)]
        }
        let x = rvb(a), y = rvb(b)
        return (0..<3).map { String(format: "%02X", Int((x[$0] + (y[$0] - x[$0]) * t).rounded())) }.joined()
    }

    private static func masque(_ m: MarquePptx?) -> String {
        guard let m else { return slideMaster }
        // Les zones de texte (pas les espaces réservés) suivent `otherStyle` : sans couleur ni police,
        // Keynote et Aperçu les écrivaient en noir, en Helvetica, sur le fond choisi.
        let autre = "<a:defRPr lang=\"fr-FR\"><a:solidFill><a:srgbClr val=\"\(m.texte)\"/></a:solidFill><a:latin typeface=\"\(XML.esc(m.police))\"/></a:defRPr>"
        let niveaux = (1...3).map { "<a:lvl\($0)pPr>\(autre)</a:lvl\($0)pPr>" }.joined()
        return slideMaster
            .replacingOccurrences(of: "<p:otherStyle><a:defPPr><a:defRPr lang=\"fr-FR\"/></a:defPPr></p:otherStyle>",
                                  with: "<p:otherStyle><a:defPPr>\(autre)</a:defPPr>\(niveaux)</p:otherStyle>")
            .replacingOccurrences(of: "<a:srgbClr val=\"FFFFFF\"/></a:solidFill><a:effectLst/>", with: "<a:srgbClr val=\"\(m.fond)\"/></a:solidFill><a:effectLst/>")
            .replacingOccurrences(of: "<a:srgbClr val=\"111111\"/>", with: "<a:srgbClr val=\"\(m.texte)\"/>")
            .replacingOccurrences(of: "<a:srgbClr val=\"222222\"/>", with: "<a:srgbClr val=\"\(m.texte)\"/>")
            .replacingOccurrences(of: "typeface=\"Helvetica Neue\"", with: "typeface=\"\(XML.esc(m.police))\"")
    }

    /// Le thème, idem : fond (lt1), texte (dk1), accent (accent1) et polices.
    private static func theme(_ m: MarquePptx?) -> String {
        guard let m else { return theme1 }
        return theme1
            .replacingOccurrences(of: "<a:dk1><a:srgbClr val=\"111111\"/>", with: "<a:dk1><a:srgbClr val=\"\(m.texte)\"/>")
            .replacingOccurrences(of: "<a:lt1><a:srgbClr val=\"FFFFFF\"/>", with: "<a:lt1><a:srgbClr val=\"\(m.fond)\"/>")
            .replacingOccurrences(of: "<a:accent1><a:srgbClr val=\"E8972E\"/>", with: "<a:accent1><a:srgbClr val=\"\(m.accent)\"/>")
            .replacingOccurrences(of: "<a:hlink><a:srgbClr val=\"C9781A\"/>", with: "<a:hlink><a:srgbClr val=\"\(m.accent)\"/>")
            .replacingOccurrences(of: "typeface=\"Helvetica Neue\"", with: "typeface=\"\(XML.esc(m.police))\"")
    }

    private static let slideMaster = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">\
    <p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>\
    <p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
    <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>\
    <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>\
    <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>\
    <p:txStyles>\
    <p:titleStyle><a:lvl1pPr algn="l"><a:defRPr sz="3200" b="1"><a:solidFill><a:srgbClr val="111111"/></a:solidFill><a:latin typeface="Helvetica Neue"/></a:defRPr></a:lvl1pPr></p:titleStyle>\
    <p:bodyStyle><a:lvl1pPr><a:defRPr sz="1800"><a:solidFill><a:srgbClr val="222222"/></a:solidFill><a:latin typeface="Helvetica Neue"/></a:defRPr></a:lvl1pPr></p:bodyStyle>\
    <p:otherStyle><a:defPPr><a:defRPr lang="fr-FR"/></a:defPPr></p:otherStyle></p:txStyles></p:sldMaster>
    """

    private static let slideLayout = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">\
    <p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
    <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>\
    <p:clrMapOvr><a:overrideClrMapping bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:clrMapOvr></p:sldLayout>
    """

    private static let theme1 = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="OK-ia">\
    <a:themeElements><a:clrScheme name="OK-ia">\
    <a:dk1><a:srgbClr val="111111"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>\
    <a:dk2><a:srgbClr val="1A3A5C"/></a:dk2><a:lt2><a:srgbClr val="FAFAF8"/></a:lt2>\
    <a:accent1><a:srgbClr val="E8972E"/></a:accent1><a:accent2><a:srgbClr val="1A3A5C"/></a:accent2>\
    <a:accent3><a:srgbClr val="2D5A1B"/></a:accent3><a:accent4><a:srgbClr val="8B0000"/></a:accent4>\
    <a:accent5><a:srgbClr val="9A9A90"/></a:accent5><a:accent6><a:srgbClr val="F0A840"/></a:accent6>\
    <a:hlink><a:srgbClr val="C9781A"/></a:hlink><a:folHlink><a:srgbClr val="8B0000"/></a:folHlink></a:clrScheme>\
    <a:fontScheme name="OK-ia"><a:majorFont><a:latin typeface="Helvetica Neue"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>\
    <a:minorFont><a:latin typeface="Helvetica Neue"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>\
    <a:fmtScheme name="OK-ia">\
    <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>\
    <a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>\
    <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>\
    <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>\
    </a:fmtScheme></a:themeElements></a:theme>
    """
}

// MARK: - Bridge from the JS export model (app only)

#if canImport(UIKit)
import UIKit

/// Converts the JS `exportModel` JSON into OOXML blocks (downloading remote
/// images), then builds .docx / .pptx. App-only (uses UIKit/URLSession).
enum OOXMLExportBridge {

    private static func intOf(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        return 0
    }

    private static func runs(_ v: Any?) -> [OOXMLRun] {
        guard let a = v as? [[String: Any]] else { return [] }
        return a.map { OOXMLRun(text: $0["text"] as? String ?? "",
                                bold: $0["bold"] as? Bool ?? false,
                                italic: $0["italic"] as? Bool ?? false,
                                code: $0["code"] as? Bool ?? false,
                                note: $0["note"] as? String) }
    }

    private static func image(_ d: [String: Any], _ downloaded: [String: OOXMLImage]) -> OOXMLImage? {
        if let b64 = d["png"] as? String, let data = Data(base64Encoded: b64) {
            return OOXMLImage(data: data, widthPx: max(intOf(d["w"]), 1), heightPx: max(intOf(d["h"]), 1), isPNG: true)
        }
        // Rasterised maps arrive as JPEG: they are photographic, and PNG costs them roughly
        // 3.6× the bytes for no visible gain (measured 343 KB against 95 KB on one map).
        // Diagrams stay PNG — line art is exactly where PNG wins.
        if let b64 = d["jpeg"] as? String, let data = Data(base64Encoded: b64) {
            return OOXMLImage(data: data, widthPx: max(intOf(d["w"]), 1), heightPx: max(intOf(d["h"]), 1), isPNG: false)
        }
        if let src = d["src"] as? String {
            if src.hasPrefix("data:") { return imageDeDonnees(src) }
            return downloaded[src]
        }
        return nil
    }

    /// Une image en `data:` (1.5) : celles des documents importés (Word, PDF, PowerPoint),
    /// rangées dans le fichier en base64. Elles ne passaient pas par le téléchargement, réservé
    /// aux adresses `http`, et disparaissaient de l'export. Les SVG n'arrivent pas jusqu'ici :
    /// `render.js` les rastérise en PNG, que Word et PowerPoint lisent.
    private static func imageDeDonnees(_ src: String) -> OOXMLImage? {
        guard let virgule = src.firstIndex(of: ",") else { return nil }
        let entete = src[..<virgule].lowercased()
        let charge = String(src[src.index(after: virgule)...])
        let data: Data?
        if entete.hasSuffix(";base64") {
            data = Data(base64Encoded: charge, options: .ignoreUnknownCharacters)
        } else {
            data = charge.removingPercentEncoding.map { Data($0.utf8) }
        }
        return data.flatMap(imageOffice)
    }

    /// Des octets d'image, dans un format que Word et PowerPoint lisent : PNG et JPEG tels
    /// quels, le reste (GIF, WebP, HEIC…) converti en PNG.
    private static func imageOffice(_ data: Data) -> OOXMLImage? {
        guard let img = UIImage(data: data), let cg = img.cgImage else { return nil }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return OOXMLImage(data: data, widthPx: cg.width, heightPx: cg.height, isPNG: true)
        }
        if data.starts(with: [0xFF, 0xD8]) {
            return OOXMLImage(data: data, widthPx: cg.width, heightPx: cg.height, isPNG: false)
        }
        guard let png = img.pngData() else { return nil }
        return OOXMLImage(data: png, widthPx: cg.width, heightPx: cg.height, isPNG: true)
    }

    private static func block(_ d: [String: Any], _ downloaded: [String: OOXMLImage]) -> OOXMLBlock? {
        switch d["t"] as? String {
        case "heading":   return .heading(level: max(1, intOf(d["level"])), runs: runs(d["runs"]))
        case "paragraph": return .paragraph(runs: runs(d["runs"]))
        case "quote":     return .quote(runs: runs(d["runs"]))
        case "list":
            let items = (d["items"] as? [Any] ?? []).map { runs($0) }
            return .list(ordered: d["ordered"] as? Bool ?? false, items: items)
        case "table":
            let rows = (d["rows"] as? [Any] ?? []).map { row in (row as? [Any] ?? []).map { runs($0) } }
            return .table(rows: rows)
        case "image":
            if let img = image(d, downloaded) { return .image(img, caption: runs(d["caption"])) }
            return nil
        case "notes":
            let items = (d["items"] as? [[String: Any]] ?? []).map {
                OOXMLNote(id: $0["id"] as? String ?? "", label: $0["label"] as? String ?? "", runs: runs($0["runs"]))
            }
            return items.isEmpty ? nil : .notes(title: runs(d["title"]), items: items)
        case "map":
            let markers = (d["markers"] as? [String]) ?? []
            let text = "🗺 Carte — " + markers.joined(separator: " · ")
            return .paragraph(runs: [OOXMLRun(text: text, italic: true)])
        default: return nil
        }
    }

    /// Collect remote image URLs from a flat block array.
    private static func imageURLs(in blocks: [[String: Any]]) -> [String] {
        blocks.compactMap { ($0["t"] as? String) == "image" ? ($0["src"] as? String) : nil }
              .filter { $0.hasPrefix("http") }
    }

    private static func download(_ urls: [String], completion: @escaping ([String: OOXMLImage]) -> Void) {
        var out: [String: OOXMLImage] = [:]
        let group = DispatchGroup()
        let lock = NSLock()
        for s in Set(urls) {
            guard let url = URL(string: s) else { continue }
            group.enter()
            URLSession.shared.dataTask(with: url) { data, _, _ in
                defer { group.leave() }
                guard let data = data, let image = imageOffice(data) else { return }
                lock.lock()
                out[s] = image
                lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) { completion(out) }
    }

    // MARK: public

    /// Build a .docx from the report export model (flat block array).
    /// `annotations` (1.4) : celles du document, portées dans le Word (`AnnotationsWord`).
    static func buildDocx(title: String, model: [[String: Any]], annotations: [Annotation] = [],
                          completion: @escaping (Data?) -> Void) {
        download(imageURLs(in: model)) { imgs in
            let blocks = model.compactMap { block($0, imgs) }
            let annote = AnnotationsWord.appliquer(annotations, a: blocks, texteNote: tr("Note manuscrite (md Viewer)"))
            completion(DocxBuilder.build(title: title, blocks: annote.blocs, commentaires: annote.commentaires))
        }
    }

    /// Build a .pptx from the presentation export model ({slides:[{title,blocks}]}).
    @MainActor static func buildPptx(model: [String: Any], completion: @escaping (Data?) -> Void) {
        // Le thème « à vos couleurs » (1.6), quand c'est celui du diaporama.
        let marque = (model["theme"] as? String) == "marque" && AchatAnalytic.partage.acces
            ? ThemeMarque.actuel?.pptx : nil
        let rawSlides = (model["slides"] as? [[String: Any]]) ?? []
        let allBlocks = rawSlides.flatMap { ($0["blocks"] as? [[String: Any]]) ?? [] }
        download(imageURLs(in: allBlocks)) { imgs in
            let slides = rawSlides.map { s -> PptxSlide in
                let blocks = ((s["blocks"] as? [[String: Any]]) ?? []).compactMap { block($0, imgs) }
                return PptxSlide(title: runs(s["title"]), blocks: blocks, notes: (s["notes"] as? String) ?? "")
            }
            completion(PptxBuilder.build(slides: slides, transition: model["transition"] as? String, marque: marque))
        }
    }
}
#endif

/// La taille en pixels d'une image PNG ou JPEG (le logo du PowerPoint), sans UIKit.
enum UIImageTaille {
    static func taille(_ d: Data) -> (width: Double, height: Double)? {
        let o = [UInt8](d.prefix(32))
        // PNG : largeur et hauteur aux octets 16-23.
        if o.count >= 24, o[0] == 0x89, o[1] == 0x50 {
            let w = Int(o[16]) << 24 | Int(o[17]) << 16 | Int(o[18]) << 8 | Int(o[19])
            let h = Int(o[20]) << 24 | Int(o[21]) << 16 | Int(o[22]) << 8 | Int(o[23])
            return (Double(w), Double(h))
        }
        return nil
    }
}
