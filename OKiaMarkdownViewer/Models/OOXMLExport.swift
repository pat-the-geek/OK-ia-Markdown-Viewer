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
    static func build(title: String, blocks: [OOXMLBlock]) -> Data {
        var images: [(name: String, img: OOXMLImage)] = []
        var rels = ""
        var relId = 0

        func runXML(_ r: OOXMLRun) -> String {
            var props = ""
            if r.bold { props += "<w:b/>" }
            if r.italic { props += "<w:i/>" }
            if r.code { props += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\"/>" }
            let rPr = props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>"
            return "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(XML.esc(r.text))</w:t></w:r>"
        }
        func runsXML(_ runs: [OOXMLRun]) -> String { runs.map(runXML).joined() }

        func para(_ runs: [OOXMLRun], style: String? = nil) -> String {
            let pPr = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
            return "<w:p>\(pPr)\(runsXML(runs))</w:p>"
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
        for block in blocks {
            switch block {
            case .heading(let level, let runs):
                body += para(runs, style: "Heading\(min(max(level, 1), 4))")
            case .paragraph(let runs):
                body += para(runs)
            case .quote(let runs):
                body += para(runs, style: "Quote")
            case .list(let ordered, let items):
                for item in items {
                    body += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(ordered ? 2 : 1)\"/></w:numPr></w:pPr>\(runsXML(item))</w:p>"
                }
            case .table(let rows):
                body += tableXML(rows)
                body += "<w:p/>"
            case .image(let img, let caption):
                body += imageXML(img)
                if !caption.isEmpty { body += para(caption, style: "Caption") }
            }
        }

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>
        """

        var zip = OOXMLZip()
        zip.add("[Content_Types].xml", xml: contentTypes)
        zip.add("_rels/.rels", xml: rootRels)
        zip.add("word/document.xml", xml: document)
        zip.add("word/styles.xml", xml: stylesXML)
        zip.add("word/numbering.xml", xml: numberingXML)
        let docRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        <Relationship Id="rIdNum" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>\
        \(rels)</Relationships>
        """
        zip.add("word/_rels/document.xml.rels", xml: docRels)
        for entry in images { zip.add("word/media/\(entry.name)", entry.img.data) }
        return zip.finalize()
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Default Extension="png" ContentType="image/png"/>\
    <Default Extension="jpeg" ContentType="image/jpeg"/>\
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
    <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
    </Types>
    """

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
