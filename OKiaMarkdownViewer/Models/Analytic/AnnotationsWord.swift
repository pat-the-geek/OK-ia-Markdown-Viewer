import Foundation

/// Option Analytic (1.4) — les annotations dans l'export Word (Patrick, 27/10/2026, fonction Mac
/// n° 4) : le document annoté, à envoyer à un collègue.
///
/// - Un surlignage devient un vrai surlignage de Word, de la même couleur (au plus proche des
///   couleurs que Word connaît) ; un soulignement, un soulignement de la même couleur. Pas un
///   commentaire par passage surligné : le volet de relecture en serait noyé, et c'est le
///   surlignage que le lecteur attend.
/// - Une note manuscrite devient un **commentaire de relecture** ancré à son paragraphe, qui en
///   porte l'image.
///
/// Les passages sont retrouvés dans les blocs exportés comme la page les retrouve
/// (`annotations.js`) : la citation exacte, et ce qui l'entoure quand elle revient plusieurs fois.
/// Les espaces sont comparés réduits : l'export ne les garde pas toujours comme la page.
enum AnnotationsWord {

    /// La couleur de surlignage de Word et celle d'un soulignement, pour une couleur de md Viewer.
    static func surlignage(_ c: Annotation.Couleur) -> String {
        switch c { case .jaune: return "yellow"; case .vert: return "green"; case .rose: return "magenta"; case .bleu: return "cyan" }
    }
    static func soulignement(_ c: Annotation.Couleur) -> String {
        switch c { case .jaune: return "E8972E"; case .vert: return "24A048"; case .rose: return "E62878"; case .bleu: return "0A6EE6" }
    }

    /// Un endroit des blocs qui porte du texte : un paragraphe, un élément de liste, une cellule…
    private struct Segment {
        let bloc: Int
        let item: Int      // élément de liste, ou cellule (ligne × 1000 + colonne) ; 0 sinon
        var runs: [OOXMLRun]
    }

    static func appliquer(_ annotations: [Annotation], a blocs: [OOXMLBlock],
                          texteNote: String) -> (blocs: [OOXMLBlock], commentaires: [OOXMLCommentaire]) {
        guard !annotations.isEmpty else { return (blocs, []) }
        var segments = Self.segments(blocs)
        var commentaires: [OOXMLCommentaire] = []

        for a in annotations {
            switch a.type {
            case .encre:
                guard let bloc = a.ancre.media != nil ? blocDeMedia(a.ancre, blocs, segments) : blocDeNote(a.ancre, segments)
                else { continue }
                let image = a.image.flatMap { Data(base64Encoded: $0) }.flatMap(imagePNG)
                commentaires.append(OOXMLCommentaire(bloc: bloc, texte: texteNote, image: image))
            case .surligne, .souligne:
                guard let (debut, fin) = trouver(a.ancre, segments) else { continue }
                marquer(&segments, de: debut, a: fin) { r in
                    if a.type == .surligne { r.surligne = surlignage(a.couleur) } else { r.souligne = soulignement(a.couleur) }
                }
            }
        }
        return (reconstruire(blocs, segments), commentaires)
    }

    // MARK: Le texte des blocs

    private static func segments(_ blocs: [OOXMLBlock]) -> [Segment] {
        var s: [Segment] = []
        for (i, b) in blocs.enumerated() {
            switch b {
            case .heading(_, let r), .paragraph(let r), .quote(let r): s.append(Segment(bloc: i, item: 0, runs: r))
            case .list(_, let items): for (k, r) in items.enumerated() { s.append(Segment(bloc: i, item: k, runs: r)) }
            case .table(let rows):
                for (l, row) in rows.enumerated() { for (c, r) in row.enumerated() { s.append(Segment(bloc: i, item: l * 1000 + c, runs: r)) } }
            case .image(_, let caption): if !caption.isEmpty { s.append(Segment(bloc: i, item: 0, runs: caption)) }
            case .notes: break
            }
        }
        return s
    }

    private static func reconstruire(_ blocs: [OOXMLBlock], _ segments: [Segment]) -> [OOXMLBlock] {
        var resultat = blocs
        for seg in segments {
            switch resultat[seg.bloc] {
            case .heading(let n, _): resultat[seg.bloc] = .heading(level: n, runs: seg.runs)
            case .paragraph: resultat[seg.bloc] = .paragraph(runs: seg.runs)
            case .quote: resultat[seg.bloc] = .quote(runs: seg.runs)
            case .list(let o, var items): items[seg.item] = seg.runs; resultat[seg.bloc] = .list(ordered: o, items: items)
            case .table(var rows): rows[seg.item / 1000][seg.item % 1000] = seg.runs; resultat[seg.bloc] = .table(rows: rows)
            case .image(let img, _): resultat[seg.bloc] = .image(img, caption: seg.runs)
            case .notes: break
            }
        }
        return resultat
    }

    /// Le texte de tous les segments, séparés par un saut de ligne, espaces réduits ; et pour chaque
    /// caractère, son segment, son run et sa place dans le run.
    private struct Texte {
        var caracteres: [Character] = []
        var origine: [(segment: Int, run: Int, offset: Int)?] = []
    }

    private static func texte(_ segments: [Segment]) -> Texte {
        var t = Texte()
        var espace = true
        for (si, seg) in segments.enumerated() {
            // Entre deux blocs, un espace : la page met un saut de ligne, que le contexte réduit en espace.
            if si > 0, !espace { t.caracteres.append(" "); t.origine.append(nil); espace = true }
            for (ri, r) in seg.runs.enumerated() {
                for (oi, ch) in r.text.enumerated() {
                    if ch.isWhitespace {
                        if espace { continue }
                        t.caracteres.append(" "); t.origine.append((si, ri, oi)); espace = true
                    } else {
                        t.caracteres.append(ch); t.origine.append((si, ri, oi)); espace = false
                    }
                }
            }
        }
        return t
    }

    /// Les espaces réduits à un seul — sans rogner les bords : l'espace qui précède une citation
    /// compte pour le contexte (« Paragraphe 25. » + espace + citation).
    private static func reduire(_ s: String) -> [Character] {
        Array(s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
    }

    /// La citation, là où son contexte ressemble le plus : début et fin (exclue) dans le texte réduit.
    private static func trouver(_ ancre: AncreAnnotation, _ segments: [Segment]) -> (Int, Int)? {
        let t = texte(segments)
        let exact = Array(String(reduire(ancre.exact)).trimmingCharacters(in: .whitespaces))
        let avant = reduire(ancre.prefix), apres = reduire(ancre.suffix)
        guard !exact.isEmpty, exact.count <= t.caracteres.count else { return nil }
        var meilleur: (Int, Int)? = nil
        var i = 0
        while i + exact.count <= t.caracteres.count {
            if t.caracteres[i] == exact[0], Array(t.caracteres[i..<(i + exact.count)]) == exact {
                var score = 0
                while score < avant.count, i - 1 - score >= 0, t.caracteres[i - 1 - score] == avant[avant.count - 1 - score] { score += 1 }
                var s2 = 0
                while s2 < apres.count, i + exact.count + s2 < t.caracteres.count, t.caracteres[i + exact.count + s2] == apres[s2] { s2 += 1 }
                if meilleur == nil || score + s2 > meilleur!.1 { meilleur = (i, score + s2) }
            }
            i += 1
        }
        guard let (debut, _) = meilleur else { return nil }
        return (debut, debut + exact.count)
    }

    /// Coupe les runs pour que le passage [debut, fin) porte la marque.
    private static func marquer(_ segments: inout [Segment], de debut: Int, a fin: Int, _ marque: (inout OOXMLRun) -> Void) {
        let t = texte(segments)
        // Par run touché : le premier et le dernier caractère du passage (dans le run d'origine).
        var plages: [String: (segment: Int, run: Int, de: Int, a: Int)] = [:]
        for k in debut..<fin {
            guard let o = t.origine[k] else { continue }
            let cle = "\(o.segment)-\(o.run)"
            if let p = plages[cle] { plages[cle] = (p.segment, p.run, min(p.de, o.offset), max(p.a, o.offset + 1)) }
            else { plages[cle] = (o.segment, o.run, o.offset, o.offset + 1) }
        }
        // De la fin vers le début de chaque segment : couper un run décale les suivants.
        for p in plages.values.sorted(by: { ($0.segment, $0.run) > ($1.segment, $1.run) }) {
            var runs = segments[p.segment].runs
            let r = runs[p.run]
            guard r.note == nil else { continue }       // un appel de note reste entier
            let lettres = Array(r.text)
            var morceaux: [OOXMLRun] = []
            if p.de > 0 { var x = r; x.text = String(lettres[0..<p.de]); morceaux.append(x) }
            var m = r; m.text = String(lettres[p.de..<min(p.a, lettres.count)]); marque(&m); morceaux.append(m)
            if p.a < lettres.count { var x = r; x.text = String(lettres[p.a...]); morceaux.append(x) }
            runs.replaceSubrange(p.run...p.run, with: morceaux)
            segments[p.segment].runs = runs
        }
    }

    /// Le bloc d'une note manuscrite : celui dont le texte commence par la citation de l'ancre.
    private static func blocDeNote(_ ancre: AncreAnnotation, _ segments: [Segment]) -> Int? {
        let debut = Array(String(reduire(ancre.exact)).trimmingCharacters(in: .whitespaces))
        guard !debut.isEmpty else { return nil }
        let n = min(debut.count, 40)
        let tete = String(debut.prefix(n))
        return segments.first { seg in
            String(reduire(seg.runs.map(\.text).joined())).hasPrefix(tete)
        }?.bloc ?? segments.first { seg in
            String(reduire(seg.runs.map(\.text).joined())).contains(tete)
        }?.bloc
    }

    /// Le bloc d'une note posée sur un diagramme, une image ou une carte : la première image de
    /// l'export qui suit le texte d'avant (l'export fait une image de chacun, quand il le peut).
    private static func blocDeMedia(_ ancre: AncreAnnotation, _ blocs: [OOXMLBlock], _ segments: [Segment]) -> Int? {
        func image(_ i: Int) -> Bool { if case .image = blocs[i] { return true }; return false }
        let fin = String(reduire(ancre.prefix)).trimmingCharacters(in: .whitespaces)
        var depuis = 0
        if !fin.isEmpty {
            let queue = String(fin.suffix(30))
            guard let seg = segments.first(where: { String(reduire($0.runs.map(\.text).joined())).contains(queue) })
            else { return nil }
            // La légende d'une image précédente est à elle : notre image vient après.
            depuis = seg.bloc + 1
        }
        return (depuis..<blocs.count).first(where: image)
    }

    /// L'image d'une note (PNG tracé à l'échelle 3) et sa taille, lue dans l'en-tête du PNG.
    private static func imagePNG(_ data: Data) -> OOXMLImage? {
        guard data.count > 24, data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { return nil }
        func entier(_ o: Int) -> Int { data[o..<(o + 4)].reduce(0) { $0 << 8 | Int($1) } }
        let w = entier(16), h = entier(20)
        guard w > 0, h > 0 else { return nil }
        return OOXMLImage(data: data, widthPx: max(w / 3, 1), heightPx: max(h / 3, 1), isPNG: true)
    }
}
