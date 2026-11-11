import Foundation

/// A Markdown report found in the vault: at its root, or at any depth of a matching subfolder.
struct VaultReport: Identifiable, Equatable, Sendable {
    /// Its folder, relative to the vault root ("" at the root, "notes/2026" deeper).
    let subfolder: String
    let name: String          // file name, e.g. "2026-06-07 rapport.md"
    let modified: Date
    let downloaded: Bool       // false = iCloud placeholder not yet downloaded
    var id: String { subfolder + "/" + name }
}

/// Remembers the vault **root** folder (security-scoped bookmark) and lists its Markdown files.
///
/// Jusqu'à la 1.5, le coffre ne lisait que les sous-dossiers de premier niveau nommés
/// « rapports-* » — la forme du coffre de fornews. Un dossier partagé d'un iMac, rangé autrement,
/// paraissait vide (Patrick, 11/11/2026). Désormais : les fichiers de la racine, et ceux de tous
/// les niveaux des sous-dossiers que retient le motif (« * » par défaut : tous). La lecture est
/// bornée — profondeur, nombre de fichiers, durée —, car un partage réseau répond lentement.
@MainActor
final class VaultStore: ObservableObject {
    /// Le même coffre dans toutes les fenêtres (1.4).
    static let partage = VaultStore()

    @Published private(set) var folderName: String?
    @Published private(set) var reports: [VaultReport] = []
    @Published private(set) var pattern: String
    /// La dernière lecture s'est arrêtée à une borne : le coffre en contient davantage.
    @Published private(set) var tronque = false
    /// Le dossier du coffre ne se lit pas : un partage réseau déconnecté, un disque absent. Sans
    /// cette mention, le coffre paraissait simplement vide.
    @Published private(set) var injoignable = false

    private let folderKey = "okia.vaultFolder"
    private let patternKey = "okia.vaultPattern"
    /// Le nom du dossier, gardé : un partage déconnecté ne se résout pas, et l'accueil ne savait plus
    /// le nommer.
    private let nameKey = "okia.vaultFolderName"
    static let defaultPattern = "*"
    /// Les bornes d'une lecture : un dossier partagé peut être immense, et le réseau lent.
    static let profondeurMax = 8
    static let fichiersMax = 3000
    static let dureeMax: TimeInterval = 4
    static let extensions: Set<String> = ["md", "markdown"]

    private var bookmark: Data?

    init() {
        bookmark = UserDefaults.standard.data(forKey: folderKey)
        pattern = UserDefaults.standard.string(forKey: patternKey) ?? VaultStore.defaultPattern
        #if DEBUG
        // Le coffre de démonstration des captures (OKIA_DEMO) : lu, jamais enregistré.
        if let demo = ModeDemo.coffre {
            bookmark = try? demo.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            pattern = VaultStore.defaultPattern
        }
        #endif
        folderName = resolveFolder()?.lastPathComponent ?? UserDefaults.standard.string(forKey: nameKey)
    }

    var hasFolder: Bool { bookmark != nil }

    /// Retient le dossier choisi. Faux si le système refuse d'en garder l'accès — on le disait
    /// pas : le choix restait sans effet.
    @discardableResult
    func setFolder(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return false }
        bookmark = data
        UserDefaults.standard.set(data, forKey: folderKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
        folderName = url.lastPathComponent
        refresh()
        return true
    }

    func setPattern(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        pattern = trimmed.isEmpty ? VaultStore.defaultPattern : trimmed
        UserDefaults.standard.set(pattern, forKey: patternKey)
        refresh()
    }

    func clearFolder() {
        bookmark = nil
        UserDefaults.standard.removeObject(forKey: folderKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        folderName = nil
        reports = []
    }

    /// Resolve the stored bookmark to the vault root URL. Caller manages security scope when reading.
    func resolveFolder() -> URL? {
        guard let bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                self.bookmark = fresh
                UserDefaults.standard.set(fresh, forKey: folderKey)
            }
        }
        return url
    }

    func reportURL(_ report: VaultReport) -> URL? {
        resolveFolder()?.appendingPathComponent(report.subfolder).appendingPathComponent(report.name)
    }

    /// Supprime un rapport du coffre (1.4), téléchargé ou encore dans iCloud, puis relit le coffre.
    func supprimer(_ report: VaultReport) throws {
        guard let root = resolveFolder() else { return }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let dossier = root.appendingPathComponent(report.subfolder)
        var url = dossier.appendingPathComponent(report.name)
        if !FileManager.default.fileExists(atPath: url.path) {
            url = dossier.appendingPathComponent("." + report.name + ".icloud")
        }
        RecentFilesStore.partage.retirer(url: dossier.appendingPathComponent(report.name))
        try SuppressionDocument.supprimer(url)
        refresh()
    }

    /// Relit le coffre, tout de suite : ceux qui l'appellent lisent `reports` juste après.
    func refresh() {
        guard let root = resolveFolder() else { publierInjoignable(); return }
        let (liste, coupe, lu) = Self.lire(racine: root, motif: pattern)
        publier(liste, coupe, lu)
    }

    /// Relit le coffre hors du fil principal, puis publie : pour la relecture périodique du Mac,
    /// qu'un partage réseau lent ne doit pas geler.
    func rafraichirEnArrierePlan() async {
        guard let root = resolveFolder() else { publierInjoignable(); return }
        let motif = pattern
        let (liste, coupe, lu) = await Task.detached(priority: .utility) { Self.lire(racine: root, motif: motif) }.value
        publier(liste, coupe, lu)
    }

    private func publier(_ liste: [VaultReport], _ coupe: Bool, _ lu: Bool) {
        if liste != reports { reports = liste }
        if coupe != tronque { tronque = coupe }
        if lu == injoignable { injoignable = !lu }
    }

    private func publierInjoignable() {
        if !reports.isEmpty { reports = [] }
        tronque = false
        injoignable = bookmark != nil
    }

    /// Les fichiers Markdown de la racine, et ceux de tous les niveaux des sous-dossiers de premier
    /// niveau que retient `motif`, du plus récent au plus ancien. Dossiers cachés (`.obsidian`,
    /// `.git`) et paquets ignorés ; les fichiers encore dans iCloud (`.nom.md.icloud`) comptés.
    /// Renvoie aussi si une borne a arrêté la lecture, et si la racine s'est lue.
    nonisolated static func lire(racine root: URL, motif: String) -> ([VaultReport], Bool, Bool) {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let predicate = NSPredicate(format: "SELF LIKE[c] %@", motif)
        let cles: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        let fin = Date().addingTimeInterval(dureeMax)
        var trouves: [VaultReport] = []
        var coupe = false
        // La racine elle-même ne se lit pas : le dossier n'est pas joignable.
        guard (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) != nil else {
            return ([], false, false)
        }

        // En largeur : les dossiers proches d'abord, si une borne arrête la lecture.
        var aLire: [(url: URL, relatif: String, profondeur: Int)] = [(root, "", 0)]
        while !aLire.isEmpty {
            if trouves.count >= fichiersMax || Date() > fin { coupe = true; break }
            let dossier = aLire.removeFirst()
            guard let enfants = try? fm.contentsOfDirectory(at: dossier.url, includingPropertiesForKeys: cles,
                                                            options: []) else { continue }
            for enfant in enfants {
                let nom = enfant.lastPathComponent
                let valeurs = try? enfant.resourceValues(forKeys: Set(cles))
                if valeurs?.isDirectory == true {
                    // Dossier caché ou paquet (une app, une bibliothèque Photos) : jamais lu.
                    if nom.hasPrefix(".") || valeurs?.isPackage == true { continue }
                    // Le motif choisit les sous-dossiers de premier niveau ; plus bas, tout est lu.
                    if dossier.profondeur == 0 && !predicate.evaluate(with: nom) { continue }
                    if dossier.profondeur + 1 > profondeurMax { coupe = true; continue }
                    let relatif = dossier.relatif.isEmpty ? nom : dossier.relatif + "/" + nom
                    aLire.append((enfant, relatif, dossier.profondeur + 1))
                    continue
                }
                let fichier: String, telecharge: Bool
                if !nom.hasPrefix("."), extensions.contains((nom as NSString).pathExtension.lowercased()) {
                    fichier = nom; telecharge = true
                } else if nom.hasPrefix("."), nom.hasSuffix(".icloud") {
                    let interieur = String(nom.dropFirst().dropLast(".icloud".count))
                    guard extensions.contains((interieur as NSString).pathExtension.lowercased()) else { continue }
                    fichier = interieur; telecharge = false
                } else {
                    continue
                }
                trouves.append(VaultReport(subfolder: dossier.relatif, name: fichier,
                                           modified: valeurs?.contentModificationDate ?? .distantPast,
                                           downloaded: telecharge))
            }
        }
        return (trouves.sorted { $0.modified > $1.modified }, coupe, true)
    }
}

extension VaultReport {
    /// Où il se trouve, pour une ligne de l'accueil : son dossier, ou rien à la racine.
    var mentionDossier: String { subfolder.isEmpty ? "" : subfolder + " · " }
}
