// Banc de l'import PDF : lance ImportPDF sur un PDF et écrit le Markdown à côté, sur le Mac
// (compilé pour Mac Catalyst, comme l'app). Voir banc.sh.
import Foundation
import PDFKit
import UIKit

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: banc <fichier.pdf> [sortie.md]"); exit(1) }
let url = URL(fileURLWithPath: args[1])
let sortie = args.count >= 3 ? URL(fileURLWithPath: args[2]) : url.deletingPathExtension().appendingPathExtension("md")
let donnees = try Data(contentsOf: url)
// BANC_PAGE=6 : les lignes de la page 6 (comptée depuis 1), avec leur place, au lieu de l'import.
if let n = Int(ProcessInfo.processInfo.environment["BANC_PAGE"] ?? ""),
   let pdf = PDFDocument(data: donnees), let page = pdf.page(at: n - 1) {
    print("largeur", page.bounds(for: .mediaBox).width)
    for l in ImportPDF.lignes(page) {
        print(String(format: "%6.1f %6.1f %6.1f %6.1f %3d  ", l.haut, l.bas, l.gauche, l.droite, l.taille) + l.texte.prefix(70))
    }
    exit(0)
}
// BANC_CASES=9 : les cases de chaque ligne de la page 9.
if let n = Int(ProcessInfo.processInfo.environment["BANC_CASES"] ?? ""),
   let pdf = PDFDocument(data: donnees), let page = pdf.page(at: n - 1) {
    let lignes = ImportPDF.lignes(page)
    for (l, c) in zip(lignes, ImportPDF.cases(lignes, page: page)) {
        print(l.texte.prefix(50), "→", c.map { "[\($0.texte)]" }.joined())
    }
    exit(0)
}
// BANC_FIGURES=8 : les cadres des figures de la page 8, et la page rendue avec ces cadres (page-8.png).
if let n = Int(ProcessInfo.processInfo.environment["BANC_FIGURES"] ?? ""),
   let pdf = PDFDocument(data: donnees), let page = pdf.page(at: n - 1) {
    let cadres = ImportPDF.figures(page, lignes: ImportPDF.lignes(page)).cadres
    for c in cadres { print(c) }
    let boite = page.bounds(for: .mediaBox)
    let rendu = UIGraphicsImageRenderer(size: boite.size).image { ctx in
        ImportPDF.image(page, largeur: boite.width)?.draw(in: CGRect(origin: .zero, size: boite.size))
        UIColor.red.setStroke()
        for c in cadres { ctx.cgContext.stroke(c, width: 2) }
    }
    try rendu.pngData()?.write(to: url.deletingLastPathComponent().appendingPathComponent("page-\(n).png"))
    exit(0)
}
let debut = Date()
let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        let doc = try await ImportPDF.convertir(donnees, nom: url.lastPathComponent)
        try doc.markdown.write(to: sortie, atomically: true, encoding: .utf8)
        print(doc.resume, "—", String(format: "%.1f s", Date().timeIntervalSince(debut)), "→", sortie.path)
    } catch { print("échec :", error) }
    semaphore.signal()
}
semaphore.wait()
