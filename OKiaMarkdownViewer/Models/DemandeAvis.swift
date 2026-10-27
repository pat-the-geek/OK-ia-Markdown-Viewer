import Foundation

/// 1.4 — la demande de note (StoreKit `requestReview`). Le classement de l'App Store tient compte
/// des notes ; md Viewer ne la demande qu'à quelqu'un qui s'en sert vraiment : cinq documents
/// ouverts, sur trois jours différents au moins. Après une demande, tout repart de zéro et rien
/// n'est redemandé dans la même version. Le système décide ensuite s'il affiche la fenêtre (trois
/// fois par an au plus) ; TestFlight ne l'affiche jamais.
enum DemandeAvis {
    static let documentsMinimum = 5
    static let joursMinimum = 3
    /// Remplaçable pour le banc d'essai.
    static var reglages = UserDefaults.standard

    private static let cleDocuments = "avis.documents"
    private static let cleJours = "avis.jours"
    private static let cleVersion = "avis.version"

    /// Compte un document ouvert ; vrai si c'est le moment de demander une note. Rien n'est
    /// consommé ici : si le moment ne s'y prête pas (une feuille ouverte), le document suivant
    /// redemandera.
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
    static func noteDemandee(version: String = versionCourante) {
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
