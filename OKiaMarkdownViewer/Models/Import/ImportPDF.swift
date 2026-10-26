import Foundation
import PDFKit
import UIKit
import Vision

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
/// - Les **pages scannées** (une image, sans couche de texte) sont lues par la reconnaissance de
///   texte de l'appareil (Vision), puis traitées comme les autres ; une page dont on ne tire presque
///   rien (photo, schéma, écriture illisible) est gardée en image (Patrick, 26/10/2026).
/// Les images d'une page à texte ne sont pas reprises : un PDF ne dit pas où finit une image et où
/// commence le décor.
enum ImportPDF {

    /// En dessous, une page passe pour scannée : un numéro de page ou un tampon ne fait pas un texte.
    static let seuilPageScannee = 20
    /// En dessous, la reconnaissance n'a presque rien tiré de la page : son image est gardée.
    static let seuilPageImage = 40

    static func convertir(_ donnees: Data, nom: String, suivi: SuiviImport? = nil) async throws -> DocumentImporte {
        guard let pdf = PDFDocument(data: donnees) else { throw LecteurZip.Erreur.pasUnZip }
        if pdf.isLocked { throw Erreur.verrouille }

        // 1. Les lignes de chaque page, avec leur place et leur police ; celles d'une page scannée,
        //    par la reconnaissance de texte.
        var pages: [[Ligne]] = []
        var reconnues: Set<Int> = []
        var imagesDePage: [Int: String] = [:]
        let reservoir = ReservoirImages()
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { pages.append([]); continue }
            var lignes = Self.lignes(page)
            if lignes.reduce(0, { $0 + $1.texte.count }) < seuilPageScannee {
                await suivi?(AvancementImport(etape: tr("Reconnaissance du texte"), fait: i + 1, total: pdf.pageCount,
                                              dernier: tr("Page %d", i + 1)))
                let lues = Self.reconnaitre(page, index: i)
                if !lues.isEmpty { lignes = lues; reconnues.insert(i) }
                // Presque rien de lisible : la page reste en image, plutôt que perdue.
                if lues.reduce(0, { $0 + $1.texte.count }) < seuilPageImage,
                   let jpeg = Self.image(page, largeur: ImagesImport.coteMax)?.jpegData(compressionQuality: ImagesImport.qualite),
                   let ref = reservoir.reference("page-\(i + 1).jpg", donnees: { jpeg }) {
                    imagesDePage[i] = "![\(tr("Page %d", i + 1))][\(ref)]"
                }
            } else if i % 5 == 0 || i == pdf.pageCount - 1 {
                await suivi?(AvancementImport(etape: tr("Pages"), fait: i + 1, total: pdf.pageCount, dernier: nil))
            }
            pages.append(lignes)
        }
        guard pages.contains(where: { !$0.isEmpty }) || !imagesDePage.isEmpty else { throw Erreur.sansTexte }
        // Les tailles lues sur une image ne sont pas des tailles de police : on les ramène à l'échelle
        // du texte des autres pages, corps contre corps, pour que les titres se comparent.
        Self.mettreALEchelle(&pages, reconnues: reconnues)

        // 2. Les en-têtes et pieds de page répétés, et les numéros de page.
        let decor = Self.decor(pages)
        // 3. La taille du corps et les tailles de titre.
        var parTaille: [Int: Int] = [:]
        for l in pages.joined() { parTaille[l.taille, default: 0] += l.texte.count }
        let corps = parTaille.max(by: { $0.value < $1.value })?.key ?? 11
        // Une ligne reconnue sur une image n'a qu'une hauteur approchée : il lui faut un écart plus net,
        // et d'être courte, pour passer pour un titre.
        let grandes = Set(pages.joined().filter { $0.peutEtreTitre(corps: corps) }.map(\.taille))
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
        for (i, lignes) in pages.enumerated() {
            if let img = imagesDePage[i] { fermer(); blocs.append(img) }
            var precedente: Ligne?
            for l in lignes where !decor.contains(Self.cle(l)) {
                let cle = KeywordMatcher.normalize(l.texte)
                // La suite d'un titre lu sur une image (« a démissionné, … » sous « Un employé de… ») :
                // même taille à un quart près, juste dessous — elle le continue, minuscule comprise.
                if l.reconnue, let p = precedente, p.estTitre, p.reconnue,
                   abs(p.taille - l.taille) * 4 <= max(p.taille, l.taille), l.haut - p.bas < Double(l.taille) * 0.8,
                   let derniere = blocs.popLast() {
                    blocs.append(derniere + " " + MarkdownImport.echapper(l.texte))
                    precedente = l.titre()
                    continue
                }
                let parTaille = l.reconnue ? l.niveauReconnu(corps: corps) : niveauParTaille[l.taille]
                if let n = signets[cle] ?? (signets.isEmpty && l.peutEtreTitre(corps: corps) ? parTaille : nil) {
                    fermer()
                    if titre == nil { titre = l.texte }
                    // Un titre sur deux lignes : la seconde rejoint la première.
                    // Lue sur une image, la hauteur varie d'une ligne à l'autre d'un même titre : le palier compte.
                    let memeTaille = precedente.map { p in
                        l.reconnue ? abs(p.taille - l.taille) * 4 <= max(p.taille, l.taille) : p.taille == l.taille
                    } ?? false
                    if let p = precedente, p.estTitre, memeTaille, l.haut - p.bas < Double(l.taille) * 0.8,
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
            // La reconnaissance peut se tromper (chiffres, noms propres) : la page le dit.
            if reconnues.contains(i) {
                fermer()
                blocs.append("*" + tr("Page %d : texte reconnu sur l’image, à vérifier.", i + 1) + "*")
            }
        }
        fermer()

        let titreFinal = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? titre ?? (nom as NSString).deletingPathExtension
        var md = MarkdownImport.entete(titre: titreFinal, source: nom, genre: "document")
            + "\n\n" + blocs.joined(separator: "\n\n") + "\n"
        if !reservoir.definitions.isEmpty { md += "\n" + reservoir.definitions.joined(separator: "\n") + "\n" }
        var resume = tr("%d pages, %d paragraphes", pdf.pageCount, blocs.count)
        if !reconnues.isEmpty || !imagesDePage.isEmpty {
            resume += ", " + tr("dont %d pages scannées", Set(reconnues).union(imagesDePage.keys).count)
        }
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
        /// Lue par la reconnaissance de texte : sa taille n'est qu'approchée.
        var reconnue = false

        func titre() -> Ligne { var l = self; l.estTitre = true; return l }

        /// Le niveau d'un titre lu sur une image, par paliers : sa hauteur n'est qu'approchée (une
        /// ligne sans jambage paraît plus petite), et des tailles exactes éparpillaient un même titre
        /// sur deux niveaux.
        func niveauReconnu(corps: Int) -> Int? {
            let r = Double(taille) / Double(max(corps, 1))
            return r >= 2.0 ? 1 : r >= 1.55 ? 2 : r >= 1.25 ? 3 : nil
        }

        func peutEtreTitre(corps: Int) -> Bool {
            // Un titre lu sur une image commence par une majuscule ou un chiffre, compte trois lettres
            // au moins et ne finit ni sur un point ni sur une virgule (une fin de phrase plus haute,
            // un logo de deux lettres passaient pour des titres).
            reconnue ? Double(taille) >= Double(corps) * 1.25 && texte.count <= 60
                && texte.filter(\.isLetter).count >= 3 && !texte.hasSuffix(".") && !texte.hasSuffix(",")
                && (texte.first.map { $0.isUppercase || $0.isNumber } ?? false)
                     : Double(taille) >= Double(corps) * 1.15 && texte.count <= 150
        }
    }

    // MARK: Les pages scannées

    /// La page dessinée en image, à la largeur voulue, sur fond blanc.
    static func image(_ page: PDFPage, largeur: CGFloat) -> UIImage? {
        let boite = page.bounds(for: .mediaBox)
        guard boite.width > 0, boite.height > 0 else { return nil }
        let taille = CGSize(width: largeur, height: (largeur * boite.height / boite.width).rounded())
        return page.thumbnail(of: taille, for: .mediaBox)
    }

    /// Les lignes d'une page scannée, lues par Vision sur l'appareil, en mode précis, avec la
    /// correction linguistique des cinq langues de l'app. Leurs places sont celles de la page.
    static func reconnaitre(_ page: PDFPage, index: Int) -> [Ligne] {
        let boite = page.bounds(for: .mediaBox)
        // 2400 points de large : assez pour un corps de 9 points sur une page A4.
        guard let cg = image(page, largeur: 2400)?.cgImage else { return [] }
        let requete = VNRecognizeTextRequest()
        requete.recognitionLevel = .accurate
        requete.usesLanguageCorrection = true
        requete.recognitionLanguages = ["fr-FR", "en-US", "de-DE", "es-ES", "it-IT"]
        requete.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([requete]) } catch { return [] }
        let r: [Ligne] = (requete.results ?? []).compactMap { obs in
            guard let texte = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces),
                  !texte.isEmpty else { return nil }
            // Le cadre de Vision est normalisé, l'origine en bas à gauche.
            let b = obs.boundingBox
            let haut = (1 - b.maxY) * boite.height, bas = (1 - b.minY) * boite.height
            // La hauteur d'une ligne reconnue couvre jambages et accents : la police en vaut ~80 %.
            let taille = max(1, Int(((bas - haut) * 0.8).rounded()))
            var l = Ligne(texte: texte, haut: haut, bas: bas, gauche: b.minX * boite.width, taille: taille,
                          gras: false, italique: false, page: index)
            l.reconnue = true
            return l
        }
        return r.sorted { abs($0.haut - $1.haut) < 4 ? $0.gauche < $1.gauche : $0.haut < $1.haut }
    }

    /// Les tailles reconnues ramenées à l'échelle des polices du document : le corps des pages
    /// scannées vaut celui des pages à texte. Un document tout scanné garde ses tailles.
    static func mettreALEchelle(_ pages: inout [[Ligne]], reconnues: Set<Int>) {
        func corps(_ lignes: [Ligne]) -> Int? {
            var n: [Int: Int] = [:]
            for l in lignes { n[l.taille, default: 0] += l.texte.count }
            return n.max(by: { $0.value < $1.value })?.key
        }
        let texte = pages.enumerated().filter { !reconnues.contains($0.offset) }.flatMap(\.element)
        let lues = pages.enumerated().filter { reconnues.contains($0.offset) }.flatMap(\.element)
        guard !reconnues.isEmpty, let cT = corps(texte), let cL = corps(lues), cL > 0 else { return }
        let k = Double(cT) / Double(cL)
        for i in reconnues where i < pages.count {
            for j in pages[i].indices { pages[i][j].taille = max(1, Int((Double(pages[i][j].taille) * k).rounded())) }
        }
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
