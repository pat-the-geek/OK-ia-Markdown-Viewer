import Foundation

#if DEBUG
/// Harnais de capture (Debug uniquement, absent du binaire livré) : OKIA_DEMO=<dossier> montre un
/// accueil de démonstration — son coffre (`<dossier>/Tourisme suisse`), les documents analysés de
/// `<dossier>/Documents analysés`, aucun récent — sans rien lire ni écrire des vrais réglages.
/// Sur le Mac, le build Debug partage le conteneur et l'iCloud de l'utilisateur : les captures de
/// l'accueil et de l'analyse du coffre (1.4) n'y montrent ni n'y laissent rien.
enum ModeDemo {
    static let dossier: URL? = ProcessInfo.processInfo.environment["OKIA_DEMO"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }

    static var actif: Bool { dossier != nil }
    /// Le coffre : le dossier de la démonstration qui contient des rapports (`rapports-*`, comme le
    /// coffre réel) — « Tourisme suisse », traduit ; son nom est celui que l'accueil affiche. Plus le
    /// nom des documents analysés à écarter : il est écrit dans quinze langues.
    static var coffre: URL? {
        guard let dossier,
              let noms = try? FileManager.default.contentsOfDirectory(atPath: dossier.path) else { return nil }
        return noms.sorted()
            .map { dossier.appendingPathComponent($0, isDirectory: true) }
            .first { u in
                let dedans = (try? FileManager.default.contentsOfDirectory(atPath: u.path)) ?? []
                return dedans.contains { $0.hasPrefix("rapports-") }
            }
    }
}
#endif
