import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// L'emplacement du coffre, partagé entre les appareils de l'utilisateur par iCloud (1.5 ; Patrick,
/// 12/11/2026 : « est-ce qu'on peut partager l'emplacement du coffre entre les appareils par
/// icloud ? », puis « on laisse ainsi le choix : mettre le coffre dans icloud ou mettre le coffre
/// dans un partage réseau »).
///
/// Le dossier lui-même ne voyage pas : iOS et macOS n'ouvrent un dossier choisi qu'à l'appareil qui
/// l'a choisi. Ce qui voyage, par le stockage clé-valeur d'iCloud, c'est où il est :
/// - **dans iCloud Drive** (le dossier « Coffre » de md Viewer) : chaque appareil le trouve chez lui,
///   sans rien choisir — un appareil sans coffre le prend aussitôt ;
/// - **un dossier choisi** (un partage réseau, un disque) : les autres appareils le disent, avec son
///   nom et son chemin, et proposent de le choisir.
@MainActor
final class CoffrePartage: ObservableObject {
    static let partage = CoffrePartage()

    struct Emplacement: Equatable {
        enum Genre: String { case icloud, dossier }
        let genre: Genre
        let nom: String
        /// Le chemin, lisible (« Pat2TB › Rapports-de-veille »).
        let lieu: String
        /// L'appareil qui l'a choisi (« iPhone », « iPad », « Mac »).
        let appareil: String
        let id: String
        let date: Date
    }

    /// Le coffre choisi sur un AUTRE appareil (nil s'il a été choisi ici, ou jamais).
    @Published private(set) var ailleurs: Emplacement?

    private let cle = "okia.coffre.emplacement"
    private let cleIgnore = "okia.coffre.suggestionIgnoree"
    private let store = NSUbiquitousKeyValueStore.default

    /// Cet appareil, pour ne pas se suggérer son propre coffre.
    static let idAppareil: String = {
        let k = "okia.appareil.id"
        if let id = UserDefaults.standard.string(forKey: k) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: k)
        return id
    }()

    static var nomAppareil: String {
        #if targetEnvironment(macCatalyst)
        return "Mac"
        #else
        return UIDevice.current.model
        #endif
    }

    private init() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lire() }
        }
        store.synchronize()
        lire()
        #if DEBUG
        // OKIA_SUGGESTION=dossier|icloud : le coffre d'un autre appareil, pour voir la suggestion.
        if let g = ProcessInfo.processInfo.environment["OKIA_SUGGESTION"].flatMap(Emplacement.Genre.init(rawValue:)) {
            ailleurs = Emplacement(genre: g, nom: "Rapports-de-veille", lieu: "Pat2TB › Rapports-de-veille",
                                   appareil: "iPhone", id: "essai", date: Date())
        }
        #endif
    }

    private func lire() {
        guard let d = store.dictionary(forKey: cle),
              let genre = (d["genre"] as? String).flatMap(Emplacement.Genre.init(rawValue:)),
              let nom = d["nom"] as? String, let id = d["id"] as? String, id != Self.idAppareil else {
            ailleurs = nil
            return
        }
        let e = Emplacement(genre: genre, nom: nom, lieu: d["lieu"] as? String ?? nom,
                            appareil: d["appareil"] as? String ?? "", id: id,
                            date: d["date"] as? Date ?? .distantPast)
        ailleurs = e
        // Le coffre est dans iCloud Drive : un appareil qui n'en a pas encore le prend aussitôt.
        if e.genre == .icloud, !VaultStore.partage.hasFolder {
            Task { _ = await VaultStore.partage.mettreDansICloud(publier: false) }
        }
    }

    /// Le coffre vient d'être choisi ici : les autres appareils l'apprendront.
    func publier(_ url: URL) {
        #if DEBUG
        // Les harnais du simulateur (OKIA_COFFRE) ne parlent pas pour l'utilisateur.
        if ProcessInfo.processInfo.environment["OKIA_COFFRE"] != nil { return }
        #endif
        let d: [String: Any] = [
            "genre": (Self.estDansICloud(url) ? Emplacement.Genre.icloud : .dossier).rawValue,
            "nom": VaultStore.nomLisible(url),
            "lieu": Self.lieu(url),
            "appareil": Self.nomAppareil,
            "id": Self.idAppareil,
            "date": Date(),
        ]
        store.set(d, forKey: cle)
        store.synchronize()
        ailleurs = nil
    }

    /// La suggestion à montrer : le coffre d'un autre appareil, s'il n'est pas déjà celui d'ici et
    /// si l'utilisateur ne l'a pas écartée.
    func suggestion(coffreIci nom: String?, dansICloud: Bool) -> Emplacement? {
        guard let e = ailleurs else { return nil }
        if let ignoree = UserDefaults.standard.object(forKey: cleIgnore) as? Date, ignoree >= e.date { return nil }
        switch e.genre {
        case .icloud: return dansICloud ? nil : e
        case .dossier: return nom == e.nom ? nil : e
        }
    }

    func ignorer(_ e: Emplacement) {
        UserDefaults.standard.set(e.date, forKey: cleIgnore)
        objectWillChange.send()
    }

    /// Le dossier est-il dans le conteneur iCloud de md Viewer ?
    nonisolated static func estDansICloud(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("iCloud~ch~ok-ia~markdownviewer")
    }

    /// Les trois derniers éléments du chemin, comme le Finder et Fichiers les nomment.
    nonisolated static func lieu(_ url: URL) -> String {
        let parties = FileManager.default.componentsToDisplay(forPath: url.path) ?? url.pathComponents
        return parties.filter { $0 != "/" }.suffix(3).joined(separator: " › ")
    }
}
