import Foundation

/// Une tranche de la liste d'accueil : un intitulé et les éléments qui tombent dedans.
struct GroupeDate<Element: Identifiable>: Identifiable {
    let titre: String
    let elements: [Element]
    var id: String { titre }
}

/// Découpe une liste datée en tranches lisibles — aujourd'hui, hier, les sept puis les
/// trente derniers jours, ensuite un groupe par mois. Les deux listes de l'écran d'accueil
/// (les récents et le coffre) partagent ce découpage : un même document doit apparaître
/// sous le même intitulé, d'une liste à l'autre.
enum DecoupageParDate {

    /// Découpe une liste **déjà triée du plus récent au plus ancien**. L'ordre des tranches
    /// suit celui des éléments, sans tri supplémentaire : c'est l'appelant qui décide de
    /// l'ordre, et le découpage n'en invente pas un autre.
    static func grouper<E>(_ elements: [E],
                           date: (E) -> Date,
                           maintenant: Date = Date()) -> [GroupeDate<E>] {
        var ordre: [Tranche] = []
        var paquets: [Tranche: [E]] = [:]
        for element in elements {
            let tranche = Tranche(date: date(element), maintenant: maintenant)
            if paquets[tranche] == nil { ordre.append(tranche) }
            paquets[tranche, default: []].append(element)
        }
        return ordre.map { GroupeDate(titre: $0.titre, elements: paquets[$0] ?? []) }
    }

    /// La mention portée par chaque ligne, sous le nom du fichier. Elle complète l'intitulé
    /// de la tranche au lieu de le répéter : l'heure quand le jour est déjà connu, la date
    /// courte sinon.
    static func mention(pour date: Date, maintenant: Date = Date()) -> String {
        let calendrier = Calendar.current
        let locale = Localization.shared.locale
        if calendrier.isDateInToday(date) || calendrier.isDateInYesterday(date) {
            return date.formatted(.dateTime.locale(locale).hour().minute())
        }
        if calendrier.component(.year, from: date) == calendrier.component(.year, from: maintenant) {
            return date.formatted(.dateTime.locale(locale).day().month(.abbreviated))
        }
        return date.formatted(.dateTime.locale(locale).day().month(.abbreviated).year())
    }

    // MARK: - Tranches

    private enum Tranche: Hashable {
        case aujourdhui
        case hier
        case septJours
        case trenteJours
        case mois(annee: Int, mois: Int)

        init(date: Date, maintenant: Date) {
            let calendrier = Calendar.current
            if calendrier.isDateInToday(date) { self = .aujourdhui; return }
            if calendrier.isDateInYesterday(date) { self = .hier; return }
            let jours = calendrier.dateComponents([.day],
                                                  from: calendrier.startOfDay(for: date),
                                                  to: calendrier.startOfDay(for: maintenant)).day ?? 0
            // Une date à venir (horloge décalée, fichier daté du futur) reste avec le jour même.
            if jours <= 0 { self = .aujourdhui; return }
            if jours <= 7 { self = .septJours; return }
            if jours <= 30 { self = .trenteJours; return }
            self = .mois(annee: calendrier.component(.year, from: date),
                         mois: calendrier.component(.month, from: date))
        }

        var titre: String {
            switch self {
            case .aujourdhui:  return tr("Aujourd'hui")
            case .hier:        return tr("Hier")
            case .septJours:   return tr("7 derniers jours")
            case .trenteJours: return tr("30 derniers jours")
            case .mois(let annee, let mois):
                var composantes = DateComponents()
                composantes.year = annee
                composantes.month = mois
                composantes.day = 1
                guard let date = Calendar.current.date(from: composantes) else { return "" }
                // Le mois s'écrit en minuscule en français comme en espagnol ; en tête d'un
                // intitulé, il prend la majuscule que la langue lui donnerait.
                let texte = date.formatted(.dateTime.locale(Localization.shared.locale)
                                                    .month(.wide).year())
                return texte.prefix(1).localizedUppercase + texte.dropFirst()
            }
        }
    }
}
