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
/// - Les **colonnes** : une page en deux ou trois colonnes se lit colonne après colonne ; une ligne
///   qui les traverse (titre, tableau, légende) coupe la page en bandes (Patrick, 28/10/2026).
/// - Les **figures** d'une page à texte (photos, graphiques, schémas) : ce que la page dessine hors de
///   ses lignes de texte, assez grand pour ne pas être un filet ou un logo, est repris en image à sa
///   place ; le texte posé dessus (les libellés d'un graphique) part avec elle (28/10/2026).
/// - Les **tableaux** : des rangées de trois cases ou plus, l'une sous l'autre, deviennent un tableau
///   Markdown ; une case sur plusieurs lignes reste une case (28/10/2026).
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
            let largeur = Double(page.bounds(for: .mediaBox).width)
            if lignes.reduce(0, { $0 + $1.texte.count }) >= seuilPageScannee {
                lignes = Self.avecFigures(lignes, page: page, index: i, reservoir: reservoir)
                lignes = Self.avecTableaux(lignes, page: page, index: i)
            }
            if lignes.reduce(0, { $0 + $1.texte.count }) < seuilPageScannee, !lignes.contains(where: { $0.bloc != nil }) {
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
            pages.append(Self.ordreDeLecture(lignes, largeur: largeur))
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
        // Une figure posée au milieu d'une phrase (la colonne continue plus loin) attend, avec sa
        // légende, que le paragraphe se termine : la phrase ne se coupe pas sur une photo.
        var apres: [String] = []
        var legende: [String] = []
        var corpsAvantFigure: Int?
        func fermer() {
            if !paragraphe.isEmpty { blocs.append(MarkdownImport.debutDeLigne(Self.recoller(paragraphe))); paragraphe = [] }
            if !liste.isEmpty { blocs.append(liste.joined(separator: "\n")); liste = [] }
            if !legende.isEmpty { apres.append(MarkdownImport.debutDeLigne(Self.recoller(legende))); legende = [] }
            corpsAvantFigure = nil
            blocs += apres
            apres = []
        }
        func finDePhrase(_ t: String) -> Bool { [".", ":", "!", "?"].contains { t.hasSuffix($0) } }
        for (i, lignes) in pages.enumerated() {
            if let img = imagesDePage[i] { fermer(); blocs.append(img) }
            var precedente: Ligne?
            for l in lignes where !decor.contains(Self.cle(l)) {
                if let image = l.bloc {
                    if let fin = paragraphe.last, !finDePhrase(fin), let p = precedente {
                        if !legende.isEmpty { apres.append(MarkdownImport.debutDeLigne(Self.recoller(legende))); legende = [] }
                        apres.append(image)
                        corpsAvantFigure = p.taille
                        continue
                    }
                    fermer()
                    blocs.append(image)
                    precedente = nil
                    continue
                }
                // La légende d'une figure qui attend : plus petite que le texte qu'elle interrompt.
                if let corps = corpsAvantFigure {
                    if l.taille < corps - 1 { legende.append(Self.enForme(l.texte, l)); continue }
                    if !legende.isEmpty { apres.append(MarkdownImport.debutDeLigne(Self.recoller(legende))); legende = [] }
                    corpsAvantFigure = nil
                }
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
                var ecart = precedente.map { l.haut - $0.bas } ?? .infinity
                let interligne = Double(l.taille) * 0.75
                // Remonté en haut de la colonne suivante : la phrase continue, sauf si elle était finie.
                if ecart < -Double(l.taille) * 2, let fin = paragraphe.last, finDePhrase(fin) { ecart = .infinity }
                // Un changement net de taille (une légende, un encadré) ouvre un paragraphe.
                if let p = precedente, abs(p.taille - l.taille) >= 2 { ecart = .infinity }
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
        var droite: Double
        /// La taille de police la plus répandue de la ligne, arrondie au point.
        var taille: Int
        var gras: Bool
        var italique: Bool
        var page: Int
        var estTitre = false
        /// Lue par la reconnaissance de texte : sa taille n'est qu'approchée.
        var reconnue = false
        /// Une figure ou un tableau de la page, en Markdown : la « ligne » n'est que sa place.
        var bloc: String?

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
            var l = Ligne(texte: texte, haut: haut, bas: bas, gauche: b.minX * boite.width,
                          droite: b.maxX * boite.width, taille: taille,
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

    static func lignes(_ page: PDFPage) -> [Ligne] {
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
                           droite: b.maxX,
                           taille: tailles.max(by: { $0.value < $1.value })?.key ?? 11,
                           gras: total > 0 && grasCar * 10 >= total * 9,
                           italique: total > 0 && italiqueCar * 10 >= total * 9, page: index))
        }
        // L'ordre de lecture : de haut en bas, puis de gauche à droite.
        return r.sorted { abs($0.haut - $1.haut) < 2 ? $0.gauche < $1.gauche : $0.haut < $1.haut }
    }

    // MARK: Colonnes

    /// L'ordre de lecture d'une page : de haut en bas, sauf sur une page en colonnes, lue colonne
    /// après colonne. Les colonnes se voient aux couloirs verticaux que les lignes de texte ne
    /// traversent pas. Une ligne qui traverse un couloir (titre, ligne de tableau, figure large)
    /// ferme la bande en cours : on lit ses colonnes, puis cette ligne, puis la bande suivante.
    static func ordreDeLecture(_ lignes: [Ligne], largeur: Double) -> [Ligne] {
        let triees = lignes.sorted { abs($0.haut - $1.haut) < 2 ? $0.gauche < $1.gauche : $0.haut < $1.haut }
        let couloirs = Self.couloirs(triees, largeur: largeur)
        guard !couloirs.isEmpty else { return triees }
        // La colonne d'une ligne ; nil si elle les traverse. Une figure qui déborde d'une colonne (un
        // graphique un peu plus large que son texte) reste à celle qui en porte les trois quarts.
        let bornes = [0.0] + couloirs + [largeur]
        func colonne(_ l: Ligne) -> Int? {
            let parts = (0..<bornes.count - 1).map { k in
                max(0, min(l.droite, bornes[k + 1]) - max(l.gauche, bornes[k]))
            }
            let total = max(l.droite - l.gauche, 1)
            guard let k = parts.indices.max(by: { parts[$0] < parts[$1] }) else { return nil }
            if l.bloc != nil { return parts[k] >= total * 0.7 ? k : nil }
            return couloirs.contains { l.gauche < $0 - 3 && l.droite > $0 + 3 } ? nil : k
        }
        // Une ligne de tableau (trois cases ou plus à la même hauteur) se lit d'une traite.
        var parRangee: [Int: Int] = [:]
        for l in triees { parRangee[Int(l.haut.rounded()), default: 0] += 1 }
        func rangee(_ l: Ligne) -> Bool {
            let h = Int(l.haut.rounded())
            return (parRangee[h] ?? 0) + (parRangee[h - 1] ?? 0) + (parRangee[h + 1] ?? 0) >= 3
        }
        var r: [Ligne] = []
        var bande: [[Ligne]] = Array(repeating: [], count: couloirs.count + 1)
        func vider() {
            for c in bande.indices { r += bande[c]; bande[c] = [] }
        }
        for l in triees {
            if let k = colonne(l), l.bloc != nil || !rangee(l) {
                bande[k].append(l)
            } else {
                vider()
                r.append(l)
            }
        }
        vider()
        return r
    }

    /// Les couloirs entre colonnes (leur abscisse), dans le tiers central de la page au sens large :
    /// des bandes d'au moins 6 points que presque aucune ligne de texte ne traverse, avec assez de
    /// lignes de part et d'autre. Seules comptent les lignes de prose, faites de lettres : les libellés
    /// courts d'un graphique ou les chiffres d'un tableau débordent dans le couloir.
    static func couloirs(_ lignes: [Ligne], largeur: Double) -> [Double] {
        let prose = lignes.filter { l in
            l.bloc == nil && l.texte.count >= 20 && l.droite - l.gauche < largeur * 0.6
                && l.texte.filter(\.isLetter).count * 10 >= l.texte.count * 6
        }
        guard prose.count >= 10, largeur > 100 else { return [] }
        let pas = 2.0, n = Int(largeur / pas) + 1
        var couverture = [Int](repeating: 0, count: n)
        for l in prose {
            let a = max(0, Int(l.gauche / pas)), b = min(n - 1, Int(l.droite / pas))
            if a <= b { for k in a...b { couverture[k] += 1 } }
        }
        let tolere = max(1, prose.count / 12)
        var r: [Double] = []
        var k = Int(largeur * 0.2 / pas)
        let fin = Int(largeur * 0.8 / pas)
        while k <= fin {
            guard couverture[k] <= tolere else { k += 1; continue }
            var j = k
            while j + 1 < n, couverture[j + 1] <= tolere { j += 1 }
            let a = Double(k) * pas, b = Double(j + 1) * pas, x = (a + b) / 2
            if b - a >= 6,
               prose.filter({ $0.droite <= x }).count >= 4, prose.filter({ $0.gauche >= x }).count >= 4 {
                r.append(x)
            }
            k = j + 1
        }
        return r
    }

    // MARK: Tableaux

    /// Une case d'une rangée : son texte et sa place.
    struct Case { var texte: String; var gauche: Double; var droite: Double }

    /// Les tableaux d'une page, chacun en « ligne » à sa place, ses lignes retirées du texte.
    /// Une ligne de PDFKit réunit souvent plusieurs cases (« 3,0% 2,3% 2,0% ») : on la redécoupe aux
    /// grands blancs, d'après la place de chaque caractère. Une rangée de trois cases ou plus est
    /// une rangée de tableau ; plusieurs, l'une sous l'autre, font un tableau. Les lignes serrées
    /// entre elles ou juste dessous (la suite d'une case) en sont.
    static func avecTableaux(_ lignes: [Ligne], page: PDFPage, index: Int) -> [Ligne] {
        // Des rangées de trois lignes au moins, ou rien à chercher : le découpage par caractère coûte.
        var parHauteur: [Int: Int] = [:]
        for l in lignes where l.bloc == nil { parHauteur[Int(l.haut.rounded())] = (parHauteur[Int(l.haut.rounded())] ?? 0) + 1 }
        guard parHauteur.keys.contains(where: { (parHauteur[$0] ?? 0) + (parHauteur[$0 + 1] ?? 0) + (parHauteur[$0 - 1] ?? 0) >= 3 }) else { return lignes }
        let cases = Self.cases(lignes, page: page)

        // Les rangées : les lignes à la même hauteur, de haut en bas.
        let texte = lignes.indices.filter { lignes[$0].bloc == nil }.sorted { lignes[$0].haut < lignes[$1].haut }
        var rangees: [[Int]] = []
        for i in texte {
            if let d = rangees.last?.first, abs(lignes[d].haut - lignes[i].haut) < 2 { rangees[rangees.count - 1].append(i) }
            else { rangees.append([i]) }
        }
        func nombreDeCases(_ r: [Int]) -> Int { r.reduce(0) { $0 + max(1, cases[$1].count) } }

        var r = lignes
        var retirees = Set<Int>()
        var k = 0
        while k < rangees.count {
            guard nombreDeCases(rangees[k]) >= 3 else { k += 1; continue }
            // Le tableau s'étend tant que les rangées se suivent de près : une rangée de cases, ou
            // la suite serrée d'une case, sous la précédente.
            var fin = k
            var j = k + 1
            var corpsTableau = rangees[k].map { lignes[$0].taille }.max() ?? 0
            while j < rangees.count {
                let avant = rangees[j - 1], ici = rangees[j]
                let h = avant.map { lignes[$0].bas - lignes[$0].haut }.max() ?? 10
                let ecart = (ici.map { lignes[$0].haut }.min() ?? 0) - (avant.map { lignes[$0].bas }.max() ?? 0)
                if nombreDeCases(ici) >= 3, ecart < h * 2.5 {
                    fin = j; j += 1
                    corpsTableau = max(corpsTableau, ici.map { lignes[$0].taille }.max() ?? 0)
                    continue
                }
                if ecart < h * 0.6, ici.allSatisfy({ lignes[$0].taille <= corpsTableau }) { j += 1; continue }
                break
            }
            // Les suites de case après la dernière rangée en sont aussi.
            let derniere = j - 1
            let tableau = Array(rangees[k...max(fin, derniere)])
            k = j
            let pleines = tableau.filter { nombreDeCases($0) >= 3 }
            guard pleines.count >= 2 else { continue }
            let toutes = pleines.flatMap { $0.flatMap { cases[$0] } }
            // Trois colonnes de prose ne font pas un tableau.
            let longueur = Double(toutes.reduce(0) { $0 + $1.texte.count }) / Double(max(toutes.count, 1))
            guard pleines.map(nombreDeCases).max() ?? 0 >= 4 || longueur <= 30 else { continue }
            guard let markdown = Self.tableau(tableau.map { rangee in
                (haut: rangee.map { lignes[$0].haut }.min() ?? 0,
                 hauteur: rangee.map { lignes[$0].bas - lignes[$0].haut }.max() ?? 10,
                 cases: rangee.flatMap { i in cases[i].isEmpty ? [Case(texte: lignes[i].texte, gauche: lignes[i].gauche, droite: lignes[i].droite)] : cases[i] })
            }) else { continue }
            let membres = tableau.flatMap { $0 }
            retirees.formUnion(membres)
            var l = Ligne(texte: "", haut: membres.map { lignes[$0].haut }.min() ?? 0, bas: membres.map { lignes[$0].bas }.max() ?? 0,
                          gauche: membres.map { lignes[$0].gauche }.min() ?? 0, droite: membres.map { lignes[$0].droite }.max() ?? 0,
                          taille: 0, gras: false, italique: false, page: index)
            l.bloc = markdown
            r.append(l)
        }
        return r.enumerated().filter { !retirees.contains($0.offset) }.map(\.element)
    }

    /// Les cases de chaque ligne : la ligne est sondée point par point (`characterIndex(at:)`) ; un
    /// blanc sans caractère plus large que les trois quarts du corps sépare deux cases, et le texte de
    /// chaque case est relu sur son rectangle. (Les indices de `characterBounds` ne suivent pas ceux
    /// du texte de la page — ligatures, accents décomposés — : on ne s'y fie pas.)
    static func cases(_ lignes: [Ligne], page: PDFPage) -> [[Case]] {
        let boite = page.bounds(for: .mediaBox)
        return lignes.map { l in
            guard l.bloc == nil, l.droite > l.gauche else { return [] }
            let yMilieu = boite.maxY - CGFloat((l.haut + l.bas) / 2)
            let h = CGFloat(l.bas - l.haut)
            let seuil = Double(max(l.taille, 6)) * 0.75
            // Le caractère sous chaque point. Une espace qui aligne un tableau est un seul caractère
            // très large : un même caractère sur plus de 1,2 corps est un blanc.
            var indices: [Int] = []
            var x = l.gauche
            while x <= l.droite {
                indices.append(page.characterIndex(at: CGPoint(x: CGFloat(x), y: yMilieu)))
                x += 1
            }
            var encre = indices.map { $0 >= 0 }
            var a = 0
            while a < indices.count {
                var b = a
                while b + 1 < indices.count, indices[b + 1] == indices[a] { b += 1 }
                if indices[a] >= 0, Double(b - a + 1) > Double(max(l.taille, 6)) * 1.2 { for k in a...b { encre[k] = false } }
                a = b + 1
            }
            var plages: [(Double, Double)] = []
            var debut: Double?, dernier = l.gauche
            for (k, e) in encre.enumerated() where e {
                let x = l.gauche + Double(k)
                if let d = debut, x - dernier > seuil { plages.append((d, dernier)); debut = nil }
                if debut == nil { debut = x }
                dernier = x
            }
            if let d = debut { plages.append((d, dernier)) }
            guard plages.count >= 2 else { return [] }
            let hauteur = h
            return plages.compactMap { a, b in
                let zone = CGRect(x: CGFloat(a) - 0.5, y: yMilieu - hauteur * 0.3, width: CGFloat(b - a) + 1.5, height: hauteur * 0.6)
                guard let t = page.selection(for: zone)?.string?
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
                return Case(texte: t, gauche: a, droite: b + 1)
            }
        }
    }

    /// Le tableau Markdown d'une suite de rangées. Les colonnes sont les bords gauches qui reviennent ;
    /// une rangée serrée sous la précédente (la seconde ligne d'une case) la complète. La première
    /// rangée fait l'en-tête. nil s'il ne reste pas deux colonnes et deux rangées.
    static func tableau(_ rangees: [(haut: Double, hauteur: Double, cases: [Case])]) -> String? {
        // Les colonnes : les bords gauches, regroupés à 8 points près, vus dans deux rangées au moins et
        // dans un cinquième des rangées pleines (un grand blanc d'un texte justifié n'ouvre pas de
        // colonne ; une case sur dix lignes ne compte qu'une fois dans sa première colonne).
        var bords: [(x: Double, n: Int)] = []
        for x in rangees.flatMap({ $0.cases.map(\.gauche) }).sorted() {
            if let d = bords.last, x - d.x <= 8 { bords[bords.count - 1].n += 1 } else { bords.append((x, 1)) }
        }
        let pleines = rangees.filter { $0.cases.count >= 3 }.count
        let colonnes = bords.filter { $0.n >= max(2, pleines / 5) }.map(\.x)
        guard colonnes.count >= 2 else { return nil }
        func colonne(_ c: Case) -> Int { max(0, (colonnes.lastIndex { $0 <= c.gauche + 8 }) ?? 0) }
        // Les rangées logiques : une rangée qui suit la précédente à moins d'un interligne la complète.
        var logiques: [[String]] = []
        var precedente: (haut: Double, hauteur: Double)?
        for rg in rangees {
            var cellules = [String](repeating: "", count: colonnes.count)
            for c in rg.cases.sorted(by: { $0.gauche < $1.gauche }) {
                let k = colonne(c)
                cellules[k] += (cellules[k].isEmpty ? "" : " ") + c.texte
            }
            if let p = precedente, rg.haut - p.haut < p.hauteur * 1.1, !logiques.isEmpty {
                for k in cellules.indices where !cellules[k].isEmpty {
                    logiques[logiques.count - 1][k] += (logiques[logiques.count - 1][k].isEmpty ? "" : " ") + cellules[k]
                }
            } else {
                logiques.append(cellules)
            }
            precedente = (rg.haut, rg.hauteur)
        }
        guard logiques.count >= 2 else { return nil }
        // Une colonne sans en-tête, après une colonne qui en a un, en est la suite (des cases qui
        // commencent un peu plus loin) ; une colonne vide partout disparaît.
        for k in stride(from: colonnes.count - 1, through: 1, by: -1)
            where logiques[0][k].isEmpty && !logiques[0][k - 1].isEmpty {
            for r in logiques.indices where !logiques[r][k].isEmpty {
                logiques[r][k - 1] += (logiques[r][k - 1].isEmpty ? "" : " ") + logiques[r][k]
            }
            for r in logiques.indices { logiques[r].remove(at: k) }
        }
        for k in stride(from: logiques[0].count - 1, through: 0, by: -1) where logiques.allSatisfy({ $0[k].isEmpty }) {
            for r in logiques.indices { logiques[r].remove(at: k) }
        }
        guard (logiques.first?.count ?? 0) >= 2 else { return nil }
        func rangee(_ c: [String]) -> String {
            "| " + c.map { MarkdownImport.echapper($0) }.joined(separator: " | ") + " |"
        }
        return ([rangee(logiques[0]), "|" + String(repeating: " --- |", count: logiques[0].count)] + logiques.dropFirst().map(rangee))
            .joined(separator: "\n")
    }

    // MARK: Figures

    /// Les figures d'une page à texte, chacune en « ligne » à sa place ; le texte posé sur une figure
    /// (libellés, axes, légende intégrée) est retiré, il est dans l'image.
    static func avecFigures(_ lignes: [Ligne], page: PDFPage, index: Int, reservoir: ReservoirImages) -> [Ligne] {
        let (visibles, cadres) = figures(page, lignes: lignes)
        let lignes = visibles
        guard !cadres.isEmpty else { return lignes }
        let boite = page.bounds(for: .mediaBox)
        // Le rendu de la page à l'échelle des figures : 1600 px pour la plus large, trois fois au plus.
        let plusLarge = cadres.map(\.width).max() ?? boite.width
        let k = min(3, ImagesImport.coteMax / max(plusLarge, 1))
        guard let rendu = Self.image(page, largeur: (boite.width * k).rounded())?.cgImage else { return lignes }
        let kx = CGFloat(rendu.width) / boite.width, ky = CGFloat(rendu.height) / boite.height
        var r = lignes.filter { l in
            !cadres.contains { $0.contains(CGPoint(x: (l.gauche + l.droite) / 2, y: (l.haut + l.bas) / 2)) }
        }
        for (n, c) in cadres.enumerated() {
            let pixels = CGRect(x: c.minX * kx, y: c.minY * ky, width: c.width * kx, height: c.height * ky).integral
            guard let morceau = rendu.cropping(to: pixels),
                  let jpeg = UIImage(cgImage: morceau).jpegData(compressionQuality: ImagesImport.qualite),
                  let ref = reservoir.reference("page-\(index + 1)-figure-\(n + 1).jpg", donnees: { jpeg }) else { continue }
            var l = Ligne(texte: "", haut: c.minY, bas: c.maxY, gauche: c.minX, droite: c.maxX,
                          taille: 0, gras: false, italique: false, page: index)
            l.bloc = "![\(tr("Page %d", index + 1))][\(ref)]"
            r.append(l)
        }
        return r
    }

    /// Les cadres des figures d'une page, comptés depuis le haut de la page : la page est rendue à un
    /// point par pixel, ses lignes de texte effacées ; ce qui reste d'encre, regroupé à 8 points près,
    /// fait une figure s'il mesure au moins 60 × 40 points. Un bloc de prose (un encadré sur fond de
    /// couleur, le titre ou la source d'un graphique) n'en fait jamais partie : son texte reste du texte.
    /// Le rendu dit aussi quelles lignes se voient : un texte qui ne laisse aucune trace sur la page
    /// (les libellés d'un graphique masqué, blanc sur blanc) est écarté (28/10/2026).
    static func figures(_ page: PDFPage, lignes: [Ligne]) -> (visibles: [Ligne], cadres: [CGRect]) {
        let boite = page.bounds(for: .mediaBox)
        let w = Int(boite.width.rounded()), h = Int(boite.height.rounded())
        guard w > 50, h > 50, let cg = Self.image(page, largeur: CGFloat(w))?.cgImage else { return (lignes, []) }
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let dessine = px.withUnsafeMutableBytes { tampon -> Bool in
            guard let ctx = CGContext(data: tampon.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard dessine else { return (lignes, []) }
        // Une ligne se voit si son cadre n'est pas d'une seule teinte, là où aucune ligne plus grande
        // ne la recouvre : deux textes ne se superposent pas, le plus petit est caché.
        var plusGrande = [Int](repeating: 0, count: w * h)
        func cadre(_ l: Ligne) -> (Int, Int, Int, Int)? {
            let x0 = max(0, Int(l.gauche)), x1 = min(w - 1, Int(l.droite.rounded(.up)))
            let y0 = max(0, Int(l.haut)), y1 = min(h - 1, Int(l.bas.rounded(.up)))
            return x0 < x1 && y0 < y1 ? (x0, x1, y0, y1) : nil
        }
        for l in lignes { if let (x0, x1, y0, y1) = cadre(l) {
            for y in y0...y1 { for x in x0...x1 { plusGrande[y * w + x] = max(plusGrande[y * w + x], l.taille) } }
        } }
        let visibles = lignes.filter { l in
            guard let (x0, x1, y0, y1) = cadre(l) else { return true }
            var bas = 255 * 3, haut = 0
            for y in y0...y1 { for x in x0...x1 where plusGrande[y * w + x] <= l.taille {
                let i = (y * w + x) * 4
                let v = Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2])
                bas = min(bas, v); haut = max(haut, v)
            } }
            return haut - bas > 60
        }
        // Le fond : la couleur la plus répandue de la page.
        var freq: [Int: Int] = [:]
        for i in stride(from: 0, to: w * h * 4, by: 4 * 7) {
            freq[Int(px[i] >> 4) << 8 | Int(px[i + 1] >> 4) << 4 | Int(px[i + 2] >> 4), default: 0] += 1
        }
        let fond = freq.max { $0.value < $1.value }?.key ?? 0xFFF
        let fr = (fond >> 8 & 0xF) * 16 + 8, fv = (fond >> 4 & 0xF) * 16 + 8, fb = (fond & 0xF) * 16 + 8
        // Le texte effacé : ses cadres ne comptent pas comme encre (la ligne 0 du tampon est le haut de la page).
        var texte = [Bool](repeating: false, count: w * h)
        for l in lignes {
            let x0 = max(0, Int(l.gauche) - 2), x1 = min(w - 1, Int(l.droite) + 2)
            let y0 = max(0, Int(l.haut) - 1), y1 = min(h - 1, Int(l.bas) + 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { texte[y * w + x] = true } }
        }
        // L'encre, par cases de 4 points.
        let c = 4, cw = (w + c - 1) / c, ch = (h + c - 1) / c
        var encre = [Bool](repeating: false, count: cw * ch)
        var compte = [Int](repeating: 0, count: cw * ch)
        for y in 0..<h {
            for x in 0..<w where !texte[y * w + x] {
                let i = (y * w + x) * 4
                if abs(Int(px[i]) - fr) + abs(Int(px[i + 1]) - fv) + abs(Int(px[i + 2]) - fb) > 60 {
                    compte[(y / c) * cw + x / c] += 1
                }
            }
        }
        for i in compte.indices where compte[i] >= 3 { encre[i] = true }
        let encreBrute = encre
        // Les filets et les bandes de décor (un liseré au bord de la page, le trait sous un titre) :
        // cinq cases d'épaisseur au plus (20 points) sur une grande longueur. Ils ne font pas une figure, et
        // ils en soudaient d'autres entre elles.
        var enLigne = [Int](repeating: 0, count: cw * ch), enColonne = [Int](repeating: 0, count: cw * ch)
        for y in 0..<ch {
            var x = 0
            while x < cw {
                guard encre[y * cw + x] else { x += 1; continue }
                var f = x
                while f + 1 < cw, encre[y * cw + f + 1] { f += 1 }
                for k in x...f { enLigne[y * cw + k] = f - x + 1 }
                x = f + 1
            }
        }
        for x in 0..<cw {
            var y = 0
            while y < ch {
                guard encre[y * cw + x] else { y += 1; continue }
                var f = y
                while f + 1 < ch, encre[(f + 1) * cw + x] { f += 1 }
                for k in y...f { enColonne[k * cw + x] = f - y + 1 }
                y = f + 1
            }
        }
        for i in encre.indices where encre[i] {
            if (enLigne[i] <= 5 && enColonne[i] >= 25) || (enColonne[i] <= 5 && enLigne[i] >= 25) { encre[i] = false }
        }
        // Regrouper : deux cases d'encre à 8 points l'une de l'autre sont d'une même figure.
        var etendue = encre
        for y in 0..<ch { for x in 0..<cw where encre[y * cw + x] {
            for dy in -2...2 { for dx in -2...2 {
                let yy = y + dy, xx = x + dx
                if yy >= 0, yy < ch, xx >= 0, xx < cw { etendue[yy * cw + xx] = true }
            } }
        } }
        var vu = [Bool](repeating: false, count: cw * ch)
        var trouves: [CGRect] = []
        for depart in etendue.indices where etendue[depart] && !vu[depart] {
            var pile = [depart]; vu[depart] = true
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            while let i = pile.popLast() {
                let x = i % cw, y = i / cw
                if encre[i] { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, xx < cw, yy >= 0, yy < ch else { continue }
                    let j = yy * cw + xx
                    if etendue[j], !vu[j] { vu[j] = true; pile.append(j) }
                }
            }
            guard maxX >= 0 else { continue }
            trouves.append(CGRect(x: minX * c, y: minY * c, width: (maxX - minX + 1) * c, height: (maxY - minY + 1) * c))
        }
        // Un cadre dans un autre (le contour d'un graphique et son tracé) ou qui le chevauche : une figure.
        var fusionnes = true
        while fusionnes {
            fusionnes = false
            outer: for i in trouves.indices { for j in trouves.indices where j > i && trouves[i].intersects(trouves[j]) {
                trouves[i] = trouves[i].union(trouves[j]); trouves.remove(at: j); fusionnes = true; break outer
            } }
        }
        // L'encre restée dans un rectangle : son cadre au plus juste.
        func serre(_ z: CGRect) -> CGRect? {
            let x0 = max(0, Int(z.minX) / c), x1 = min(cw - 1, Int(z.maxX - 1) / c)
            let y0 = max(0, Int(z.minY) / c), y1 = min(ch - 1, Int(z.maxY - 1) / c)
            guard x0 <= x1, y0 <= y1 else { return nil }
            var a = Int.max, b = Int.max, e = -1, f = -1
            for y in y0...y1 { for x in x0...x1 where encre[y * cw + x] { a = min(a, x); e = max(e, x); b = min(b, y); f = max(f, y) } }
            return e < 0 ? nil : CGRect(x: a * c, y: b * c, width: (e - a + 1) * c, height: (f - b + 1) * c)
        }
        func dedans(_ z: CGRect) -> [Ligne] {
            visibles.filter { z.contains(CGPoint(x: ($0.gauche + $0.droite) / 2, y: ($0.haut + $0.bas) / 2)) }
        }
        func estProse(_ l: Ligne) -> Bool { l.texte.count >= 25 }
        // Le corps de la page : la taille la plus répandue de son texte.
        var parTaille: [Int: Int] = [:]
        for l in visibles { parTaille[l.taille, default: 0] += l.texte.count }
        let corps = parTaille.max { $0.value < $1.value }?.key ?? 11
        var r: [CGRect] = []
        for depart in trouves {
            let poses = dedans(depart)
            // Un tableau (des rangées de trois cases ou plus, dont des mots) n'est pas une figure :
            // ses filets ne font pas une image, son texte reste du texte.
            var rangees: [Int: [Ligne]] = [:]
            for l in poses { rangees[Int(l.haut.rounded()), default: []].append(l) }
            let rangeesDeTableau = rangees.values.filter { r in
                r.count >= 3 && r.filter { $0.texte.filter(\.isLetter).count >= 4 }.count >= 2
            }.count
            guard rangeesDeTableau < 2 else { continue }
            // Les blocs de prose posés dans le cadre (un encadré collé à une photo, le titre ou la
            // source d'un graphique) : des lignes longues, voisines, regroupées.
            // Une ligne longue seule (un titre de graphique, une entrée de légende) reste dans l'image.
            var blocsProse: [(cadre: CGRect, lignes: Int)] = []
            for l in poses where estProse(l) {
                var b = (cadre: CGRect(x: l.gauche, y: l.haut, width: l.droite - l.gauche, height: l.bas - l.haut), lignes: 1)
                let marge = { (z: CGRect) in z.insetBy(dx: -6, dy: -(l.bas - l.haut) * 0.8) }
                while let k = blocsProse.firstIndex(where: { $0.cadre.intersects(marge(b.cadre)) }) {
                    let o = blocsProse.remove(at: k)
                    b = (b.cadre.union(o.cadre), b.lignes + o.lignes)
                }
                blocsProse.append(b)
            }
            // Le texte de la page qui mord sur le bord du cadre (une colonne qui longe la photo) en
            // sort aussi : une image ne coupe pas une ligne.
            let mordent = visibles.filter { l in
                let z = CGRect(x: l.gauche, y: l.haut, width: l.droite - l.gauche, height: l.bas - l.haut)
                return z.intersects(depart) && !depart.contains(CGPoint(x: z.midX, y: z.midY))
            }.map { CGRect(x: $0.gauche, y: $0.haut, width: $0.droite - $0.gauche, height: $0.bas - $0.haut) }
            // La prose reste du texte : la figure est ce qui reste du cadre à côté d'elle (la plus
            // grande des quatre bandes autour du bloc).
            var cadre = depart
            for p in blocsProse.filter({ $0.lignes >= 2 }).map(\.cadre) + mordent where p.intersects(cadre) {
                let bandes = [CGRect(x: cadre.minX, y: cadre.minY, width: p.minX - 4 - cadre.minX, height: cadre.height),
                              CGRect(x: p.maxX + 4, y: cadre.minY, width: cadre.maxX - p.maxX - 4, height: cadre.height),
                              CGRect(x: cadre.minX, y: cadre.minY, width: cadre.width, height: p.minY - 4 - cadre.minY),
                              CGRect(x: cadre.minX, y: p.maxY + 4, width: cadre.width, height: cadre.maxY - p.maxY - 4)]
                    .filter { $0.width > 0 && $0.height > 0 }.compactMap(serre)
                guard let plusGrande = bandes.max(by: { $0.width * $0.height < $1.width * $1.height }) else { cadre = .zero; break }
                cadre = plusGrande
            }
            // Les libellés qui la bordent (axes, légende, crédit photo), courts et plus petits que le
            // corps, sont de la figure ; un titre, une citation, une case de tableau restent du texte.
            var agrandi = true
            while agrandi {
                agrandi = false
                for l in visibles where l.texte.count <= 40 && !l.texte.hasSuffix(".") && l.taille <= corps - 2 {
                    let z = CGRect(x: l.gauche, y: l.haut, width: l.droite - l.gauche, height: l.bas - l.haut)
                    if !cadre.contains(z), cadre.insetBy(dx: -10, dy: -10).intersects(z) {
                        cadre = cadre.union(z); agrandi = true
                    }
                }
            }
            // Assez grande, pas un filet ni une bande d'en-tête, et sans prose restée dedans.
            guard cadre.width >= 60, cadre.height >= 40, cadre.width * cadre.height >= 6000,
                  cadre.width <= cadre.height * 8 else { continue }
            let restes = dedans(cadre)
            // Les libellés courts ne comptent pas : un graphique en est fait.
            let surface = restes.filter { $0.texte.count > 40 || $0.texte.hasSuffix(".") }
                .reduce(0.0) { $0 + ($1.droite - $1.gauche) * ($1.bas - $1.haut) }
            guard restes.filter(estProse).count <= 3, surface < Double(cadre.width * cadre.height) * 0.35 else { continue }
            // Et pas un fond presque vide : un quarantième de ses cases au moins porte de l'encre (les
            // trois courbes d'un graphique en lignes n'en couvrent guère plus).
            let x0 = Int(cadre.minX) / c, x1 = min(cw - 1, Int(cadre.maxX - 1) / c)
            let y0 = Int(cadre.minY) / c, y1 = min(ch - 1, Int(cadre.maxY - 1) / c)
            var pleines = 0
            for y in y0...y1 { for x in x0...x1 where encreBrute[y * cw + x] { pleines += 1 } }
            guard pleines * 40 >= (x1 - x0 + 1) * (y1 - y0 + 1) else { continue }
            // Une seule teinte presque partout (le fond d'un encadré, un bandeau de titre) : du décor.
            var teintes: [Int: Int] = [:], total = 0
            for y in Int(cadre.minY)..<min(h, Int(cadre.maxY)) {
                for x in Int(cadre.minX)..<min(w, Int(cadre.maxX)) where !texte[y * w + x] {
                    let i = (y * w + x) * 4
                    guard abs(Int(px[i]) - fr) + abs(Int(px[i + 1]) - fv) + abs(Int(px[i + 2]) - fb) > 60 else { continue }
                    teintes[Int(px[i] >> 4) << 8 | Int(px[i + 1] >> 4) << 4 | Int(px[i + 2] >> 4), default: 0] += 1
                    total += 1
                }
            }
            // Mesuré sur le bilan de législature de Fribourg (86 pages) : photos et graphiques sous 0,3 ;
            // encadrés et bandeaux au-dessus de 0,66, ou de 0,45 avec moins de quinze teintes.
            let dominante = Double(teintes.values.max() ?? 0) / Double(max(total, 1))
            guard dominante < 0.66, teintes.count >= 15 || dominante < 0.45 else { continue }
            r.append(cadre)
        }
        // Deux figures qui se touchent (un graphique et son axe de droite) n'en font qu'une.
        var fusion = true
        while fusion {
            fusion = false
            boucle: for i in r.indices { for j in r.indices where j > i && r[i].insetBy(dx: -14, dy: -14).intersects(r[j]) {
                r[i] = r[i].union(r[j]); r.remove(at: j); fusion = true; break boucle
            } }
        }
        return (visibles, r)
    }

    // MARK: Décor, signets, puces

    /// La clé d'une ligne pour reconnaître le décor : son texte sans chiffres (« Page 3 sur 12 »)
    /// et sa hauteur sur la page, à 10 points près.
    private static func cle(_ l: Ligne) -> String {
        // Une figure : sa place et sa taille — le logo qui revient sur chaque page.
        if l.bloc != nil { return "img|\(Int(l.haut / 10))|\(Int(l.gauche / 10))|\(Int((l.droite - l.gauche) / 10))|\(Int((l.bas - l.haut) / 10))" }
        return "\(Int(l.haut / 10))|" + l.texte.filter { !$0.isNumber }.trimmingCharacters(in: .whitespaces)
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
