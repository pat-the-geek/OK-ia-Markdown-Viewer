import Foundation

/// Option Analytic (1.7) — le texte d'un document Pages, lu dans ses fichiers `Index/*.iwa`.
///
/// Un `.iwa` est une suite de blocs compressés en Snappy (sans somme de contrôle), chacun précédé
/// d'un octet nul et de sa taille sur trois octets. Décompressés, ils donnent des messages protobuf :
/// une en-tête `ArchiveInfo` (le type et la taille de chaque message), puis les messages. Le texte
/// vit dans `TSWP.StorageArchive` (types 2001 et 2005), champ 3, avec son genre au champ 1 (0 le
/// corps, 3 une zone de texte, 4 une note). Rien d'autre n'est lu : ni la mise en forme, ni l'ordre
/// des diapositives d'un Keynote.
enum LecteurIWA {
    struct Texte {
        let genre: Int
        let texte: String
    }

    /// Les textes de tous les fichiers donnés, dans l'ordre.
    static func textes(_ fichiers: [Data]) -> [Texte] {
        fichiers.flatMap { messages(decompresser($0)) }
    }

    // MARK: Snappy

    static func decompresser(_ iwa: Data) -> Data {
        let o = [UInt8](iwa)
        var sortie = Data()
        var i = 0
        while i + 4 <= o.count {
            let taille = Int(o[i + 1]) | Int(o[i + 2]) << 8 | Int(o[i + 3]) << 16
            let debut = i + 4, fin = min(debut + taille, o.count)
            if o[i] == 0 { sortie.append(snappy(Array(o[debut..<fin]))) }
            i = fin
        }
        return sortie
    }

    private static func snappy(_ e: [UInt8]) -> Data {
        var p = 0
        // La taille décompressée, en varint : on la saute.
        while p < e.count, e[p] & 0x80 != 0 { p += 1 }
        p += 1
        var s = [UInt8]()
        s.reserveCapacity(e.count * 3)
        while p < e.count {
            let tag = e[p]; p += 1
            switch tag & 3 {
            case 0:
                var n = Int(tag >> 2)
                if n >= 60 {
                    let octets = n - 59
                    guard p + octets <= e.count else { return Data(s) }
                    n = 0
                    for k in 0..<octets { n |= Int(e[p + k]) << (8 * k) }
                    p += octets
                }
                n += 1
                guard p + n <= e.count else { return Data(s) }
                s.append(contentsOf: e[p..<(p + n)])
                p += n
            case 1:
                guard p < e.count else { return Data(s) }
                let n = 4 + Int((tag >> 2) & 7)
                let decalage = Int(tag >> 5) << 8 | Int(e[p]); p += 1
                copier(&s, decalage, n)
            case 2:
                guard p + 2 <= e.count else { return Data(s) }
                let n = Int(tag >> 2) + 1
                let decalage = Int(e[p]) | Int(e[p + 1]) << 8; p += 2
                copier(&s, decalage, n)
            default:
                guard p + 4 <= e.count else { return Data(s) }
                let n = Int(tag >> 2) + 1
                let decalage = Int(e[p]) | Int(e[p + 1]) << 8 | Int(e[p + 2]) << 16 | Int(e[p + 3]) << 24; p += 4
                copier(&s, decalage, n)
            }
        }
        return Data(s)
    }

    /// Une copie qui peut chevaucher ce qu'elle écrit : octet par octet.
    private static func copier(_ s: inout [UInt8], _ decalage: Int, _ n: Int) {
        guard decalage > 0, decalage <= s.count else { return }
        let depart = s.count - decalage
        for k in 0..<n { s.append(s[depart + k]) }
    }

    // MARK: Protobuf

    private struct Lecteur {
        let o: [UInt8]
        var p = 0
        var fini: Bool { p >= o.count }
        mutating func varint() -> UInt64? {
            var r: UInt64 = 0, decal: UInt64 = 0
            while p < o.count {
                let b = o[p]; p += 1
                r |= UInt64(b & 0x7f) << decal
                if b & 0x80 == 0 { return r }
                decal += 7
                if decal > 63 { return nil }
            }
            return nil
        }
        /// Un champ : son numéro, son type, et pour un champ de longueur, ses octets.
        mutating func champ() -> (numero: Int, type: Int, valeur: UInt64, octets: ArraySlice<UInt8>)? {
            guard let cle = varint() else { return nil }
            let numero = Int(cle >> 3), type = Int(cle & 7)
            switch type {
            case 0: guard let v = varint() else { return nil }; return (numero, 0, v, [])
            case 1: guard p + 8 <= o.count else { return nil }; p += 8; return (numero, 1, 0, [])
            case 2:
                guard let n = varint(), p + Int(n) <= o.count else { return nil }
                let s = o[p..<(p + Int(n))]; p += Int(n)
                return (numero, 2, 0, s)
            case 5: guard p + 4 <= o.count else { return nil }; p += 4; return (numero, 5, 0, [])
            default: return nil
            }
        }
    }

    private static func messages(_ d: Data) -> [Texte] {
        var l = Lecteur(o: [UInt8](d))
        var textes: [Texte] = []
        while !l.fini {
            guard let n = l.varint(), l.p + Int(n) <= l.o.count else { break }
            var info = Lecteur(o: Array(l.o[l.p..<(l.p + Int(n))]))
            l.p += Int(n)
            // Les messages de l'archive : (type, taille), dans l'ordre.
            var suite: [(Int, Int)] = []
            while let c = info.champ() {
                guard c.numero == 2, c.type == 2 else { continue }
                var m = Lecteur(o: Array(c.octets))
                var type = 0, taille = 0
                while let f = m.champ() {
                    if f.numero == 1, f.type == 0 { type = Int(f.valeur) }
                    if f.numero == 3, f.type == 0 { taille = Int(f.valeur) }
                }
                suite.append((type, taille))
            }
            for (type, taille) in suite {
                guard l.p + taille <= l.o.count else { return textes }
                if type == 2001 || type == 2005, let t = stockage(Array(l.o[l.p..<(l.p + taille)])) { textes.append(t) }
                l.p += taille
            }
        }
        return textes
    }

    /// `TSWP.StorageArchive` : le genre (champ 1) et le texte (champ 3).
    private static func stockage(_ o: [UInt8]) -> Texte? {
        var l = Lecteur(o: o)
        var genre = 0, morceaux: [String] = []
        while let c = l.champ() {
            if c.numero == 1, c.type == 0 { genre = Int(c.valeur) }
            if c.numero == 3, c.type == 2 { morceaux.append(String(decoding: c.octets, as: UTF8.self)) }
        }
        let texte = morceaux.joined()
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            // Le retour chariot sépare les paragraphes ; la tabulation verticale, les lignes.
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{000B}", with: "\n")
            .unicodeScalars.filter { $0 == "\n" || $0 == "\t" || $0.value >= 0x20 && $0.value != 0xFFFC }
        let propre = String(String.UnicodeScalarView(texte)).trimmingCharacters(in: .whitespacesAndNewlines)
        return propre.isEmpty ? nil : Texte(genre: genre, texte: propre)
    }
}
