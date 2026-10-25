import Foundation
import PDFKit
import UIKit

/// Option Analytic (1.4) — un PDF devient un document md Viewer. Un PDF ne connaît que des lignes
/// posées sur des pages : on retrouve la structure par ce qu'elles montrent.
/// - Les **titres** : d'abord la table des matières du PDF (les signets), qui dit leur niveau ;
///   sinon la taille de police, nettement plus grande que celle du corps.
/// - Les **paragraphes** : les lignes se suivent tant que l'écart entre elles reste celui d'un
///   interligne ; un écart plus grand ouvre un paragraphe. Un mot coupé en fin de ligne est recollé.
/// - Les **en-têtes et pieds de page** : une ligne qui revient au même endroit sur la plupart des
///   pages, et les numéros de page, sont écartés.
/// - Les **puces** tapées (« • », « – ») font des listes. Le gras et l'italique d'une ligne entière
///   sont gardés.
/// Les images ne sont pas reprises : un PDF ne dit pas où finit une image et où commence le décor.
enum ImportPDF {

    static func convertir(_ donnees: Data, nom: String, suivi: SuiviImport? = nil) async throws -> DocumentImporte {
        guard let pdf = PDFDocument(data: donnees) else { throw LecteurZip.Erreur.pasUnZip }
        if pdf.isLocked { throw Erreur.verrouille }

        // 1. Les lignes de chaque page, avec leur place et leur police.
        var pages: [[Ligne]] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            pages.append(Self.lignes(page))
            if i % 5 == 0 || i == pdf.pageCount - 1 {
                await suivi?(AvancementImport(etape: tr("Pages"), fait: i + 1, total: pdf.pageCount, dernier: nil))
            }
        }
        guard pages.contains(where: { !$0.isEmpty }) else { throw Erreur.sansTexte }

        // 2. Les en-têtes et pieds de page répétés, et les numéros de page.
        let decor = Self.decor(pages)
        // 3. La taille du corps et les tailles de titre.
        var parTaille: [Int: Int] = [:]
        for l in pages.joined() { parTaille[l.taille, default: 0] += l.texte.count }
        let corps = parTaille.max(by: { $0.value < $1.value })?.key ?? 11
        let grandes = Set(pages.joined().filter { Double($0.taille) >= Double(corps) * 1.15 && $0.texte.count <= 150 }.map(\.taille))
            .sorted(by: >).prefix(3)
        let niveauParTaille = Dictionary(uniqueKeysWithValues: grandes.enumerated().map { ($1, $0 + 1) })
        let signets = Self.signets(pdf)

        // 4. Les blocs.
        var blocs: [String] = []
        var paragraphe: [String] = []
        var liste: [String] = []
        var titre: String?
        func fermer() {
            if !paragraphe.isEmpty { blocs.append(MarkdownImport.debutDeLigne(Self.recoller(paragraphe))); paragraphe = [] }
            if !liste.isEmpty { blocs.append(liste.joined(separator: "\n")); liste = [] }
        }
        for lignes in pages {
            var precedente: Ligne?
            for l in lignes where !decor.contains(Self.cle(l)) {
                let cle = KeywordMatcher.normalize(l.texte)
                if let n = signets[cle] ?? (signets.isEmpty ? niveauParTaille[l.taille] : nil) {
                    fermer()
                    if titre == nil { titre = l.texte }
                    // Un titre sur deux lignes : la seconde rejoint la première.
                    if let p = precedente, p.estTitre, p.taille == l.taille, l.haut - p.bas < Double(l.taille) * 0.8,
                       let derniere = blocs.popLast() {
                        blocs.append(derniere + " " + MarkdownImport.echapper(l.texte))
                    } else {
                        blocs.append(String(repeating: "#", count: min(n, 6)) + " " + MarkdownImport.echapper(l.texte))
                    }
                    precedente = l.titre()
                    continue
                }
                let ecart = precedente.map { l.haut - $0.bas } ?? .infinity
                let interligne = Double(l.taille) * 0.75
                if let (reste, numero) = Self.puce(l.texte) {
                    if !paragraphe.isEmpty { fermer() }
                    let marque = numero.map { "\($0)." } ?? "-"
                    liste.append(marque + " " + Self.enForme(reste, l))
                } else if !liste.isEmpty, ecart < interligne, l.gauche - (precedente?.gauche ?? 0) > 4 {
                    // La suite d'une puce, en retrait.
                    liste[liste.count - 1] += " " + Self.enForme(l.texte, l)
                } else {
                    if ecart > interligne || !liste.isEmpty { fermer() }
                    paragraphe.append(Self.enForme(l.texte, l))
                }
                precedente = l
            }
            // Une page qui finit sur une phrase achevée ferme son paragraphe ; sinon il continue.
            if let fin = paragraphe.last, fin.hasSuffix(".") || fin.hasSuffix(":") { fermer() }
        }
        fermer()

        let titreFinal = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? titre ?? (nom as NSString).deletingPathExtension
        let md = MarkdownImport.entete(titre: titreFinal, source: nom, genre: "document")
            + "\n\n" + blocs.joined(separator: "\n\n") + "\n"
        let resume = tr("%d pages, %d paragraphes", pdf.pageCount, blocs.count)
        return DocumentImporte(genre: .rapport, titre: titreFinal, markdown: md, resume: resume)
    }

    enum Erreur: LocalizedError {
        case verrouille, sansTexte
        var errorDescription: String? {
            switch self {
            case .verrouille: return tr("Ce PDF est protégé par un mot de passe.")
            case .sansTexte:  return tr("Ce PDF ne contient pas de texte : c’est sans doute un document numérisé.")
            }
        }
    }

    // MARK: Les lignes d'une page

    struct Ligne {
        var texte: String
        /// Le haut et le bas de la ligne, comptés depuis le haut de la page.
        var haut: Double
        var bas: Double
        var gauche: Double
        /// La taille de police la plus répandue de la ligne, arrondie au point.
        var taille: Int
        var gras: Bool
        var italique: Bool
        var page: Int
        var estTitre = false

        func titre() -> Ligne { var l = self; l.estTitre = true; return l }
    }

    private static func lignes(_ page: PDFPage) -> [Ligne] {
        let boite = page.bounds(for: .mediaBox)
        guard let tout = page.selection(for: boite) else { return [] }
        let index = page.document.map { $0.index(for: page) } ?? 0
        var r: [Ligne] = []
        for s in tout.selectionsByLine() {
            guard let attr = s.attributedString else { continue }
            let texte = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texte.isEmpty else { continue }
            let b = s.bounds(for: page)
            var tailles: [Int: Int] = [:]
            var grasCar = 0, italiqueCar = 0, total = 0
            attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length)) { valeur, plage, _ in
                guard let f = valeur as? UIFont else { return }
                let n = plage.length
                tailles[Int(f.pointSize.rounded()), default: 0] += n
                let traits = f.fontDescriptor.symbolicTraits
                let nomPolice = f.fontName.lowercased()
                if traits.contains(.traitBold) || nomPolice.contains("bold") || nomPolice.contains("black") { grasCar += n }
                if traits.contains(.traitItalic) || nomPolice.contains("italic") || nomPolice.contains("oblique") { italiqueCar += n }
                total += n
            }
            r.append(Ligne(texte: texte, haut: boite.maxY - b.maxY, bas: boite.maxY - b.minY, gauche: b.minX,
                           taille: tailles.max(by: { $0.value < $1.value })?.key ?? 11,
                           gras: total > 0 && grasCar * 10 >= total * 9,
                           italique: total > 0 && italiqueCar * 10 >= total * 9, page: index))
        }
        // L'ordre de lecture : de haut en bas, puis de gauche à droite.
        return r.sorted { abs($0.haut - $1.haut) < 2 ? $0.gauche < $1.gauche : $0.haut < $1.haut }
    }

    // MARK: Décor, signets, puces

    /// La clé d'une ligne pour reconnaître le décor : son texte sans chiffres (« Page 3 sur 12 »)
    /// et sa hauteur sur la page, à 10 points près.
    private static func cle(_ l: Ligne) -> String {
        "\(Int(l.haut / 10))|" + l.texte.filter { !$0.isNumber }.trimmingCharacters(in: .whitespaces)
    }

    /// Les lignes qui reviennent au même endroit sur au moins la moitié des pages (trois au moins),
    /// et les numéros de page seuls.
    private static func decor(_ pages: [[Ligne]]) -> Set<String> {
        var vues: [String: Set<Int>] = [:]
        var r: Set<String> = []
        for (i, lignes) in pages.enumerated() {
            for l in lignes {
                let k = cle(l)
                vues[k, default: []].insert(i)
                if l.texte.range(of: #"^(?:[Pp]age\s*)?\d{1,4}(?:\s*(?:/|sur|of|von)\s*\d{1,4})?$"#,
                                 options: .regularExpression) != nil { r.insert(k) }
            }
        }
        if pages.count >= 3 {
            for (k, p) in vues where p.count * 2 >= pages.count { r.insert(k) }
        }
        return r
    }

    /// Les titres de la table des matières, pliés, avec leur profondeur (1 = premier niveau).
    private static func signets(_ pdf: PDFDocument) -> [String: Int] {
        guard let racine = pdf.outlineRoot else { return [:] }
        var r: [String: Int] = [:]
        func parcourir(_ o: PDFOutline, profondeur: Int) {
            for i in 0..<o.numberOfChildren {
                guard let enfant = o.child(at: i) else { continue }
                if let l = enfant.label, !l.isEmpty { r[KeywordMatcher.normalize(l)] = min(profondeur, 6) }
                parcourir(enfant, profondeur: profondeur + 1)
            }
        }
        parcourir(racine, profondeur: 1)
        return r
    }

    /// Une puce ou un numéro en tête de ligne : le reste du texte, et le numéro s'il y en a un.
    private static func puce(_ texte: String) -> (String, Int?)? {
        if let r = texte.range(of: #"^[•◦▪▫‣⁃●○■□–\-·]\s+"#, options: .regularExpression) {
            return (String(texte[r.upperBound...]), nil)
        }
        if let r = texte.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression),
           let n = Int(texte[r].filter(\.isNumber)) {
            return (String(texte[r.upperBound...]), n)
        }
        return nil
    }

    /// Une ligne entière en gras ou en italique le reste en Markdown.
    private static func enForme(_ texte: String, _ l: Ligne) -> String {
        var m = MarkdownImport.echapper(texte)
        if l.italique { m = "*\(m)*" }
        if l.gras { m = "**\(m)**" }
        return m
    }

    /// Les lignes d'un paragraphe recollées : un mot coupé (« informa- / tion ») se ressoude.
    static func recoller(_ lignes: [String]) -> String {
        var r = ""
        for l in lignes {
            if r.hasSuffix("-"), let c = l.first, c.isLowercase {
                r.removeLast()
                r += l
            } else {
                r += (r.isEmpty ? "" : " ") + l
            }
        }
        // Deux lignes grasses voisines : `**a** **b**` devient `**a b**`.
        return r.replacingOccurrences(of: "** **", with: " ")
    }
}
