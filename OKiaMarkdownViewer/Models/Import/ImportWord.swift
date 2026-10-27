import Foundation

/// Option Analytic (1.4) — un document Word devient un document md Viewer. Le chemin inverse de
/// l'export Word : les titres d'après leur style (ou leur niveau de plan), les listes d'après la
/// numérotation, le gras, l'italique et le barré, les liens, les tableaux, les images, les notes de
/// bas de page. Les commentaires de relecture deviennent des notes `[^c1]` à l'endroit commenté,
/// avec leur auteur ; les révisions suivies sont lues acceptées (le texte inséré gardé, le supprimé
/// écarté).
enum ImportWord {

    static func convertir(_ donnees: Data, nom: String, suivi: SuiviImport? = nil) async throws -> DocumentImporte {
        let zip = try LecteurZip(donnees)
        let partie = "word/document.xml"
        guard let xml = try zip.donnees(partie), let racine = NoeudXML.lire(xml),
              let corps = racine.descendant("w:body") else { throw LecteurZip.Erreur.pasUnZip }

        let styles = Styles(zip)
        var lu = Lecture(zip: zip, rels: MarkdownImport.relations(de: partie, dans: zip),
                         styles: styles, numeros: Numerotation(zip), reservoir: ReservoirImages(),
                         largeurTexte: Self.largeurTexte(corps))
        lu.commentaires = Self.commentaires(zip)
        lu.notes = Self.notes(zip)
        let stylesUtilises = corps.descendants("w:pStyle").compactMap { $0["w:val"] }
        if stylesUtilises.contains(where: styles.estTitreDuDocument) { lu.decalage = 1 }
        // Aucun titre par style ni par niveau de plan : le document est mis en forme à la main
        // (textutil, Pages, bien des modèles) — les titres se reconnaissent alors à leur taille.
        let titresParStyle = stylesUtilises.contains { styles.niveauDePlan($0) != nil || styles.estTitreDuDocument($0) }
            || corps.descendant("w:outlineLvl") != nil
        if !titresParStyle { lu.tailles = TaillesDeTitre(corps, defaut: styles.tailleParDefaut) }

        let blocs = corps.enfants
        for (i, bloc) in blocs.enumerated() {
            lu.bloc(bloc)
            // Un compte rendu toutes les 40 parties : assez pour le compte à rebours, sans le noyer.
            if i % 40 == 0 || i == blocs.count - 1 {
                await suivi?(AvancementImport(etape: tr("Paragraphes"), fait: i + 1, total: blocs.count,
                                              dernier: lu.dernierTitre))
            }
        }
        lu.fermerListe()

        let titre = Self.titreDuDocument(zip) ?? lu.titre ?? (nom as NSString).deletingPathExtension
        var md = MarkdownImport.entete(titre: titre, source: nom, genre: "document")
        md += "\n\n" + lu.lignes.joined(separator: "\n\n") + "\n"
        if !lu.definitionsDeNotes.isEmpty { md += "\n" + lu.definitionsDeNotes.joined(separator: "\n") + "\n" }
        if !lu.reservoir.definitions.isEmpty { md += "\n" + lu.reservoir.definitions.joined(separator: "\n") + "\n" }
        var parts = [tr("%d paragraphes", lu.paragraphes)]
        if lu.reservoir.nombre > 0 { parts.append(lu.reservoir.nombre == 1 ? tr("1 image") : tr("%d images", lu.reservoir.nombre)) }
        if lu.nombreDeCommentaires > 0 {
            parts.append(lu.nombreDeCommentaires == 1 ? tr("1 commentaire") : tr("%d commentaires", lu.nombreDeCommentaires))
        }
        return DocumentImporte(genre: .rapport, titre: titre, markdown: md, resume: parts.joined(separator: ", "),
                               consignes: lu.consignes)
    }

    // MARK: Le corps

    private struct Lecture {
        let zip: LecteurZip
        let rels: [String: (cible: String, type: String)]
        let styles: Styles
        let numeros: Numerotation
        let reservoir: ReservoirImages
        /// La largeur du texte, en EMU : la part qu'une image en occupe fixe sa définition.
        let largeurTexte: Double
        var commentaires: [String: (auteur: String, texte: String)] = [:]
        var notes: [String: String] = [:]

        var lignes: [String] = []
        var titre: String?
        var dernierTitre: String?
        var paragraphes = 0
        var definitionsDeNotes: [String] = []
        var nombreDeCommentaires = 0
        /// Les commentaires, avec le passage qu'ils commentent : des consignes possibles.
        var consignes: [ConsigneImport] = []
        private var marquesEnAttente: [String] = []
        private var passageCourant = ""
        /// Les lignes d'une liste en cours : une liste est un seul bloc, ses lignes sans blanc.
        private var liste: [String] = []
        /// Le numéro Word de la liste en cours : une autre liste qui suit en commence une nouvelle.
        private var listeEnCours: String?
        /// Le document a un paragraphe de style « Titre » : il prend le `#`, et les titres de
        /// niveau 1 descendent d'un cran.
        var decalage = 0
        /// Les tailles de police qui font un titre, quand le document n'a pas de styles de titre.
        var tailles: TaillesDeTitre?
        /// Un champ Word en cours (`fldChar` begin → instrText → separate → résultat → end) : le lien
        /// d'un champ `HYPERLINK`, que Word écrit ainsi plutôt qu'en `w:hyperlink` dans bien des cas.
        private var instruction: String?
        private var lienDeChamp: String?
        /// Les retraits des puces tapées à la main, pour en déduire le niveau.
        private var retraits: [Int] = []
        /// Le compteur de chaque liste numérotée, par numéro et par niveau.
        private var compteurs: [String: [Int: Int]] = [:]

        init(zip: LecteurZip, rels: [String: (cible: String, type: String)], styles: Styles,
             numeros: Numerotation, reservoir: ReservoirImages, largeurTexte: Double) {
            self.zip = zip; self.rels = rels; self.styles = styles; self.numeros = numeros
            self.reservoir = reservoir; self.largeurTexte = largeurTexte
        }

        mutating func bloc(_ n: NoeudXML) {
            if n.nom == "w:p" || n.nom == "w:tbl" { passageCourant = texteBrut(n) }
            switch n.nom {
            case "w:p":   paragraphe(n)
            case "w:tbl": fermerListe(); tableau(n)
            case "w:sdt": n.enfant("w:sdtContent")?.enfants.forEach { bloc($0) }
            default:      break
            }
            // Les marques des commentaires suivent leur bloc ; dans une liste, elles attendent sa fin
            // pour ne pas la couper.
            if liste.isEmpty { poserMarques() }
        }

        mutating func fermerListe() {
            guard !liste.isEmpty else { return }
            lignes.append(liste.joined(separator: "\n"))
            liste = []
            listeEnCours = nil
            poserMarques()
        }

        private mutating func poserMarques() {
            lignes += marquesEnAttente
            marquesEnAttente = []
        }

        private mutating func paragraphe(_ p: NoeudXML) {
            let ppr = p.enfant("w:pPr")
            let style = ppr?.enfant("w:pStyle")?["w:val"]
            let texte = enLigne(p).trimmingCharacters(in: .whitespaces)
            // Une image seule dans son paragraphe n'en reste pas moins un paragraphe.
            guard !texte.isEmpty else { return }
            paragraphes += 1

            // Un titre : le niveau de plan du paragraphe, sinon celui de son style.
            let niveauPlan = ppr?.enfant("w:outlineLvl")?["w:val"].flatMap(Int.init) ?? styles.niveauDePlan(style)
            if styles.estTitreDuDocument(style) {
                fermerListe()
                if titre == nil { titre = texteBrut(p) }
                dernierTitre = texteBrut(p)
                lignes.append("# " + texte)
                return
            }
            if let n = niveauPlan, n < 6 {
                fermerListe()
                dernierTitre = texteBrut(p)
                if titre == nil, n == 0 { titre = dernierTitre }
                lignes.append(String(repeating: "#", count: min(6, n + 1 + decalage)) + " " + texte)
                return
            }
            // Une liste : la numérotation du paragraphe, sinon celle de son style.
            if let num = ppr?.enfant("w:numPr") ?? styles.numerotation(style),
               let id = num.enfant("w:numId")?["w:val"], id != "0" {
                let niveau = Int(num.enfant("w:ilvl")?["w:val"] ?? "") ?? 0
                if listeEnCours != id { fermerListe(); listeEnCours = id }
                let marque: String
                if numeros.estNumerotee(id, niveau: niveau) {
                    var c = compteurs[id] ?? [:]
                    c[niveau, default: 0] += 1
                    // Revenir à un niveau remet les sous-niveaux à zéro.
                    for k in c.keys where k > niveau { c[k] = nil }
                    compteurs[id] = c
                    marque = "\(c[niveau]!)."
                } else {
                    marque = "-"
                }
                liste.append(String(repeating: "   ", count: niveau) + marque + " " + texte)
                return
            }
            // Un titre reconnu à sa taille, une puce ou un numéro tapés à la main.
            if let tailles, let n = tailles.niveau(p), texteBrut(p).count <= 150 {
                fermerListe()
                dernierTitre = texteBrut(p)
                if titre == nil { titre = dernierTitre }
                lignes.append(String(repeating: "#", count: n) + " " + MarkdownImport.echapper(texteBrut(p)))
                return
            }
            if let (marque, reste) = Self.puceTapee(texte, brut: texteAvecTabulations(p)) {
                let genre = marque == "-" ? "puces" : "numeros"
                if listeEnCours != genre { fermerListe(); listeEnCours = genre; retraits = [] }
                let retrait = Int(ppr?.enfant("w:ind")?["w:left"] ?? ppr?.enfant("w:ind")?["w:start"] ?? "") ?? 0
                if !retraits.contains(retrait) { retraits.append(retrait); retraits.sort() }
                let niveau = retraits.firstIndex(of: retrait) ?? 0
                liste.append(String(repeating: "   ", count: niveau) + marque + " " + reste)
                return
            }
            fermerListe()
            // Citation : les styles « Quote » / « Citation ».
            if styles.estCitation(style) {
                lignes.append("> " + texte)
            } else {
                lignes.append(MarkdownImport.debutDeLigne(texte))
            }
        }

        /// Une puce (« • », « ◦ », « – ») ou un numéro (« 3 » suivi d'une tabulation, « 3. ») tapés
        /// en tête du paragraphe : la marque Markdown et le reste du texte mis en forme.
        static func puceTapee(_ texte: String, brut: String) -> (String, String)? {
            if let r = brut.range(of: #"^\s*(\d{1,3})(?:[.)]\s*|\t)"#, options: .regularExpression),
               let n = Int(brut[r].filter(\.isNumber)) {
                guard let m = texte.range(of: #"^\s*\d{1,3}(?:\\?[.)])?\s*"#, options: .regularExpression) else { return nil }
                return ("\(n).", String(texte[m.upperBound...]))
            }
            guard brut.range(of: #"^\s*[•◦▪▫‣⁃●○■□–·]\s"#, options: .regularExpression) != nil,
                  let m = texte.range(of: #"^\s*[•◦▪▫‣⁃●○■□–·]\s*"#, options: .regularExpression) else { return nil }
            return ("-", String(texte[m.upperBound...]))
        }

        private func texteAvecTabulations(_ p: NoeudXML) -> String {
            p.descendants("w:r").flatMap(\.enfants).map { $0.nom == "w:tab" ? "\t" : ($0.nom == "w:t" ? $0.texte : "") }.joined()
        }

        private func texteBrut(_ p: NoeudXML) -> String {
            p.descendants("w:t").map(\.texte).joined(separator: p.nom == "w:tbl" ? " " : "").trimmingCharacters(in: .whitespaces)
        }

        // MARK: Le texte d'un paragraphe

        /// Un passage de texte et sa mise en forme, avant qu'on ne regroupe les voisins pareils.
        private struct Passage {
            var texte: String
            var gras = false, italique = false, barre = false
            var lien: String?
            /// Déjà du Markdown (image, appel de note) : ni échappé ni mis en forme.
            var brut = false
        }

        private mutating func enLigne(_ p: NoeudXML) -> String {
            var passages: [Passage] = []
            parcourir(p, lien: nil, dans: &passages)
            return composer(passages)
        }

        private mutating func parcourir(_ n: NoeudXML, lien: String?, dans passages: inout [Passage]) {
            for e in n.enfants {
                switch e.nom {
                case "w:r":
                    passer(e, lien: lien, dans: &passages)
                case "w:hyperlink":
                    var cible = e["r:id"].flatMap { rels[$0]?.cible }
                    if cible == nil, let ancre = e["w:anchor"] { cible = "#" + ancre }
                    parcourir(e, lien: cible ?? lien, dans: &passages)
                case "w:ins", "w:smartTag", "w:fldSimple", "w:customXml":
                    parcourir(e, lien: lien, dans: &passages)
                case "w:sdt":
                    if let c = e.enfant("w:sdtContent") { parcourir(c, lien: lien, dans: &passages) }
                case "w:commentReference":
                    commentaire(e["w:id"], dans: &passages)
                default:
                    break   // w:del, w:pPr, w:bookmarkStart…
                }
            }
        }

        private mutating func passer(_ r: NoeudXML, lien: String?, dans passages: inout [Passage]) {
            let rpr = r.enfant("w:rPr")
            func actif(_ nom: String) -> Bool {
                guard let b = rpr?.enfant(nom) else { return false }
                return !["0", "false", "none"].contains(b["w:val"] ?? "")
            }
            for e in r.enfants {
                switch e.nom {
                case "w:fldChar":
                    switch e["w:fldCharType"] {
                    case "begin":    instruction = ""; lienDeChamp = nil
                    case "separate": lienDeChamp = instruction.flatMap(Self.lienHyperlink); instruction = nil
                    default:         instruction = nil; lienDeChamp = nil
                    }
                case "w:instrText":
                    instruction? += e.texte
                default:
                    break
                }
            }
            // Le code d'un champ n'est pas du texte.
            if instruction != nil { return }
            let modele = Passage(texte: "", gras: actif("w:b"), italique: actif("w:i"),
                                 barre: actif("w:strike") || actif("w:dstrike"), lien: lien ?? lienDeChamp)
            for e in r.enfants {
                switch e.nom {
                case "w:t":
                    var p = modele; p.texte = e.texte; passages.append(p)
                case "w:tab":
                    var p = modele; p.texte = " "; passages.append(p)
                case "w:br", "w:cr":
                    var p = modele; p.texte = "  \n"; p.brut = true; passages.append(p)
                case "w:noBreakHyphen":
                    var p = modele; p.texte = "-"; passages.append(p)
                case "w:drawing", "w:pict", "w:object":
                    if let md = image(e) { passages.append(Passage(texte: md, brut: true)) }
                case "w:footnoteReference", "w:endnoteReference":
                    note(e["w:id"], prefixe: e.nom == "w:endnoteReference" ? "fin" : "", dans: &passages)
                case "w:commentReference":
                    commentaire(e["w:id"], dans: &passages)
                default:
                    break   // w:rPr, w:instrText (le code d'un champ), w:delText
                }
            }
        }

        /// L'adresse d'un champ `HYPERLINK "https://…"` (ou `HYPERLINK \l "signet"`).
        static func lienHyperlink(_ instruction: String) -> String? {
            let t = instruction.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("HYPERLINK"),
                  let r = t.range(of: #""[^"]+""#, options: .regularExpression) else { return nil }
            let cible = String(t[r].dropFirst().dropLast())
            return t.contains("\\l") ? "#" + cible : cible
        }

        /// Les passages regroupés : `**a b**` plutôt que `**a****b**`.
        private func composer(_ passages: [Passage]) -> String {
            var r = ""
            var i = 0
            while i < passages.count {
                let p = passages[i]
                if p.brut { r += p.texte; i += 1; continue }
                var texte = p.texte
                var j = i + 1
                while j < passages.count, !passages[j].brut, passages[j].gras == p.gras,
                      passages[j].italique == p.italique, passages[j].barre == p.barre, passages[j].lien == p.lien {
                    texte += passages[j].texte; j += 1
                }
                r += Self.mettreEnForme(texte, p)
                i = j
            }
            return r
        }

        /// Les marques à l'intérieur des espaces : `**gras** suite`, jamais `**gras **suite`.
        private static func mettreEnForme(_ texte: String, _ p: Passage) -> String {
            let coeur = texte.trimmingCharacters(in: .whitespaces)
            guard !coeur.isEmpty else { return texte }
            let avant = texte.prefix { $0 == " " }, apres = String(texte.reversed().prefix { $0 == " " })
            var m = MarkdownImport.echapper(coeur)
            if p.barre { m = "~~\(m)~~" }
            if p.italique { m = "*\(m)*" }
            if p.gras { m = "**\(m)**" }
            if let lien = p.lien { m = "[\(m)](\(lien.replacingOccurrences(of: " ", with: "%20")))" }
            return avant + m + apres
        }

        // MARK: Images, notes, commentaires

        private func image(_ dessin: NoeudXML) -> String? {
            let id = dessin.descendant("a:blip")?["r:embed"] ?? dessin.descendant("v:imagedata")?["r:id"]
            guard let id, let cible = rels[id]?.cible else { return nil }
            let largeur = Double(dessin.descendant("wp:extent")?["cx"] ?? "")
            let zip = self.zip
            guard let ref = reservoir.reference(cible, part: largeur.map { $0 / largeurTexte },
                                                donnees: { try? zip.donnees(cible) }) else { return nil }
            let alt = dessin.descendant("wp:docPr")?["descr"] ?? dessin.descendant("wp:docPr")?["title"] ?? ""
            return "![\(MarkdownImport.texteAlt(alt))][\(ref)]"
        }

        private mutating func note(_ id: String?, prefixe: String, dans passages: inout [Passage]) {
            guard let id, let texte = notes[prefixe + id] else { return }
            let etiquette = "\(prefixe.isEmpty ? "" : "fin")\(definitionsDeNotes.count + 1)"
            definitionsDeNotes.append("[^\(etiquette)]: " + texte)
            passages.append(Passage(texte: "[^\(etiquette)]", brut: true))
        }

        private mutating func commentaire(_ id: String?, dans passages: inout [Passage]) {
            guard let id, let c = commentaires[id] else { return }
            nombreDeCommentaires += 1
            let etiquette = "c\(nombreDeCommentaires)"
            let auteur = c.auteur.isEmpty ? "" : c.auteur + " : "
            definitionsDeNotes.append("[^\(etiquette)]: 💬 " + auteur + MarkdownImport.echapper(c.texte))
            passages.append(Passage(texte: "[^\(etiquette)]", brut: true))
            // De quoi le rédiger plus tard, si l'utilisateur le demande à l'import.
            consignes.append(ConsigneImport(numero: nombreDeCommentaires, auteur: c.auteur, commentaire: c.texte,
                                            passage: passageCourant, section: dernierTitre))
            marquesEnAttente.append(ConsigneImport.marque(nombreDeCommentaires))
        }

        // MARK: Tableaux

        private mutating func tableau(_ t: NoeudXML) {
            let rangees = t.enfants("w:tr").map { tr in
                tr.enfants("w:tc").map { tc in
                    tc.enfants("w:p").map { enLigne($0) }.filter { !$0.isEmpty }.joined(separator: "<br>")
                }
            }
            // Les cellules sont déjà du Markdown : on ne les échappe pas une seconde fois.
            guard let entete = rangees.first, !entete.isEmpty else { return }
            let n = rangees.map(\.count).max() ?? entete.count
            func ligne(_ l: [String]) -> String {
                // Les barres du texte sont déjà échappées (`echapper`).
                "| " + (0..<n).map { $0 < l.count ? l[$0] : "" }.joined(separator: " | ") + " |"
            }
            var r = [ligne(entete), "| " + Array(repeating: "---", count: n).joined(separator: " | ") + " |"]
            r += rangees.dropFirst().map(ligne)
            lignes.append(r.joined(separator: "\n"))
        }
    }

    // MARK: Styles et numérotation

    /// Ce que `styles.xml` dit des styles de paragraphe : leur nom anglais (Word l'écrit toujours en
    /// anglais pour ses styles intégrés : « heading 1 », « Title », « Quote »), leur niveau de plan,
    /// leur numérotation et leur style parent.
    private struct Styles {
        private var noms: [String: String] = [:]
        private var plans: [String: Int] = [:]
        private var numeros: [String: NoeudXML] = [:]
        private var parents: [String: String] = [:]
        /// La taille du texte par défaut, en demi-points (11 pt, celle de Word, s'il ne la donne pas).
        private(set) var tailleParDefaut = 22

        init(_ zip: LecteurZip) {
            guard let xml = try? zip.donnees("word/styles.xml"), let racine = NoeudXML.lire(xml) else { return }
            if let t = racine.descendant("w:docDefaults")?.descendant("w:sz")?["w:val"].flatMap(Int.init) { tailleParDefaut = t }
            for s in racine.enfants("w:style") where s["w:type"] == "paragraph" {
                guard let id = s["w:styleId"] else { continue }
                noms[id] = s.enfant("w:name")?["w:val"]?.lowercased()
                if let p = s.enfant("w:basedOn")?["w:val"] { parents[id] = p }
                if let ppr = s.enfant("w:pPr") {
                    if let n = ppr.enfant("w:outlineLvl")?["w:val"].flatMap(Int.init) { plans[id] = n }
                    if let num = ppr.enfant("w:numPr") { numeros[id] = num }
                }
            }
        }

        private func remonter<T>(_ id: String?, _ valeur: (String) -> T?) -> T? {
            var courant = id, tours = 0
            while let c = courant, tours < 10 {
                if let v = valeur(c) { return v }
                courant = parents[c]; tours += 1
            }
            return nil
        }

        func niveauDePlan(_ id: String?) -> Int? {
            remonter(id) { id in
                if let n = plans[id] { return n }
                // « heading 2 » sans niveau de plan explicite.
                if let nom = noms[id], nom.hasPrefix("heading "), let n = Int(nom.dropFirst(8)) { return n - 1 }
                return nil
            }
        }

        func estTitreDuDocument(_ id: String?) -> Bool { id.flatMap { noms[$0] } == "title" }

        func estCitation(_ id: String?) -> Bool {
            guard let nom = id.flatMap({ noms[$0] }) else { return false }
            return nom == "quote" || nom == "intense quote" || nom == "block text"
        }

        func numerotation(_ id: String?) -> NoeudXML? { remonter(id) { numeros[$0] } }
    }

    /// Les titres d'un document sans styles de titre : les tailles de police nettement plus grandes
    /// que celle du corps (la plus répandue, au nombre de caractères), de la plus grande (`#`) à la
    /// plus petite, trois niveaux au plus. Un paragraphe est titre si TOUT son texte a cette taille.
    struct TaillesDeTitre {
        private var niveaux: [Int: Int] = [:]
        private let defaut: Int

        init(_ corps: NoeudXML, defaut: Int) {
            self.defaut = defaut
            var parTaille: [Int: Int] = [:]
            var tete: Set<Int> = []
            for p in corps.descendants("w:p") {
                for r in p.descendants("w:r") {
                    let n = r.descendants("w:t").map(\.texte.count).reduce(0, +)
                    parTaille[Self.taille(r, defaut: defaut), default: 0] += n
                }
                if let t = Self.tailleUnique(p, defaut: defaut) { tete.insert(t) }
            }
            guard let corpsTaille = parTaille.max(by: { $0.value < $1.value })?.key else { return }
            let grandes = tete.filter { Double($0) >= Double(corpsTaille) * 1.15 }.sorted(by: >).prefix(3)
            for (i, t) in grandes.enumerated() { niveaux[t] = i + 1 }
        }

        func niveau(_ p: NoeudXML) -> Int? { Self.tailleUnique(p, defaut: defaut).flatMap { niveaux[$0] } }

        /// La taille d'un passage, en demi-points.
        static func taille(_ r: NoeudXML, defaut: Int) -> Int {
            Int(r.enfant("w:rPr")?.enfant("w:sz")?["w:val"] ?? "") ?? defaut
        }

        /// La taille de tout le texte du paragraphe, s'il n'en a qu'une.
        static func tailleUnique(_ p: NoeudXML, defaut: Int) -> Int? {
            let t = Set(p.descendants("w:r").filter { !$0.descendants("w:t").isEmpty }.map { taille($0, defaut: defaut) })
            return t.count == 1 ? t.first : nil
        }
    }

    /// `numbering.xml` : une liste numérotée ou à puces, par numéro et par niveau.
    private struct Numerotation {
        /// numId → abstractNumId
        private var abstraits: [String: String] = [:]
        /// abstractNumId → niveau → format (« bullet », « decimal »…)
        private var formats: [String: [Int: String]] = [:]

        init(_ zip: LecteurZip) {
            guard let xml = try? zip.donnees("word/numbering.xml"), let racine = NoeudXML.lire(xml) else { return }
            for a in racine.enfants("w:abstractNum") {
                guard let id = a["w:abstractNumId"] else { continue }
                var f: [Int: String] = [:]
                for l in a.enfants("w:lvl") {
                    if let n = Int(l["w:ilvl"] ?? ""), let fmt = l.enfant("w:numFmt")?["w:val"] { f[n] = fmt }
                }
                formats[id] = f
            }
            for n in racine.enfants("w:num") {
                if let id = n["w:numId"], let a = n.enfant("w:abstractNumId")?["w:val"] { abstraits[id] = a }
            }
        }

        func estNumerotee(_ numId: String, niveau: Int) -> Bool {
            guard let a = abstraits[numId], let fmt = formats[a]?[niveau] else { return false }
            return fmt != "bullet" && fmt != "none"
        }
    }

    // MARK: Parties annexes

    /// Les commentaires de relecture : identifiant → (auteur, texte).
    private static func commentaires(_ zip: LecteurZip) -> [String: (auteur: String, texte: String)] {
        guard let xml = try? zip.donnees("word/comments.xml"), let racine = NoeudXML.lire(xml) else { return [:] }
        var r: [String: (String, String)] = [:]
        for c in racine.enfants("w:comment") {
            guard let id = c["w:id"] else { continue }
            let texte = c.descendants("w:p").map { $0.descendants("w:t").map(\.texte).joined() }
                .filter { !$0.isEmpty }.joined(separator: " ")
            r[id] = (c["w:author"] ?? "", texte)
        }
        return r
    }

    /// Les notes de bas de page et de fin, en texte simple : « 3 » et « fin3 ».
    private static func notes(_ zip: LecteurZip) -> [String: String] {
        var r: [String: String] = [:]
        for (fichier, balise, prefixe) in [("word/footnotes.xml", "w:footnote", ""), ("word/endnotes.xml", "w:endnote", "fin")] {
            guard let xml = try? zip.donnees(fichier), let racine = NoeudXML.lire(xml) else { continue }
            for n in racine.enfants(balise) where n["w:type"] == nil {
                guard let id = n["w:id"] else { continue }
                let texte = n.descendants("w:p").map { $0.descendants("w:t").map(\.texte).joined() }
                    .joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !texte.isEmpty { r[prefixe + id] = MarkdownImport.echapper(texte) }
            }
        }
        return r
    }

    /// Le titre des propriétés du document (`docProps/core.xml`), quand l'auteur l'a rempli.
    private static func titreDuDocument(_ zip: LecteurZip) -> String? {
        guard let xml = try? zip.donnees("docProps/core.xml"), let racine = NoeudXML.lire(xml),
              let t = racine.descendant("dc:title")?.texte.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        return t
    }

    /// La largeur du texte de la première section, en EMU (la page moins ses marges, en vingtièmes
    /// de point) ; 6 pouces si le document ne la donne pas.
    private static func largeurTexte(_ corps: NoeudXML) -> Double {
        guard let sect = corps.descendant("w:sectPr"),
              let page = Double(sect.enfant("w:pgSz")?["w:w"] ?? "") else { return 5_486_400 }
        let marges = (Double(sect.enfant("w:pgMar")?["w:left"] ?? "") ?? 1440)
            + (Double(sect.enfant("w:pgMar")?["w:right"] ?? "") ?? 1440)
        return max(1, page - marges) * 635
    }
}
