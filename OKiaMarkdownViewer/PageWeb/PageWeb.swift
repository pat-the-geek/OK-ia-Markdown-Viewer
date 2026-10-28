import Foundation

// Option Analytic (1.4) — une page web envoyée à md Viewer depuis Safari (ou toute app qui partage
// une adresse). Ce fichier est compilé dans l'app ET dans l'extension de partage : il ne dépend de
// rien d'autre que Foundation.

/// Ce que `ExtrairePage.js` rend d'une page : ses métadonnées et le corps de l'article, bloc par
/// bloc, en texte simple. Une page reçue par sa seule adresse n'a que `url` : l'app la charge alors
/// elle-même et y exécute le même script.
struct PageWeb: Codable, Sendable, Equatable {
    struct Bloc: Codable, Sendable, Equatable {
        /// « h » (intertitre), « p », « li », « q » (citation), « img » (adresse d'une illustration).
        var t: String
        var x: String
    }
    var url: String
    var titre: String?
    var media: String?
    var auteur: String?
    var date: String?
    var image: String?
    var logo: String?
    var langue: String?
    var description: String?
    var blocs: [Bloc]?
    var erreur: String?

    /// La page a-t-elle un corps lisible ? Sinon, l'app la recharge à partir de son adresse.
    var aUnCorps: Bool { (blocs ?? []).contains { $0.t != "img" && $0.x.count > 40 } }
}

/// La boîte de réception des pages partagées : un fichier JSON par page, dans le groupe d'apps que
/// md Viewer partage déjà avec fornews (`group.ai.fornews.native`, celui de `BoiteAuxLettres`) —
/// l'extension de partage y dépose, l'app y relève à son prochain passage au premier plan.
/// ⚠️ Un groupe de plus aurait demandé un nouvel identifiant de groupe dans App Store Connect pour
/// l'app, l'extension et le Mac ; celui-ci est déjà enregistré et livré.
enum BoitePages {
    static let groupe = "group.ai.fornews.native"

    static var dossier: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupe)?
            .appendingPathComponent("mdviewer-pages", isDirectory: true)
    }

    static func deposer(_ page: PageWeb) throws {
        guard let d = dossier else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let nom = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            + "-" + UUID().uuidString.prefix(8) + ".json"
        try JSONEncoder().encode(page).write(to: d.appendingPathComponent(nom), options: .atomic)
    }

    /// Le signal qui prévient l'app qu'une page attend (une notification Darwin, d'un processus à
    /// l'autre). Sans lui, md Viewer ne relevait la boîte qu'en revenant au premier plan : déjà à
    /// l'écran (le Duo déplié, Safari d'un côté et md Viewer de l'autre ; l'iPad partagé ; le Mac),
    /// il ne faisait rien (Patrick, 28/10/2026).
    static let signal = "ch.ok-ia.markdownviewer.page-deposee"

    /// L'extension, une fois la page déposée.
    static func signaler() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(signal as CFString), nil, nil, true)
    }

    /// L'app : `action` sur le fil principal à chaque page déposée, tant qu'elle tourne.
    nonisolated(unsafe) private static var surSignal: (() -> Void)?
    static func ecouter(_ action: @escaping () -> Void) {
        surSignal = action
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { BoitePages.surSignal?() }
        }, signal as CFString, nil, .deliverImmediately)
    }

    /// Les pages en attente, des plus anciennes aux plus récentes ; chacune est retirée de la boîte.
    static func relever() -> [PageWeb] {
        guard let d = dossier,
              let fichiers = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)
        else { return [] }
        return fichiers.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { f in
                defer { try? FileManager.default.removeItem(at: f) }
                return (try? Data(contentsOf: f)).flatMap { try? JSONDecoder().decode(PageWeb.self, from: $0) }
            }
    }
}
