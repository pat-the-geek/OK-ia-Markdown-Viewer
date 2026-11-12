import Foundation

/// A Markdown report found in the vault: at its root, or at any depth of a matching subfolder.
struct VaultReport: Identifiable, Equatable, Sendable, Codable {
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
///
/// Un dossier réseau — un partage de l'iMac, à travers Tailscale (Patrick, 11/11/2026) — répond
/// en dizaines ou centaines de millisecondes par dossier. Les dossiers d'un même niveau se lisent
/// donc ensemble ; un dossier réseau ne se lit jamais sur le fil principal, a une borne de durée plus
/// large et se relit moins souvent ; la dernière liste est gardée et montrée dès le lancement.
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
    /// Une lecture du coffre est en cours (au lancement, un partage lent met du temps à répondre).
    @Published private(set) var enLecture = false
    /// Le coffre est sur un volume réseau : il ne se lit qu'en arrière-plan, et moins souvent.
    @Published private(set) var reseau = false
    /// La fin de la dernière lecture : la surveillance du Mac espace celles d'un dossier réseau.
    private(set) var derniereLecture: Date = .distantPast

    private let folderKey = "okia.vaultFolder"
    private let patternKey = "okia.vaultPattern"
    /// Le nom du dossier, gardé : un partage déconnecté ne se résout pas, et l'accueil ne savait plus
    /// le nommer.
    private let nameKey = "okia.vaultFolderName"
    static let defaultPattern = "*"
    /// Les bornes d'une lecture : un dossier partagé peut être immense, et le réseau lent.
    nonisolated static let profondeurMax = 8
    nonisolated static let fichiersMax = 3000
    nonisolated static let dureeMax: TimeInterval = 4
    /// Sur un volume réseau, la lecture se fait en arrière-plan : elle peut durer davantage.
    nonisolated static let dureeMaxReseau: TimeInterval = 20
    /// Les dossiers lus ensemble : assez pour masquer la latence, sans noyer le serveur.
    nonisolated static let lecturesSimultanees = 8
    nonisolated static let extensions: Set<String> = ["md", "markdown"]

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
        chargerListe()
    }

    // MARK: La dernière liste, gardée

    /// Ce qu'on garde d'une lecture : la liste, pour quel dossier et quel motif, et si c'était un
    /// volume réseau.
    private struct ListeGardee: Codable {
        let dossier: String
        let motif: String
        let reseau: Bool
        let rapports: [VaultReport]
    }

    private static let fichierListe: URL = {
        let dossier = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dossier.appendingPathComponent("coffre-liste.json")
    }()

    private func chargerListe() {
        guard hasFolder, let data = try? Data(contentsOf: Self.fichierListe),
              let g = try? JSONDecoder().decode(ListeGardee.self, from: data),
              g.dossier == (folderName ?? ""), g.motif == pattern else { return }
        reports = g.rapports
        reseau = g.reseau
    }

    private func garderListe() {
        let g = ListeGardee(dossier: folderName ?? "", motif: pattern, reseau: reseau, rapports: reports)
        if let data = try? JSONEncoder().encode(g) { try? data.write(to: Self.fichierListe, options: .atomic) }
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
        reports = []
        reseau = Self.estReseau(url)
        refresh()
        return true
    }

    func setPattern(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        pattern = trimmed.isEmpty ? VaultStore.defaultPattern : trimmed
        UserDefaults.standard.set(pattern, forKey: patternKey)
        reports = []
        refresh()
    }

    func clearFolder() {
        bookmark = nil
        UserDefaults.standard.removeObject(forKey: folderKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        folderName = nil
        reports = []
        try? FileManager.default.removeItem(at: Self.fichierListe)
    }

    /// Resolve the stored bookmark to the vault root URL. Caller manages security scope when reading.
    func resolveFolder() -> URL? {
        guard let bookmark else { return nil }
        var stale = false
        // Sans monter le volume : un partage déconnecté ferait attendre le fil principal le temps
        // que le système tente de le monter. Il est alors dit injoignable.
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutMounting],
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

    /// Relit le coffre. Un dossier local, tout de suite : ceux qui l'appellent lisent `reports` juste
    /// après. Un dossier réseau, jamais sur le fil principal : la relecture part en arrière-plan, et
    /// l'appelant lit la dernière liste connue.
    func refresh() {
        if reseau {
            Task { await rafraichirEnArrierePlan() }
            return
        }
        guard let root = resolveFolder() else { publierInjoignable(); return }
        publier(Self.lire(racine: root, motif: pattern))
    }

    /// Une relecture forcée demandée pendant une autre lecture : elle suit celle-ci.
    private var relireEnsuite = false

    /// Relit le coffre hors du fil principal, puis publie. Une lecture à la fois : celle qui est en
    /// cours suffit.
    ///
    /// `forcee` — le bouton « Recharger le coffre » (Patrick, 12/11/2026) : la relecture part tout de
    /// suite, même pour un dossier réseau relu il y a peu ; demandée pendant une lecture, elle la
    /// suit au lieu d'être perdue ; et un partage déconnecté est remonté, si le système le peut
    /// (une lecture ordinaire ne monte jamais rien).
    func rafraichirEnArrierePlan(forcee: Bool = false) async {
        guard !enLecture else {
            if forcee { relireEnsuite = true }
            return
        }
        guard let marque = bookmark else { return }
        enLecture = true
        var monter = forcee
        repeat {
            relireEnsuite = false
            let rapide = resolveFolder()
            let motif = pattern
            let lecture = await Task.detached(priority: monter ? .userInitiated : .utility) {
                Self.lire(rapide: rapide, marque: marque, motif: motif, monter: monter)
            }.value
            if let lecture { publier(lecture) } else { publierInjoignable() }
            monter = true
        } while relireEnsuite
        enLecture = false
    }

    /// La lecture du dossier résolu sans montage ; s'il ne répond pas et que `monter`, le signet
    /// est résolu à nouveau en laissant le système monter le volume (un partage SMB de l'iMac,
    /// déconnecté), puis relu. Nil : le dossier reste introuvable.
    nonisolated private static func lire(rapide: URL?, marque: Data, motif: String, monter: Bool) -> Lecture? {
        var lecture: Lecture?
        if let rapide { lecture = lire(racine: rapide, motif: motif) }
        guard monter, lecture?.lu != true else { return lecture }
        var perime = false
        guard let monte = try? URL(resolvingBookmarkData: marque, options: [], relativeTo: nil,
                                   bookmarkDataIsStale: &perime) else { return lecture }
        return lire(racine: monte, motif: motif)
    }

    private func publier(_ l: Lecture) {
        derniereLecture = Date()
        if l.reseau != reseau { reseau = l.reseau }
        if l.lu == injoignable { injoignable = !l.lu }
        // Injoignable : la dernière liste reste affichée, avec la mention — un partage qui ne répond
        // pas un instant ne vide plus l'accueil.
        guard l.lu else { return }
        if l.rapports != reports { reports = l.rapports }
        if l.coupe != tronque { tronque = l.coupe }
        garderListe()
    }

    private func publierInjoignable() {
        derniereLecture = Date()
        tronque = false
        injoignable = bookmark != nil
    }

    /// Ce qu'une lecture rapporte.
    struct Lecture: Sendable {
        var rapports: [VaultReport] = []
        var coupe = false
        var lu = true
        var reseau = false
    }

    /// Le dossier est-il sur un volume réseau ? Un partage monté (SMB, AFP) sur Mac, un serveur
    /// ajouté dans Fichiers sur iPhone et iPad.
    nonisolated static func estReseau(_ url: URL) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OKIA_LATENCE_COFFRE"] != nil { return true }
        #endif
        if url.path.contains("/LiveFiles/") { return true }
        return (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false
    }

    /// Les fichiers Markdown de la racine, et ceux de tous les niveaux des sous-dossiers de premier
    /// niveau que retient `motif`, du plus récent au plus ancien. Dossiers cachés (`.obsidian`,
    /// `.git`) et paquets ignorés ; les fichiers encore dans iCloud (`.nom.md.icloud`) comptés.
    /// Niveau par niveau, les dossiers d'un niveau lus ensemble : une structure année / mois se lit
    /// en trois vagues, non en autant d'allers-retours que de mois.
    nonisolated static func lire(racine root: URL, motif: String) -> Lecture {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let predicate = NSPredicate(format: "SELF LIKE[c] %@", motif)
        let cles: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        var lecture = Lecture(reseau: estReseau(root))
        let fin = Date().addingTimeInterval(lecture.reseau ? dureeMaxReseau : dureeMax)
        #if DEBUG
        // OKIA_LATENCE_COFFRE=<ms> : chaque dossier répond avec ce retard, comme un partage lointain.
        let latence = Double(ProcessInfo.processInfo.environment["OKIA_LATENCE_COFFRE"] ?? "") ?? 0
        #endif
        func lister(_ url: URL, _ c: [URLResourceKey]?) -> [URL]? {
            #if DEBUG
            if latence > 0 { Thread.sleep(forTimeInterval: latence / 1000) }
            #endif
            return try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: c, options: [])
        }

        typealias Dossier = (url: URL, relatif: String, profondeur: Int)
        var niveau: [Dossier] = [(root, "", 0)]
        var racineLue = false
        while !niveau.isEmpty {
            if lecture.rapports.count >= fichiersMax || Date() > fin { lecture.coupe = true; break }
            // Les dossiers du niveau, lus ensemble, chacun à sa place dans le résultat.
            var contenus = [[URL]?](repeating: nil, count: niveau.count)
            let verrou = NSLock()
            let lot = niveau
            DispatchQueue.concurrentPerform(iterations: min(lot.count, lecturesSimultanees)) { voie in
                var k = voie
                while k < lot.count {
                    if Date() > fin { break }
                    let enfants = lister(lot[k].url, cles)
                    verrou.lock(); contenus[k] = enfants; verrou.unlock()
                    k += lecturesSimultanees
                }
            }
            var suivant: [Dossier] = []
            for (k, dossier) in lot.enumerated() {
                guard let enfants = contenus[k] else {
                    if dossier.profondeur == 0 { return Lecture(lu: false, reseau: lecture.reseau) }
                    continue
                }
                if dossier.profondeur == 0 { racineLue = true }
                for enfant in enfants {
                    let nom = enfant.lastPathComponent
                    let valeurs = try? enfant.resourceValues(forKeys: Set(cles))
                    if valeurs?.isDirectory == true {
                        // Dossier caché ou paquet (une app, une bibliothèque Photos) : jamais lu.
                        if nom.hasPrefix(".") || valeurs?.isPackage == true { continue }
                        // Le motif choisit les sous-dossiers de premier niveau ; plus bas, tout est lu.
                        if dossier.profondeur == 0 && !predicate.evaluate(with: nom) { continue }
                        if dossier.profondeur + 1 > profondeurMax { lecture.coupe = true; continue }
                        let relatif = dossier.relatif.isEmpty ? nom : dossier.relatif + "/" + nom
                        suivant.append((enfant, relatif, dossier.profondeur + 1))
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
                    lecture.rapports.append(VaultReport(subfolder: dossier.relatif, name: fichier,
                                                        modified: valeurs?.contentModificationDate ?? .distantPast,
                                                        downloaded: telecharge))
                }
            }
            // Un dossier du niveau resté sans réponse avant la borne : la lecture est incomplète.
            if contenus.contains(where: { $0 == nil }) && Date() > fin { lecture.coupe = true }
            niveau = suivant
        }
        lecture.lu = racineLue
        lecture.rapports.sort { $0.modified > $1.modified }
        return lecture
    }
}

extension VaultReport {
    /// Où il se trouve, pour une ligne de l'accueil : son dossier, ou rien à la racine.
    var mentionDossier: String { subfolder.isEmpty ? "" : subfolder + " · " }
}
