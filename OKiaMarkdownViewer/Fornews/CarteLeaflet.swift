// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsServices/Flux/CarteLeaflet.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **La carte des lieux d'un document Markdown** — bloc `leaflet`, lu par md Viewer et par le
/// plugin Obsidian du même nom.
///
/// ## Pourquoi ce fichier existe
///
/// Comme `ImageMarkdown` : la règle vivait dans `RapportObsidian` (`FornewsFeatures`), hors de
/// portée du générateur de dossiers qui vit plus bas dans la pile. Plutôt qu'un second émetteur
/// — qui aurait divergé au premier correctif de zoom ou d'échappement CSV — elle descend d'un
/// étage, et `RapportObsidian` s'y branche.
///
/// ⚠️ **Sans le plugin, le bloc s'affiche simplement en code.** Le document reste lisible : c'est
/// la condition pour qu'on puisse en poser un sans rien casser chez un lecteur qui ne l'a pas.
public enum CarteLeaflet {

    public struct Point: Sendable, Equatable {
        public let nom: String, type: TypeEntite, lat: Double, lon: Double
        public init(nom: String, type: TypeEntite, lat: Double, lon: Double) {
            self.nom = nom; self.type = type; self.lat = lat; self.lon = lon
        }
    }

    /// Une carte n'a de sens qu'à partir de **deux** lieux : un marqueur unique ne dit rien que le
    /// titre du dossier ne dise déjà. Seuil hérité du rapport d'histoire, conservé tel quel.
    public static let minimumPoints = 2

    /// **Les points réellement portés sur la carte** : nom non vide, coordonnées dans les bornes,
    /// dédoublonnés par nom.
    ///
    /// ⚠️ Public parce que le SEUIL doit se compter là-dessus, pas sur la liste brute. Cinq
    /// articles citant « Berne » donnaient cinq points, donc une carte — avec un seul marqueur, et
    /// une étendue nulle. Le seuil ne veut pas dire « deux mentions » mais « deux LIEUX ».
    public static func retenus(_ points: [Point]) -> [Point] {
        var vus = Set<String>(); var pts: [Point] = []
        for p in points {
            let cle = p.nom.lowercased()
            guard !cle.isEmpty, abs(p.lat) <= 90, abs(p.lon) <= 180,
                  vus.insert(cle).inserted else { continue }
            pts.append(p)
        }
        return pts
    }

    /// Échappement des libellés dans un lien `[[…]]`.
    static func nettoyerLien(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "|", with: "·").replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    public static func bloc(_ points: [Point]) -> String? {
        let pts = retenus(points)
        guard !pts.isEmpty else { return nil }

        let lat = pts.map(\.lat), lon = pts.map(\.lon)
        let centreLat = lat.reduce(0, +) / Double(pts.count)
        let centreLon = lon.reduce(0, +) / Double(pts.count)
        let etendue = Swift.max(lat.max()! - lat.min()!, lon.max()! - lon.min()!)
        func f(_ d: Double) -> String { String(format: "%.5f", d) }

        var l = ["```leaflet",
                 "id: fornews-carte",
                 "height: 400px",
                 "lat: \(f(centreLat))",
                 "long: \(f(centreLon))",
                 "defaultZoom: \(zoomPourEtendue(etendue, unPoint: pts.count == 1))",
                 "minZoom: 1", "maxZoom: 18"]
        for p in pts {
            // ⚠️ Le plugin lit « marker: type,lat,long,link » (CSV) → la virgule doit disparaître
            // du libellé. Mais la remplacer par une espace laissait « Washington  D.C. » avec deux
            // espaces : on réduit les répétitions, sinon on corrige un défaut en en posant un autre.
            let nom = p.nom.replacingOccurrences(of: ",", with: " ")
                .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            l.append("marker: default,\(f(p.lat)),\(f(p.lon)),[[\(nettoyerLien(nom))]]")
        }
        l.append("```")
        return l.joined(separator: "\n")
    }

    /// Niveau de zoom Leaflet selon l'étendue (degrés) des points ; un point isolé → zoom rapproché.
    static func zoomPourEtendue(_ span: Double, unPoint: Bool) -> Int {
        if unPoint { return 8 }
        switch span {
        case 120...:    return 1
        case 60..<120:  return 2
        case 30..<60:   return 3
        case 15..<30:   return 4
        case 7..<15:    return 5
        case 3..<7:     return 6
        case 1..<3:     return 7
        default:        return 8
        }
    }

}
