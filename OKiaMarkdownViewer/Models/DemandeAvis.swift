import Foundation

/// 1.4 — la demande de note (StoreKit `requestReview`). Le classement de l'App Store tient compte
/// des notes ; md Viewer ne la demande qu'à quelqu'un qui s'en sert vraiment : cinq documents
/// ouverts, sur trois jours différents au moins. Après une demande, tout repart de zéro et rien
/// n'est redemandé dans la même version. Le système décide ensuite s'il affiche la fenêtre (trois
/// fois par an au plus) ; TestFlight ne l'affiche jamais.
///
/// 1.5.1 (27/11/2026) — au moment opportun : la demande ne tombe plus à l'ouverture d'un document,
/// en pleine lecture, mais juste après une réussite (`succes()`) : un diaporama mené jusqu'à sa
/// dernière diapositive, un export enregistré ou partagé. La fenêtre vient une fois la feuille ou
/// le diaporama refermé (`momentVenu()`), jamais par-dessus. Une réussite qui ne tombe pas au
/// bon moment (trop tôt, déjà demandé) est oubliée : elle ne ressort pas plus tard, hors de propos.
enum DemandeAvis {
    static let documentsMinimum = 5
    static let joursMinimum = 3
    /// Remplaçable pour le banc d'essai.
    static var reglages = UserDefaults.standard

    private static let cleDocuments = "avis.documents"
    private static let cleJours = "avis.jours"
    private static let cleVersion = "avis.version"

    /// Une réussite vient d'avoir lieu ; la demande attend que la feuille ou le diaporama se referme.
    @MainActor private(set) static var succesEnAttente = false

    @MainActor static func succes() { succesEnAttente = true }

    /// Vrai si une réussite attend et que md Viewer sert vraiment (assez de documents, assez de
    /// jours, pas déjà demandé dans cette version). La réussite est consommée dans tous les cas.
    @MainActor static func momentVenu(version: String = versionCourante) -> Bool {
        guard succesEnAttente else { return false }
        succesEnAttente = false
        let documents = reglages.integer(forKey: cleDocuments)
        let jours = reglages.stringArray(forKey: cleJours) ?? []
        return documents >= documentsMinimum && jours.count >= joursMinimum
            && reglages.string(forKey: cleVersion) != version
    }

    /// Compte un document ouvert ; vrai si md Viewer sert assez pour demander une note. Depuis la
    /// 1.5.1, la demande elle-même attend une réussite (`momentVenu()`).
    @discardableResult
    static func documentOuvert(le date: Date = .now, version: String = versionCourante) -> Bool {
        let documents = reglages.integer(forKey: cleDocuments) + 1
        reglages.set(documents, forKey: cleDocuments)
        var jours = Set(reglages.stringArray(forKey: cleJours) ?? [])
        if jours.count < joursMinimum {
            jours.insert(jour(date))
            reglages.set(jours.sorted(), forKey: cleJours)
        }
        guard documents >= documentsMinimum, jours.count >= joursMinimum,
              reglages.string(forKey: cleVersion) != version else { return false }
        return true
    }

    /// La note vient d'être demandée : plus rien dans cette version, et les compteurs repartent.
    @MainActor static func noteDemandee(version: String = versionCourante) {
        succesEnAttente = false
        reglages.set(version, forKey: cleVersion)
        reglages.set(0, forKey: cleDocuments)
        reglages.set([String](), forKey: cleJours)
    }

    static var versionCourante: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private static func jour(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
