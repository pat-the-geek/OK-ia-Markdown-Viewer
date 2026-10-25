import Foundation
import Compression

/// Option Analytic (1.4) — lire une archive zip : un `.docx` ou un `.pptx` n'est rien d'autre
/// qu'un zip de XML et d'images. iOS et Mac Catalyst n'ont pas de lecteur zip public ; celui-ci lit
/// le répertoire central et décompresse les entrées stockées (0) ou « deflate » (8) avec le
/// framework Compression d'Apple (`COMPRESSION_ZLIB` est le deflate brut de la RFC 1951). C'est le
/// pendant de `OOXMLZip`, qui écrit les exports Word et PowerPoint.
struct LecteurZip {
    enum Erreur: Error, LocalizedError {
        case pasUnZip
        case methodeInconnue(UInt16)
        case entreeAbimee(String)

        var errorDescription: String? {
            switch self {
            case .pasUnZip: return tr("Ce fichier n’est pas un document Office lisible.")
            case .methodeInconnue: return tr("Ce document utilise une compression inconnue.")
            case .entreeAbimee(let nom): return tr("Une partie du document est abîmée : %@", nom)
            }
        }
    }

    private struct Entree {
        let methode: UInt16
        let tailleCompressee: Int
        let taille: Int
        let decalageEntete: Int
    }

    private let archive: Data
    private var entrees: [String: Entree] = [:]

    /// Les noms des entrées, dans l'ordre de l'archive.
    private(set) var noms: [String] = []

    init(_ donnees: Data) throws {
        self.archive = donnees
        // La fin du répertoire central (0x06054b50), cherchée depuis la fin : un commentaire de
        // 65 535 octets au plus peut la suivre.
        let fin = archive.count
        guard fin >= 22 else { throw Erreur.pasUnZip }
        var eocd = -1
        var i = fin - 22
        let plancher = max(0, fin - 22 - 65_535)
        while i >= plancher {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Erreur.pasUnZip }
        let nombre = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        for _ in 0..<nombre {
            guard p + 46 <= fin, u32(p) == 0x0201_4b50 else { throw Erreur.pasUnZip }
            let methode = u16(p + 10)
            let tailleC = Int(u32(p + 20)), taille = Int(u32(p + 24))
            let lNom = Int(u16(p + 28)), lExtra = Int(u16(p + 30)), lComm = Int(u16(p + 32))
            let decalage = Int(u32(p + 42))
            let nom = String(decoding: archive[(archive.startIndex + p + 46)..<(archive.startIndex + p + 46 + lNom)], as: UTF8.self)
            entrees[nom] = Entree(methode: methode, tailleCompressee: tailleC, taille: taille, decalageEntete: decalage)
            noms.append(nom)
            p += 46 + lNom + lExtra + lComm
        }
    }

    func contient(_ nom: String) -> Bool { entrees[nom] != nil }

    /// Le contenu d'une entrée, décompressé ; nil si elle n'existe pas.
    func donnees(_ nom: String) throws -> Data? {
        guard let e = entrees[nom] else { return nil }
        // L'en-tête local peut porter un champ « extra » différent de celui du répertoire central.
        let h = e.decalageEntete
        guard h + 30 <= archive.count, u32(h) == 0x0403_4b50 else { throw Erreur.entreeAbimee(nom) }
        let debut = h + 30 + Int(u16(h + 26)) + Int(u16(h + 28))
        guard debut + e.tailleCompressee <= archive.count else { throw Erreur.entreeAbimee(nom) }
        let brut = archive[(archive.startIndex + debut)..<(archive.startIndex + debut + e.tailleCompressee)]
        switch e.methode {
        case 0:
            return Data(brut)
        case 8:
            return try decompresser(Data(brut), taille: e.taille, nom: nom)
        default:
            throw Erreur.methodeInconnue(e.methode)
        }
    }

    /// Le texte d'une entrée XML, en UTF-8.
    func texte(_ nom: String) throws -> String? {
        try donnees(nom).map { String(decoding: $0, as: UTF8.self) }
    }

    private func decompresser(_ entree: Data, taille: Int, nom: String) throws -> Data {
        guard taille > 0 else { return Data() }
        var sortie = Data(count: taille)
        let ecrits = sortie.withUnsafeMutableBytes { (s: UnsafeMutableRawBufferPointer) -> Int in
            entree.withUnsafeBytes { (e: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(s.bindMemory(to: UInt8.self).baseAddress!, taille,
                                          e.bindMemory(to: UInt8.self).baseAddress!, entree.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard ecrits == taille else { throw Erreur.entreeAbimee(nom) }
        return sortie
    }

    private func u16(_ i: Int) -> UInt16 {
        UInt16(archive[archive.startIndex + i]) | UInt16(archive[archive.startIndex + i + 1]) << 8
    }

    private func u32(_ i: Int) -> UInt32 {
        UInt32(u16(i)) | UInt32(u16(i + 2)) << 16
    }
}
