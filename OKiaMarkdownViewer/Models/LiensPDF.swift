import Foundation
import PDFKit

/// Les liens cliquables du PDF exporté (1.5.1 ; demandé par Patrick le 19/11/2026, par la session
/// fornews : « liens cliquables »).
///
/// Le moteur d'impression d'iOS (`UIPrintPageRenderer`) dessine le texte des liens mais perd leurs
/// adresses. On les repose après coup : chaque lien du document (son texte, son adresse, dans
/// l'ordre) est retrouvé dans le PDF, et une annotation de lien couvre chacune de ses lignes.
///
/// Un lien coupé sur deux lignes ne se trouve pas d'un bloc (PDFKit ne cherche pas à travers un
/// retour à la ligne) : on prend le plus long début qui se trouve, puis on cherche la suite juste
/// en dessous, sur la même page ou en haut de la suivante. Un texte présent plusieurs fois (deux
/// liens « source ») est attribué dans l'ordre : la n-ième fois au n-ième lien.
enum LiensPDF {
    struct Lien: Equatable {
        var texte: String
        var adresse: String
    }

    /// Pose les liens dans `doc` ; rend le nombre d'annotations posées.
    @discardableResult
    static func poser(_ liens: [Lien], dans doc: PDFDocument) -> Int {
        var dejaPris: [String: Int] = [:]     // texte cherché → occurrences déjà attribuées
        var posees = 0
        for lien in liens {
            guard let url = URL(string: lien.adresse) else { continue }
            let mots = lien.texte.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !mots.isEmpty, lien.texte.count >= 2 else { continue }
            var lignes: [(PDFPage, CGRect)] = []
            var reste = mots[...]
            var precedent: (page: PDFPage, rect: CGRect)?
            while !reste.isEmpty {
                guard let (prises, trouve) = plusLongDebut(reste, dans: doc, apres: precedent, dejaPris: &dejaPris)
                else { break }
                lignes += trouve
                if let derniere = trouve.last { precedent = (derniere.0, derniere.1) }
                reste = reste.dropFirst(prises)
            }
            for (page, rect) in lignes {
                let a = PDFAnnotation(bounds: rect, forType: .link, withProperties: nil)
                a.url = url
                // Sans cadre : le texte souligné suffit à dire que c'est un lien.
                let bord = PDFBorder()
                bord.lineWidth = 0
                a.border = bord
                page.addAnnotation(a)
                posees += 1
            }
        }
        return posees
    }

    /// Le plus long début de `mots` qu'on trouve : la première fois (au-delà des occurrences déjà
    /// prises) pour un début de lien, ou juste sous `apres` pour sa suite.
    private static func plusLongDebut(_ mots: ArraySlice<String>, dans doc: PDFDocument,
                                      apres: (page: PDFPage, rect: CGRect)?,
                                      dejaPris: inout [String: Int]) -> (Int, [(PDFPage, CGRect)])? {
        // Un début trop court (« le ») se trouverait n'importe où : deux mots au moins, sauf pour
        // un lien d'un seul mot, ou pour la suite d'une ligne déjà trouvée.
        let minimum = apres == nil ? min(2, mots.count) : 1
        // Le plus long début présent dans le document, par dichotomie (un début présent l'est
        // aussi, raccourci) : un long rapport a des centaines de liens.
        var bas = minimum - 1, haut = mots.count
        while bas < haut {
            let m = (bas + haut + 1) / 2
            if doc.findString(mots.prefix(m).joined(separator: " "), withOptions: []).isEmpty { haut = m - 1 } else { bas = m }
        }
        var n = bas
        while n >= minimum {
            let q = mots.prefix(n).joined(separator: " ")
            let trouves = doc.findString(q, withOptions: [])
            if let apres {
                if let s = trouves.first(where: { suite($0, de: apres, doc: doc) }) {
                    return (n, lignes(s))
                }
            } else {
                // Deux titres qui commencent pareil (« Nicole Kidman et Sandra Bullock se… »,
                // « Nicole Kidman et Sandra Bullock : leur film… ») : le plus long début trouvé
                // peut appartenir à l'AUTRE lien. On ne retient une occurrence que si le mot
                // suivant du lien se trouve juste en dessous ; sinon, un début plus court.
                let k = dejaPris[q, default: 0]
                if k < trouves.count {
                    let l = lignes(trouves[k])
                    if n == mots.count || suiteExiste(mots[mots.startIndex + n], apres: trouves[k], derniere: l.last, doc: doc) {
                        dejaPris[q] = k + 1
                        return (n, l)
                    }
                }
            }
            n -= 1
        }
        return nil
    }

    /// Le mot qui suit `apres` dans le texte du PDF est-il `mot`, en tête de la ligne suivante ?
    /// (La prochaine occurrence seulement : un mot courant, « de », se trouve des centaines de fois.)
    private static func suiteExiste(_ mot: String, apres: PDFSelection, derniere: (PDFPage, CGRect)?,
                                    doc: PDFDocument) -> Bool {
        guard let derniere, let s = doc.findString(mot, fromSelection: apres, withOptions: []) else { return false }
        return suite(s, de: (derniere.0, derniere.1), doc: doc)
    }

    private static func lignes(_ s: PDFSelection) -> [(PDFPage, CGRect)] {
        s.selectionsByLine().compactMap { l in
            guard let p = l.pages.first else { return nil }
            return (p, l.bounds(for: p))
        }
    }

    /// La sélection est-elle la ligne suivante de `de` : juste en dessous sur la même page, ou en
    /// haut de la page suivante ?
    private static func suite(_ s: PDFSelection, de: (page: PDFPage, rect: CGRect), doc: PDFDocument) -> Bool {
        guard let l = s.selectionsByLine().first, let p = l.pages.first else { return false }
        let r = l.bounds(for: p)
        if p == de.page {
            let ecart = de.rect.minY - r.maxY            // y PDF : vers le haut
            return ecart > -2 && ecart < max(de.rect.height, 12) * 1.2
        }
        let haut = p.bounds(for: .mediaBox).height
        return doc.index(for: p) == doc.index(for: de.page) + 1 && r.maxY > haut - 120
    }
}
