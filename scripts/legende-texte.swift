// Dessine une légende de capture App Store en PNG transparent, pour les langues que la Nunito de
// l'app ne couvre pas (cyrillique, vietnamien, turc, japonais, chinois, coréen, hindi) : la
// police arrondie du système en noir, et CoreText choisit lui-même la police de repli de
// l'écriture — avec la composition du devanagari, que Pillow sans raqm ne sait pas faire.
//
// Usage : legende-texte <texte> <corps px> <largeur px> <interligne px> <sortie.png>
// Écrit sur la sortie standard : « <lignes> <hauteur px> ».
import AppKit

let a = CommandLine.arguments
guard a.count == 6, let corps = Double(a[2]), let largeur = Double(a[3]), let interligne = Double(a[4]) else {
    FileHandle.standardError.write("usage : legende-texte texte corps largeur interligne sortie.png\n".data(using: .utf8)!)
    exit(2)
}
var police = NSFont.systemFont(ofSize: corps, weight: .black)
if let d = police.fontDescriptor.withDesign(.rounded), let r = NSFont(descriptor: d, size: corps) { police = r }
let style = NSMutableParagraphStyle()
style.minimumLineHeight = interligne
style.maximumLineHeight = interligne
style.lineBreakMode = .byWordWrapping
style.lineBreakStrategy = .standard
let texte = NSAttributedString(string: a[1], attributes: [
    .font: police, .paragraphStyle: style,
    .foregroundColor: NSColor(srgbRed: 28 / 255, green: 25 / 255, blue: 23 / 255, alpha: 1),
])

// Les lignes, telles que CoreText les coupe dans la largeur donnée.
let cadre = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(texte),
                                     CFRange(location: 0, length: 0),
                                     CGPath(rect: CGRect(x: 0, y: 0, width: largeur, height: 100_000), transform: nil), nil)
let nombre = (CTFrameGetLines(cadre) as? [CTLine])?.count ?? 1
let hauteur = Int((Double(nombre) * interligne + corps * 0.35).rounded(.up))

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(largeur), pixelsHigh: hauteur,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
texte.draw(with: NSRect(x: 0, y: 0, width: largeur, height: Double(hauteur)),
           options: [.usesLineFragmentOrigin, .usesFontLeading])
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[5]))
print(nombre, hauteur)
