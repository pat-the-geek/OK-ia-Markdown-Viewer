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
        FileManager.default.url(forUbiquityContainerIdentifier: SynchroICloud.conteneur)?
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
    static func documents() -> [(url: URL, nom: String, date: Date)] {
        let dossier = dossierAnalyses()
        guard let e = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: [.creationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "md" }.map { u in
            let d = (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (u, u.deletingPathExtension().lastPathComponent, d)
        }
        .sorted { $0.date > $1.date }
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
    static func ecrire(_ markdown: String, titre: String, analyse: Bool = true) throws -> URL {
        let dossier = analyse ? dossier()
            : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pages web", isDirectory: true)
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
        // Spotlight apprend le nouveau document (un lot n'envoie qu'une fois).
        if analyse { Task { @MainActor in RechercheCoffre.partage.indexerSpotlight() } }
        return cible
    }
}
