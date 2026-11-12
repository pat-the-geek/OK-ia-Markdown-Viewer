import Foundation

/// Option Analytic (1.4) — où et sous quel nom md Viewer range ce qu'il crée : les imports Word, PDF
/// et PowerPoint, leurs rapports d'analyse, les fiches de pages web (Patrick, 27/10/2026 : « si les
/// documents sont stockés dans le cloud, il faut les auto-organiser dans des répertoires année, mois,
/// jour » ; « est-ce qu'on peut normaliser automatiquement le nom du fichier ? » — noms lisibles).
///
/// - Dans **iCloud Drive**, dossier « md Viewer » : le même fichier sur tous les appareils de
///   l'utilisateur, et ses annotations le suivent (`SynchroICloud`, qui reconnaît un document à son
///   nom et à son contenu). Sans iCloud Drive, dans les documents de l'app, rangés pareil.
/// - Dans **« Documents analysés »** (Patrick, 27/10 : « appeler le nouveau dossier documents
///   analysés »), à part du coffre de la 1.3 — le dossier de rapports que l'utilisateur a choisi.
///   Réservé à l'option Analytic (« il faut avoir payé l'extension ») : sans elle, le texte d'une
///   page web va dans « Pages web », un dossier local de l'app.
/// - Par **date de création** : `Documents analysés/2026/10/27/`.
/// - Sous un **nom lisible et normalisé** : le titre, accents gardés, sans les caractères qu'un nom
///   de fichier n'admet pas, 80 caractères au plus, « (2) » en cas de doublon.
///
/// Les documents ouverts depuis Fichiers ne sont jamais déplacés ni renommés.
enum RangementDocuments {

    /// Le dossier du jour : `md Viewer/Documents analysés/AAAA/MM/JJ` dans iCloud Drive, sinon dans les
    /// documents de l'app. ⚠️ Ne pas appeler sur le fil principal : la première demande du conteneur
    /// iCloud peut attendre.
    static func dossier(pour date: Date = Date()) -> URL {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return dossierAnalyses()
            .appendingPathComponent(String(format: "%04d", c.year ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", c.month ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", c.day ?? 0), isDirectory: true)
    }

    /// Le nom du dossier, dans la langue de l'app. Un dossier déjà là, dans une autre langue, reste
    /// celui qu'on emploie : changer de langue ne doit pas couper les documents en deux.
    static let nomsDuDossier = ["fr": "Documents analysés", "en": "Analyzed Documents",
                                "de": "Analysierte Dokumente", "es": "Documentos analizados",
                                "it": "Documenti analizzati", "ja": "分析済みの書類", "ko": "분석된 문서",
                                "zh-Hans": "已分析的文档", "pt-BR": "Documentos analisados",
                                "nl": "Geanalyseerde documenten", "ru": "Проанализированные документы",
                                "uk": "Проаналізовані документи", "tr": "Analiz Edilen Belgeler",
                                "vi": "Tài liệu đã phân tích", "hi": "विश्लेषित दस्तावेज़"]

    /// iCloud Drive (« md Viewer »), sinon les documents de l'app.
    static func racine() -> URL {
        #if DEBUG
        if let demo = ModeDemo.dossier { return demo }
        #endif
        return FileManager.default.url(forUbiquityContainerIdentifier: SynchroICloud.conteneur)?
            .appendingPathComponent("Documents", isDirectory: true)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Le dossier « Documents analysés ».
    static func dossierAnalyses() -> URL {
        let r = racine()
        for nom in nomsDuDossier.values where FileManager.default.fileExists(atPath: r.appendingPathComponent(nom).path) {
            return r.appendingPathComponent(nom, isDirectory: true)
        }
        let choisie = UserDefaults.standard.string(forKey: "okia.language").flatMap { nomsDuDossier[$0] }
            ?? nomsDuDossier[Localization.systemCode]   // « zh-Hans », « pt-BR » : pas deux lettres
            ?? nomsDuDossier["en"]!
        return r.appendingPathComponent(choisie, isDirectory: true)
    }

    /// Les documents analysés, du plus récent au plus ancien (date de création).
    /// Un document créé sur un autre appareil n'est d'abord, sur iPhone et iPad, qu'un espace réservé
    /// iCloud caché, `.Nom.md.icloud` : il compte aussi, sous son vrai nom, et son téléchargement est
    /// demandé (Patrick, 29/10/2026 : « j'ai analysé un document sur Mac, je ne le vois pas apparaître
    /// dans les documents analysés sur mon iPhone »). L'ouvrir passe par un coordinateur, qui attend
    /// le fichier.
    static func documents() -> [(url: URL, nom: String, date: Date)] {
        let dossier = dossierAnalyses()
        guard let e = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                                                     options: []) else { return [] }
        var vus = Set<String>()
        var resultat: [(url: URL, nom: String, date: Date)] = []
        for case let u as URL in e {
            let nom = u.lastPathComponent
            var reel = u
            if nom.hasPrefix(".") {
                // Les autres fichiers et dossiers cachés restent à l'écart, comme avant. Ne sauter que
                // l'intérieur d'un dossier : appelé sur un fichier — le `.DS_Store` que le Finder pose
                // dès qu'on ouvre le dossier —, `skipDescendants` sautait le dossier suivant, « 2026 »,
                // et l'accueil du Mac n'avait plus aucun document analysé (Patrick, 30/10/2026).
                guard nom.hasSuffix(".icloud") else {
                    if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { e.skipDescendants() }
                    continue
                }
                reel = u.deletingLastPathComponent()
                    .appendingPathComponent(String(nom.dropFirst().dropLast(".icloud".count)))
                guard reel.pathExtension.lowercased() == "md" else { continue }
                try? FileManager.default.startDownloadingUbiquitousItem(at: reel)
            }
            guard reel.pathExtension.lowercased() == "md", vus.insert(reel.path).inserted else { continue }
            let d = (try? reel.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            resultat.append((reel, reel.deletingPathExtension().lastPathComponent, d))
        }
        return resultat.sorted { $0.date > $1.date }
    }

    /// Le nom lisible d'un document, sans extension : « Apple : la keynote / résumé » → « Apple - la
    /// keynote - résumé ».
    static func nomNormalise(_ titre: String) -> String {
        var s = titre.precomposedStringWithCanonicalMapping
        // Ce qu'un nom de fichier n'admet pas, sur Mac, iOS ou Windows (iCloud pour Windows).
        s = s.replacingOccurrences(of: #"\s*[:/\\|]\s*"#, with: " - ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[?*"<>\p{Cc}]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\s*-\s*){2,}"#, with: " - ", options: .regularExpression)
        // Ni point au début (fichier caché), ni tiret, point ou espace aux bouts.
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .-–—").union(.whitespacesAndNewlines))
        if s.count > 80 {
            // Couper à la fin d'un mot.
            let coupe = String(s.prefix(80))
            s = coupe.range(of: " ", options: .backwards).map { String(coupe[..<$0.lowerBound]) } ?? coupe
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .-–—,;"))
        }
        return s.isEmpty ? "Document" : s
    }

    /// Écrit un Markdown créé par md Viewer à sa place, sans écraser un document du même nom.
    /// `analyse` : un document de l'option (import, fiche) ; faux, le texte seul d'une page web, sans
    /// l'option — dans « Pages web », un dossier local de l'app, jamais dans « Documents analysés ».
    ///
    /// Depuis la 1.5.1, un document de l'option va dans le coffre, dossier « coffre md viewer », par
    /// année et par mois (`importsDansCoffre`) ; le coffre injoignable (un partage qui dort), dans « Documents
    /// analysés », et l'import le dit (`estRepli`).
    static func ecrire(_ markdown: String, titre: String, analyse: Bool = true) throws -> URL {
        if analyse, importsDansCoffre, let racine = racineCoffre() {
            let ouvert = racine.startAccessingSecurityScopedResource()
            defer { if ouvert { racine.stopAccessingSecurityScopedResource() } }
            if coffreJoignable(racine),
               let u = try? ecrire(markdown, titre: titre, dans: dossierDansCoffre(racine)) {
                Task { @MainActor in
                    RechercheCoffre.partage.indexerSpotlight()
                    await VaultStore.partage.rafraichirEnArrierePlan(forcee: true)
                }
                return u
            }
            let u = try ecrire(markdown, titre: titre, dans: dossier())
            noterRepli(u)
            Task { @MainActor in RechercheCoffre.partage.indexerSpotlight() }
            return u
        }
        let dossier = analyse ? dossier()
            : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pages web", isDirectory: true)
        let u = try ecrire(markdown, titre: titre, dans: dossier)
        // Spotlight apprend le nouveau document (un lot n'envoie qu'une fois).
        if analyse { Task { @MainActor in RechercheCoffre.partage.indexerSpotlight() } }
        return u
    }

    private static func ecrire(_ markdown: String, titre: String, dans dossier: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let base = nomNormalise(titre)
        var cible = dossier.appendingPathComponent(base + ".md")
        var n = 2
        while FileManager.default.fileExists(atPath: cible.path) {
            cible = dossier.appendingPathComponent("\(base) (\(n)).md"); n += 1
        }
        // iCloud Drive : l'écriture passe par un coordinateur, comme le veut le système de fichiers
        // partagé (le démon d'iCloud peut lire le dossier au même moment).
        var erreurCoordination: NSError?
        var erreurEcriture: Error?
        NSFileCoordinator().coordinate(writingItemAt: cible, options: .forReplacing, error: &erreurCoordination) { url in
            do { try markdown.write(to: url, atomically: true, encoding: .utf8) } catch { erreurEcriture = error }
        }
        if let e = erreurCoordination ?? erreurEcriture { throw e }
        return cible
    }

    // MARK: Le coffre (1.5.1)

    // Patrick, 12/11/2026 : les documents importés peuvent aller dans le coffre, dans un dossier
    // « coffre md viewer » au même niveau que les rapports, sur le même lecteur (le partage de l'iMac).
    // Le coffre les lit toujours, quel que soit son motif (`VaultStore.lire`).

    /// Le dossier des imports, à la racine du coffre.
    static let dossierDuCoffre = "coffre md viewer"
    /// Le réglage « Ranger les imports dans le coffre » (réglages du coffre) : vrai par défaut.
    static let cleDansCoffre = "okia.importsDansCoffre"

    static var importsDansCoffre: Bool {
        UserDefaults.standard.object(forKey: cleDansCoffre) as? Bool ?? true
    }

    /// La racine du coffre, d'après le signet que garde `VaultStore`, sans monter de volume ; nil sans
    /// coffre. Hors du fil principal : résoudre le signet d'un partage touche au réseau.
    static func racineCoffre() -> URL? {
        guard let signet = UserDefaults.standard.data(forKey: "okia.vaultFolder") else { return nil }
        var perime = false
        return try? URL(resolvingBookmarkData: signet, options: [.withoutMounting], relativeTo: nil,
                        bookmarkDataIsStale: &perime)
    }

    /// Le coffre répond : sa racine existe. Sans ce garde-fou, un partage démonté laissait un chemin
    /// sous /Volumes, et créer le dossier du jour y aurait fait un dossier local.
    private static func coffreJoignable(_ racine: URL) -> Bool {
        var dossier: ObjCBool = false
        return FileManager.default.fileExists(atPath: racine.path, isDirectory: &dossier) && dossier.boolValue
    }

    /// `coffre md viewer/AAAA/MM` dans le coffre : par année et par mois, comme les rapports
    /// (Patrick, 12/11/2026 : « on prévoit aussi une structure année mois »).
    static func dossierDansCoffre(_ racine: URL, pour date: Date = Date()) -> URL {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return racine.appendingPathComponent(dossierDuCoffre, isDirectory: true)
            .appendingPathComponent(String(format: "%04d", c.year ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", c.month ?? 0), isDirectory: true)
    }

    /// Les documents rangés dans « Documents analysés » faute de coffre joignable : l'import le dit.
    private static let verrou = NSLock()
    nonisolated(unsafe) private static var replis: Set<String> = []

    private static func noterRepli(_ url: URL) {
        verrou.lock(); defer { verrou.unlock() }
        replis.insert(url.standardizedFileURL.path)
    }

    /// Vrai si ce document a été rangé dans « Documents analysés » faute de coffre (une seule fois).
    static func estRepli(_ url: URL) -> Bool {
        verrou.lock(); defer { verrou.unlock() }
        return replis.remove(url.standardizedFileURL.path) != nil
    }

    enum ErreurCoffre: LocalizedError {
        case aucun, injoignable
        var errorDescription: String? {
            switch self {
            case .aucun: return tr("Aucun coffre n’est choisi.")
            case .injoignable: return tr("Le coffre n’est pas joignable. Le document reste dans « Documents analysés ».")
            }
        }
    }

    /// « Mettre dans le coffre » : déplace un document analysé dans `coffre md viewer`, au dossier du
    /// mois de sa création. Le même nom et le même contenu : ses annotations le suivent. Un document
    /// identique déjà là : celui de « Documents analysés » est seulement retiré. Hors du fil principal.
    static func mettreDansCoffre(_ source: URL) throws -> URL {
        guard let racine = racineCoffre() else { throw ErreurCoffre.aucun }
        let ouvert = racine.startAccessingSecurityScopedResource()
        defer { if ouvert { racine.stopAccessingSecurityScopedResource() } }
        guard coffreJoignable(racine) else { throw ErreurCoffre.injoignable }

        // Lu par un coordinateur : un document venu d'un autre appareil peut être encore dans iCloud.
        var erreurLecture: NSError?
        var donnees: Data?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &erreurLecture) { u in
            donnees = try? Data(contentsOf: u)
        }
        guard let donnees else { throw erreurLecture ?? CocoaError(.fileReadUnknown) }

        let creation = (try? source.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let dossier = dossierDansCoffre(racine, pour: creation)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        var cible = dossier.appendingPathComponent(source.lastPathComponent)
        var n = 2
        var dejaLa = false
        while FileManager.default.fileExists(atPath: cible.path) {
            if (try? Data(contentsOf: cible)) == donnees { dejaLa = true; break }
            cible = dossier.appendingPathComponent("\(base) (\(n)).md"); n += 1
        }
        if !dejaLa {
            try donnees.write(to: cible, options: .atomic)
            // La date de création suit : l'accueil et la recherche datent le document par elle.
            try? FileManager.default.setAttributes([.creationDate: creation], ofItemAtPath: cible.path)
        }
        // Retiré de « Documents analysés », par un coordinateur (iCloud Drive).
        var erreurSuppression: NSError?
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forDeleting, error: &erreurSuppression) { u in
            try? FileManager.default.removeItem(at: u)
        }
        return cible
    }
}
