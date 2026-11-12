import Foundation

/// Option Analytic (1.7) — un classeur Excel (`.xlsx`) ou un fichier CSV devient un document
/// Markdown : une section par feuille, un tableau par section (Patrick, 13/11/2026 : « Pages,
/// Keynote, Numbers, Excel and CSV […] an Excel workbook or a CSV file becomes a table »).
///
/// Le classeur se lit comme un `.docx` : un zip de XML (`LecteurZip`, `NoeudXML`). Les valeurs sont
/// celles qu'Excel a enregistrées : le texte, les nombres tels quels, les dates (cellules au format
/// date) en AAAA-MM-JJ, les formules par leur dernier résultat.
enum ImportTableur {
    static let extensions: Set<String> = ["xlsx", "csv", "tsv"]

    /// Au-delà, le tableau s'arrête et le document le dit : un journal de 100 000 lignes ne se lit
    /// pas en Markdown.
    static let lignesMax = 2_000

    enum Erreur: Error, LocalizedError {
        case vide
        var errorDescription: String? { tr("Ce tableur ne contient aucune cellule lisible.") }
    }

    static func convertir(_ donnees: Data, nom: String, suivi: SuiviImport? = nil) async throws -> DocumentImporte {
        let ext = (nom as NSString).pathExtension.lowercased()
        let titre = (nom as NSString).deletingPathExtension
        let feuilles: [(nom: String, lignes: [[String]])]
        if ext == "xlsx" {
            feuilles = try lireClasseur(donnees)
        } else {
            feuilles = [("", lireCSV(MarkdownLoader.decode(donnees), separateur: ext == "tsv" ? "\t" : nil))]
        }
        let pleines = feuilles.filter { !$0.lignes.isEmpty }
        guard !pleines.isEmpty else { throw Erreur.vide }
        var md = "# " + titre + "\n"
        var total = 0
        for f in pleines {
            if pleines.count > 1 || !f.nom.isEmpty { md += "\n## " + f.nom + "\n" }
            md += "\n" + tableau(f.lignes) + "\n"
            if f.lignes.count > lignesMax {
                md += "\n*" + tr("%d lignes de plus ne sont pas reprises.", f.lignes.count - lignesMax) + "*\n"
            }
            total += min(f.lignes.count, lignesMax)
        }
        let resume = pleines.count > 1
            ? tr("%d feuilles, %d lignes", pleines.count, total)
            : tr("%d lignes", total)
        return DocumentImporte(genre: .rapport, titre: titre, markdown: md, resume: resume)
    }

    // MARK: Le tableau Markdown

    /// La première ligne pour en-tête ; les colonnes vides à droite retirées ; `|` et retours à la
    /// ligne protégés.
    static func tableau(_ lignes: [[String]]) -> String {
        let gardees = Array(lignes.prefix(lignesMax + 1))
        let largeur = gardees.map { l in (l.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? -1) + 1 }.max() ?? 0
        guard largeur > 0 else { return "" }
        func cellule(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\r\n", with: "<br>")
                .replacingOccurrences(of: "\n", with: "<br>")
                .trimmingCharacters(in: .whitespaces)
        }
        func rangee(_ l: [String]) -> String {
            let c = (0..<largeur).map { $0 < l.count ? cellule(l[$0]) : "" }
            return "| " + c.joined(separator: " | ") + " |"
        }
        var sortie = [rangee(gardees[0]), "|" + String(repeating: " --- |", count: largeur)]
        sortie += gardees.dropFirst().map(rangee)
        return sortie.joined(separator: "\n")
    }

    // MARK: CSV

    /// Un CSV selon la RFC 4180 : guillemets, guillemets doublés, retours à la ligne dans une
    /// cellule. Le séparateur se devine sur la première ligne : `;` (Excel en français), `,` ou
    /// tabulation.
    static func lireCSV(_ texte: String, separateur impose: Character? = nil) -> [[String]] {
        var t = texte
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        let premiere = t.prefix { $0 != "\n" }
        let sep: Character = impose ?? [";", ",", "\t"].max { a, b in
            premiere.filter { $0 == a }.count < premiere.filter { $0 == b }.count
        } ?? ","
        var lignes: [[String]] = [], ligne: [String] = [], champ = ""
        var guillemets = false
        var i = t.startIndex
        while i < t.endIndex {
            let c = t[i]
            if guillemets {
                if c == "\"" {
                    let suivant = t.index(after: i)
                    if suivant < t.endIndex, t[suivant] == "\"" { champ.append("\""); i = suivant }
                    else { guillemets = false }
                } else {
                    champ.append(c)
                }
            } else if c == "\"" && champ.isEmpty {
                guillemets = true
            } else if c == sep {
                ligne.append(champ); champ = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                ligne.append(champ); champ = ""
                lignes.append(ligne); ligne = []
            } else {
                champ.append(c)
            }
            i = t.index(after: i)
        }
        if !champ.isEmpty || !ligne.isEmpty { ligne.append(champ); lignes.append(ligne) }
        // Les lignes entièrement vides (la dernière, souvent) ne comptent pas.
        return lignes.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    // MARK: Excel

    static func lireClasseur(_ donnees: Data) throws -> [(nom: String, lignes: [[String]])] {
        let zip = try LecteurZip(donnees)
        // Les textes partagés : la plupart des cellules de texte n'en portent que le numéro.
        var partages: [String] = []
        if let d = try zip.donnees("xl/sharedStrings.xml"), let x = NoeudXML.lire(d) {
            partages = x.enfants("si").map { si in si.descendants("t").map(\.texte).joined() }
        }
        // Les styles qui sont des dates : les cellules qui les portent sont des numéros de jour.
        var stylesDate = Set<Int>()
        if let d = try zip.donnees("xl/styles.xml"), let x = NoeudXML.lire(d) {
            var formatsDate = Set<Int>([14, 15, 16, 17, 22, 27, 30, 36, 45, 46, 47, 50, 57])
            for f in x.descendants("numFmt") {
                if let id = f["numFmtId"].flatMap(Int.init), let code = f["formatCode"]?.lowercased(),
                   code.contains("y") || (code.contains("d") && code.contains("m") && !code.contains("0")) {
                    formatsDate.insert(id)
                }
            }
            if let xfs = x.descendant("cellXfs") {
                for (n, xf) in xfs.enfants("xf").enumerated() where xf["numFmtId"].flatMap(Int.init).map(formatsDate.contains) == true {
                    stylesDate.insert(n)
                }
            }
        }
        // Les feuilles, dans l'ordre du classeur, et le fichier de chacune.
        var cibles: [String: String] = [:]
        if let d = try zip.donnees("xl/_rels/workbook.xml.rels"), let x = NoeudXML.lire(d) {
            for r in x.enfants("Relationship") {
                if let id = r["Id"], let cible = r["Target"] {
                    cibles[id] = cible.hasPrefix("/") ? String(cible.dropFirst()) : "xl/" + cible
                }
            }
        }
        guard let d = try zip.donnees("xl/workbook.xml"), let classeur = NoeudXML.lire(d) else { throw LecteurZip.Erreur.pasUnZip }
        var feuilles: [(String, [[String]])] = []
        for s in classeur.descendants("sheet") {
            guard let id = s["r:id"], let chemin = cibles[id], let fd = try zip.donnees(chemin),
                  let feuille = NoeudXML.lire(fd) else { continue }
            feuilles.append((s["name"] ?? "", lireFeuille(feuille, partages: partages, stylesDate: stylesDate)))
        }
        return feuilles
    }

    private static func lireFeuille(_ x: NoeudXML, partages: [String], stylesDate: Set<Int>) -> [[String]] {
        var lignes: [[String]] = []
        for row in x.descendants("row") {
            var ligne: [String] = []
            for c in row.enfants("c") {
                // La colonne de la cellule (« C7 » → 2) : les cellules vides ne sont pas écrites.
                if let ref = c["r"] {
                    let col = colonne(ref)
                    while ligne.count < col { ligne.append("") }
                }
                ligne.append(valeur(c, partages: partages, stylesDate: stylesDate))
            }
            // Les lignes vides sautées par Excel (« r » de la ligne) : on les rend, jusqu'à 50.
            if let r = row["r"].flatMap(Int.init), r - 1 > lignes.count, r - 1 - lignes.count <= 50 {
                while lignes.count < r - 1 { lignes.append([]) }
            }
            lignes.append(ligne)
        }
        return lignes.filter { $0.contains { !$0.isEmpty } }
    }

    private static func colonne(_ ref: String) -> Int {
        var n = 0
        for ch in ref.uppercased().unicodeScalars {
            guard ch.value >= 65, ch.value <= 90 else { break }
            n = n * 26 + Int(ch.value - 64)
        }
        return max(n - 1, 0)
    }

    private static func valeur(_ c: NoeudXML, partages: [String], stylesDate: Set<Int>) -> String {
        let v = c.enfant("v")?.texte ?? ""
        switch c["t"] {
        case "s": return Int(v).flatMap { $0 < partages.count ? partages[$0] : nil } ?? ""
        case "inlineStr": return c.descendants("t").map(\.texte).joined()
        case "b": return v == "1" ? "✓" : ""
        case "str", "e": return v
        default:
            if let s = c["s"].flatMap(Int.init), stylesDate.contains(s), let jours = Double(v) {
                return date(jours)
            }
            return v
        }
    }

    /// Un numéro de jour d'Excel (1900, avec son 29 février 1900 fictif) en AAAA-MM-JJ.
    private static func date(_ jours: Double) -> String {
        let base = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                                  year: 1899, month: 12, day: 30).date!
        let d = base.addingTimeInterval(jours * 86_400)
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = jours.truncatingRemainder(dividingBy: 1) == 0 ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}
