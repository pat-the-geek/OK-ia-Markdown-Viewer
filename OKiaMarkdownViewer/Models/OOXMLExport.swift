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

// MARK: - PPTX builder (mixed: editable text + tables + images)

/// One slide: a title plus ordered content blocks (text, lists, quotes, native
/// editable tables, and rasterised media images).
struct PptxSlide {
    var title: [OOXMLRun]
    var blocks: [OOXMLBlock]
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

    static func build(slides: [PptxSlide]) -> Data {
        var zip = OOXMLZip()
        var slideOverrides = ""
        var presRels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        var sldIdList = ""

        for (i, slide) in slides.enumerated() {
            let n = i + 1
            let rid = "rId\(n + 1)"
            var images: [(name: String, img: OOXMLImage)] = []
            let xml = slideXML(slide, slideIndex: n, images: &images)
            zip.add("ppt/slides/slide\(n).xml", xml: xml)

            var rels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>"
            for (k, entry) in images.enumerated() {
                rels += "<Relationship Id=\"rIdImg\(k + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(entry.name)\"/>"
                zip.add("ppt/media/\(entry.name)", entry.img.data)
            }
            zip.add("ppt/slides/_rels/slide\(n).xml.rels", xml: relsDoc(rels))

            slideOverrides += "<Override PartName=\"/ppt/slides/slide\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
            presRels += "<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(n).xml\"/>"
            sldIdList += "<p:sldId id=\"\(255 + n)\" r:id=\"\(rid)\"/>"
        }

        zip.add("[Content_Types].xml", xml: contentTypes(slideOverrides))
        zip.add("_rels/.rels", xml: rootRels)
        zip.add("ppt/presentation.xml", xml: presentationXML(sldIdList))
        zip.add("ppt/_rels/presentation.xml.rels", xml: relsDoc(presRels))
        zip.add("ppt/slideMasters/slideMaster1.xml", xml: slideMaster)
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", xml: relsDoc(
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme1.xml\"/>"))
        zip.add("ppt/slideLayouts/slideLayout1.xml", xml: slideLayout)
        zip.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", xml: relsDoc(
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/>"))
        zip.add("ppt/theme/theme1.xml", xml: theme1)
        return zip.finalize()
    }

    // MARK: per-slide layout

    private static func slideXML(_ slide: PptxSlide, slideIndex: Int, images: inout [(name: String, img: OOXMLImage)]) -> String {
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
        \(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:overrideClrMapping bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:clrMapOvr></p:sld>
        """
    }

    // MARK: DrawingML helpers

    private static func runAXML(_ r: OOXMLRun, size: Int, bold: Bool) -> String {
        var rPr = "<a:rPr lang=\"fr-FR\" sz=\"\(size)\""
        if r.bold || bold { rPr += " b=\"1\"" }
        if r.italic { rPr += " i=\"1\"" }
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

    private static func presentationXML(_ sldIdList: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">\
        <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>\
        <p:sldIdLst>\(sldIdList)</p:sldIdLst>\
        <p:sldSz cx="\(slideW)" cy="\(slideH)" type="screen16x9"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>
        """
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
