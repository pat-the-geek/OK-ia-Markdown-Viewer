import Foundation

/// Option Analytic (1.4) — un PowerPoint devient une présentation md Viewer : une diapositive par
/// bloc séparé par `---`. C'est le chemin inverse de l'export (`OOXMLExport`) : les diapositives
/// dans l'ordre de `presentation.xml`, leur titre en `##` (`#` pour une diapositive de titre), leurs
/// puces avec leur niveau, leurs tableaux et leurs images ; les notes de l'orateur et les
/// commentaires dans un commentaire HTML sous la diapositive — gardés dans le fichier, pas
/// affichés. La transition de la présentation, quand md Viewer la connaît, va dans l'en-tête.
enum ImportPowerPoint {

    static func convertir(_ donnees: Data, nom: String, suivi: SuiviImport? = nil) async throws -> DocumentImporte {
        let zip = try LecteurZip(donnees)
        guard let pres = try zip.donnees("ppt/presentation.xml"), let racine = NoeudXML.lire(pres) else {
            throw LecteurZip.Erreur.pasUnZip
        }
        let rels = MarkdownImport.relations(de: "ppt/presentation.xml", dans: zip)
        let ordre = (racine.descendant("p:sldIdLst")?.enfants("p:sldId") ?? []).compactMap { rels[$0["r:id"] ?? ""]?.cible }
        let auteurs = Self.auteurs(zip)
        let taille = racine.descendant("p:sldSz")
        let page = (Double(taille?["cx"] ?? "") ?? 12_192_000, Double(taille?["cy"] ?? "") ?? 6_858_000)

        var diapositives: [String] = []
        var titre: String?
        let reservoir = ReservoirImages()
        var transitions: [String: Int] = [:]
        for (i, partie) in ordre.enumerated() {
            guard let xml = try zip.donnees(partie), let diapo = NoeudXML.lire(xml) else { continue }
            let relsDiapo = MarkdownImport.relations(de: partie, dans: zip)
            var lu = Lecture(zip: zip, rels: relsDiapo, reservoir: reservoir, page: page)
            if let arbre = diapo.descendant("p:spTree") { lu.parcourir(arbre, premiere: i == 0) }
            if titre == nil { titre = lu.titre }
            if let t = Self.transition(diapo) { transitions[t, default: 0] += 1 }

            var bloc = lu.lignes.joined(separator: "\n\n")
            var cache: [String] = []
            if let notes = Self.notes(relsDiapo, zip: zip), !notes.isEmpty {
                cache.append(tr("Notes de l’orateur :") + "\n" + notes)
            }
            let comms = Self.commentaires(partie: partie, rels: relsDiapo, zip: zip, auteurs: auteurs)
            if !comms.isEmpty { cache.append(tr("Commentaires :") + "\n" + comms.joined(separator: "\n")) }
            if !cache.isEmpty {
                // `--` est interdit dans un commentaire HTML : il le fermerait trop tôt.
                let propre = cache.joined(separator: "\n\n").replacingOccurrences(of: "--", with: "—")
                bloc += (bloc.isEmpty ? "" : "\n\n") + "<!--\n" + propre + "\n-->"
            }
            diapositives.append(bloc.isEmpty ? "&nbsp;" : bloc)
            await suivi?(AvancementImport(etape: tr("Diapositives"), fait: i + 1, total: ordre.count,
                                          dernier: lu.titre))
        }

        let titreFinal = titre ?? (nom as NSString).deletingPathExtension
        var extra: [String: String] = [:]
        if let t = transitions.max(by: { $0.value < $1.value })?.key { extra["transition"] = t }
        let markdown = MarkdownImport.entete(titre: titreFinal, source: nom, genre: "presentation", extra: extra)
            + "\n\n" + diapositives.joined(separator: "\n\n---\n\n") + "\n"
            + (reservoir.definitions.isEmpty ? "" : "\n" + reservoir.definitions.joined(separator: "\n") + "\n")
        let resume = tr("%d diapositives, %d images", diapositives.count, reservoir.nombre)
        return DocumentImporte(genre: .presentation, titre: titreFinal, markdown: markdown, resume: resume)
    }

    // MARK: Une diapositive

    private struct Lecture {
        let zip: LecteurZip
        let rels: [String: (cible: String, type: String)]
        let reservoir: ReservoirImages
        /// La taille de la diapositive, en EMU.
        let page: (Double, Double)
        var lignes: [String] = []
        var titre: String?

        mutating func parcourir(_ arbre: NoeudXML, premiere: Bool) {
            for forme in arbre.enfants {
                switch forme.nom {
                case "p:sp":           texte(forme, premiere: premiere)
                case "p:pic":          image(forme)
                case "p:graphicFrame": if let t = forme.descendant("a:tbl") { tableau(t) }
                case "p:grpSp":        parcourir(forme, premiere: premiere)
                default:               break
                }
            }
        }

        private mutating func texte(_ forme: NoeudXML, premiere: Bool) {
            let ph = forme.descendant("p:nvPr")?.enfant("p:ph")
            let genre = ph?["type"] ?? (ph != nil ? "body" : "")
            if ["sldNum", "dt", "ftr", "hdr", "sldImg"].contains(genre) { return }
            guard let corps = forme.descendant("p:txBody") else { return }
            let paragraphes = corps.enfants("a:p").map { (Self.texte($0), Self.niveau($0), Self.puce($0)) }
                .filter { !$0.0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !paragraphes.isEmpty else { return }
            if genre == "title" || genre == "ctrTitle" {
                let t = paragraphes.map(\.0).joined(separator: " ")
                if titre == nil { titre = t }
                lignes.append((genre == "ctrTitle" || premiere ? "# " : "## ") + MarkdownImport.echapper(t))
                return
            }
            // Le corps d'un espace réservé est en puces, sauf avis contraire du paragraphe ; une zone
            // de texte libre est en paragraphes, sauf puce explicite.
            let parDefautPuces = genre == "body" || genre == "obj"
            var bloc: [String] = []
            for (t, niveau, puce) in paragraphes {
                let enPuce = puce ?? parDefautPuces
                let ligne = MarkdownImport.echapper(t)
                bloc.append(enPuce ? String(repeating: "  ", count: niveau) + "- " + ligne : ligne)
            }
            lignes.append(bloc.joined(separator: parDefautPuces ? "\n" : "\n\n"))
        }

        private mutating func image(_ forme: NoeudXML) {
            guard let id = forme.descendant("a:blip")?["r:embed"], let cible = rels[id]?.cible else { return }
            let zip = self.zip
            // La place de l'image sur la diapositive : un logo dans un coin n'a pas besoin de 1600 px.
            let ext = forme.descendant("a:ext")
            let part = max((Double(ext?["cx"] ?? "") ?? 0) / page.0, (Double(ext?["cy"] ?? "") ?? 0) / page.1)
            guard let ref = reservoir.reference(cible, part: part > 0 ? part : nil,
                                                donnees: { try? zip.donnees(cible) }) else { return }
            let alt = forme.descendant("p:cNvPr")?["descr"] ?? ""
            lignes.append("![\(MarkdownImport.echapper(alt))][\(ref)]")
        }

        private mutating func tableau(_ t: NoeudXML) {
            let lignesTab = t.enfants("a:tr").map { tr in
                tr.enfants("a:tc").map { tc in tc.descendants("a:p").map(Self.texte).joined(separator: " ") }
            }
            let md = MarkdownImport.tableau(lignesTab)
            if !md.isEmpty { lignes.append(md) }
        }

        /// Le texte d'un paragraphe : ses passages (`a:r`), ses champs (`a:fld`) et ses retours.
        static func texte(_ p: NoeudXML) -> String {
            var r = ""
            for e in p.enfants {
                switch e.nom {
                case "a:r", "a:fld": r += e.enfant("a:t")?.texte ?? ""
                case "a:br":         r += " "
                default:             break
                }
            }
            return r.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func niveau(_ p: NoeudXML) -> Int { Int(p.enfant("a:pPr")?["lvl"] ?? "") ?? 0 }

        /// nil : rien dit ; vrai : une puce explicite ; faux : `a:buNone`.
        static func puce(_ p: NoeudXML) -> Bool? {
            guard let ppr = p.enfant("a:pPr") else { return nil }
            if ppr.enfant("a:buNone") != nil { return false }
            if ppr.enfant("a:buChar") != nil || ppr.enfant("a:buAutoNum") != nil { return true }
            return nil
        }
    }

    // MARK: Notes, commentaires, transition

    /// Le texte des notes de l'orateur : le corps de la page de notes, sans l'image de la
    /// diapositive ni son numéro.
    private static func notes(_ rels: [String: (cible: String, type: String)], zip: LecteurZip) -> String? {
        guard let cible = rels.values.first(where: { $0.type.hasSuffix("/notesSlide") })?.cible,
              let xml = try? zip.donnees(cible), let racine = NoeudXML.lire(xml) else { return nil }
        var r: [String] = []
        for forme in racine.descendants("p:sp") {
            let genre = forme.descendant("p:ph")?["type"] ?? ""
            guard genre == "body" || genre.isEmpty else { continue }
            for p in forme.descendants("a:p") {
                let t = Lecture.texte(p)
                if !t.isEmpty { r.append(t) }
            }
        }
        return r.joined(separator: "\n")
    }

    /// Les auteurs des commentaires : l'ancien format (`commentAuthors.xml`) et le nouveau
    /// (`authors.xml`, PowerPoint 365).
    private static func auteurs(_ zip: LecteurZip) -> [String: String] {
        var r: [String: String] = [:]
        if let xml = try? zip.donnees("ppt/commentAuthors.xml"), let racine = NoeudXML.lire(xml) {
            for a in racine.enfants("p:cmAuthor") { if let id = a["id"], let n = a["name"] { r[id] = n } }
        }
        for nom in zip.noms where nom.hasPrefix("ppt/") && nom.hasSuffix("authors.xml") {
            guard let xml = try? zip.donnees(nom), let racine = NoeudXML.lire(xml) else { continue }
            for a in racine.descendants("p188:author") { if let id = a["id"], let n = a["name"] { r[id] = n } }
        }
        return r
    }

    private static func commentaires(partie: String, rels: [String: (cible: String, type: String)], zip: LecteurZip,
                                     auteurs: [String: String]) -> [String] {
        var r: [String] = []
        for rel in rels.values where rel.type.hasSuffix("/comments") || rel.type.contains("modernComment") {
            guard let xml = try? zip.donnees(rel.cible), let racine = NoeudXML.lire(xml) else { continue }
            for c in racine.descendants("p:cm") {
                let t = c.enfant("p:text")?.texte.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !t.isEmpty { r.append("- " + (auteurs[c["authorId"] ?? ""].map { "\($0) : " } ?? "") + t) }
            }
            for c in racine.descendants("p188:cm") {
                let t = c.descendants("a:p").map(Lecture.texte).joined(separator: " ")
                if !t.isEmpty { r.append("- " + (auteurs[c["authorId"] ?? ""].map { "\($0) : " } ?? "") + t) }
            }
        }
        return r
    }

    /// La transition d'une diapositive, dans les noms du diaporama de md Viewer ; la table inverse
    /// de `OOXMLExport.transition`.
    static func transition(_ diapo: NoeudXML) -> String? {
        guard let t = diapo.descendant("p:transition"), let effet = t.enfants.first else { return nil }
        switch effet.nom {
        case "p:fade":           return effet["thruBlk"] == "1" ? "black" : "dissolve"
        case "p:push":           return "push"
        case "p:cover":          return "movein"
        case "p14:flythrough":   return "scale"
        case "p14:flip":         return "flip"
        case "p:wipe":           return "wipe"
        case "p:pull":           return "reveal"
        case "p14:prism":        return "cube"
        case "p:circle":         return "iris"
        case "p14:glitter":      return "checker"
        default:                 return nil
        }
    }
}
