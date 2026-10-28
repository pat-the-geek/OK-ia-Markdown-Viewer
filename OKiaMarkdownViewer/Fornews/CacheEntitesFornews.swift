// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/CacheEntitesFornews.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Les entités que Wikidata a résolues, publiées dans l'App Group pour md Viewer.**
///
/// Demande de md Viewer (option Analytic, 1.4, 27/10/2026) : ne pas redemander à Wikidata ce que
/// fornews sait déjà. md Viewer lit `Entites/cache.json` dans le conteneur du groupe ; fornews le
/// réécrit après chaque passe d'enrichissement (`PublieurCacheEntites`).
///
/// 🔑 Même patron que `CacheBulletinMontre` : un fichier JSON écrit d'un bloc, de façon atomique,
/// que l'autre application relit à froid sans rien demander à fornews.
///
/// ⛔ **Seulement ce que Wikidata a donné** : nom, alias, type, QID, description, image,
/// coordonnées. Ni texte d'article, ni note, ni entité surveillée — rien de personnel.
///
/// ⚠️ Ce fichier ne dépend que de Foundation : md Viewer peut le copier tel quel
/// (`scripts/copier-fornews.sh`) pour lire le cache avec les mêmes types.
///
/// ⛔ **Pas `CacheEntites`** (renommé le 28/10/2026, avant toute reprise) : md Viewer a déjà sa propre classe
/// `CacheEntites` (`Models/Analytic/AnalyseEntites.swift`), et `copier-fornews.sh` recopie ce code DANS LE MÊME
/// MODULE — les deux noms seraient entrés en collision à la première copie.
public enum CacheEntitesFornews {
    public static let appGroupID = "group.ai.fornews.native"
    /// Nom en clair, comme `BoiteAuxLettres.sousDossier` : qui inspecte le conteneur doit comprendre.
    public static let sousDossier = "Entites"
    public static let nomFichier = "cache.json"

    /// Une entité résolue. Les clés JSON sont les noms des propriétés ; un champ absent vaut `nil`.
    public struct Entree: Codable, Sendable, Equatable {
        public var nom: String
        public var alias: [String]
        /// `TypeEntite.rawValue` : `person`, `org`, `gpe`, `loc`, `product`, `event`, `work`…
        public var type: String
        /// Le QID Wikidata (« Q90 »). Toujours présent : une entité sans QID n'entre pas au cache.
        public var qid: String
        public var description: String?
        public var image: String?
        public var latitude: Double?
        public var longitude: Double?
        /// La langue de `nom` et de `description` : celle du contenu de fornews quand il a publié.
        public var langue: String

        public init(nom: String, alias: [String], type: String, qid: String, description: String?,
                    image: String?, latitude: Double?, longitude: Double?, langue: String) {
            self.nom = nom; self.alias = alias; self.type = type; self.qid = qid
            self.description = description; self.image = image
            self.latitude = latitude; self.longitude = longitude; self.langue = langue
        }
    }

    /// `<conteneur du groupe>/Entites/cache.json`, ou `nil` sans App Group (tests, simulateur ad hoc).
    public static var url: URL? {
        guard let racine = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        return racine.appendingPathComponent(sousDossier, isDirectory: true)
            .appendingPathComponent(nomFichier)
    }

    public static func encoder(_ entrees: [Entree]) -> Data? {
        let e = JSONEncoder()
        // Ordre stable des clés : deux publications identiques donnent deux fichiers identiques.
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? e.encode(entrees)
    }

    public static func decoder(_ data: Data) -> [Entree]? {
        try? JSONDecoder().decode([Entree].self, from: data)
    }

    /// Écrit le cache d'un bloc (`.atomic` : md Viewer ne lit jamais un fichier à moitié écrit).
    /// - Returns: `false` sans App Group ou si l'écriture échoue.
    @discardableResult
    public static func ecrire(_ entrees: [Entree]) -> Bool {
        guard let url else { return false }
        return ecrire(entrees, vers: url)
    }

    public static func lire() -> [Entree]? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return decoder(data)
    }

    /// ⚠️ Écrit dans un dossier donné — pour les tests, qui n'ont pas d'App Group.
    @discardableResult
    public static func ecrire(_ entrees: [Entree], dans dossier: URL) -> Bool {
        ecrire(entrees, vers: dossier.appendingPathComponent(sousDossier, isDirectory: true)
            .appendingPathComponent(nomFichier))
    }

    public static func lire(dans dossier: URL) -> [Entree]? {
        let url = dossier.appendingPathComponent(sousDossier, isDirectory: true).appendingPathComponent(nomFichier)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decoder(data)
    }

    private static func ecrire(_ entrees: [Entree], vers url: URL) -> Bool {
        guard let data = encoder(entrees) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
