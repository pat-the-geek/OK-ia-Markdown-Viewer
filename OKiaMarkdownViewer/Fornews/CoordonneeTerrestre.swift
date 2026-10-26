// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsServices/Carte/CoordonneeTerrestre.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Une coordonnée est-elle posable sur la carte de la Terre ?**
///
/// ⛔ La question n'est pas rhétorique : le corpus contenait « Olya », un `gpe` à
/// **longitude 291,8** (mesuré le 12/09/2026 sur le store du Mac mini). Aucune longitude terrestre
/// ne dépasse 180 — mais Wikidata publie aussi des coordonnées **planétaires**, et les cratères de
/// Mars ou de Vénus se repèrent par convention sur 0–360° est. La revendication P625 porte alors un
/// champ `globe` qui n'est pas la Terre, que l'ancien lecteur ignorait.
///
/// Ce que MapKit en fait, mesuré : `CLLocationCoordinate2DIsValid` rend `false`, et
/// `MKMapPoint(coordonnée)` rend **(-1, -1)** — un point hors du monde, sans erreur ni exception.
/// Un seul lieu de ce genre suffit donc à entraîner le cadrage de la carte entière hors du monde,
/// puisque le rectangle d'ensemble est l'union de tous les points.
public enum CoordonneeTerrestre {

    /// Identifiant Wikidata de la Terre. Une coordonnée sur un autre globe n'a rien à faire ici.
    public static let globeTerre = "Q2"

    /// Vrai si le couple se pose sur la Terre : fini, et dans les bornes.
    ///
    /// ⚠️ On ne RAMÈNE PAS 291,8 à −68,2 par un modulo. Ce serait deviner : si la valeur vient d'un
    /// autre globe, le point « corrigé » désignerait un endroit bien réel de la Terre où il ne s'est
    /// rien passé. Une épingle absente se voit ; une épingle fausse se croit.
    public static func estValide(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
    }

    /// Vrai si l'URI de globe d'une revendication P625 désigne la Terre.
    ///
    /// Wikidata rend `globe` sous la forme `http://www.wikidata.org/entity/Q2`. Une revendication
    /// SANS globe est traitée comme terrestre : c'est la valeur par défaut de la propriété, et la
    /// refuser priverait la carte de lieux parfaitement justes.
    public static func globeEstLaTerre(_ uri: String?) -> Bool {
        guard let uri, !uri.isEmpty else { return true }
        return uri.hasSuffix("/" + globeTerre)
    }
}
