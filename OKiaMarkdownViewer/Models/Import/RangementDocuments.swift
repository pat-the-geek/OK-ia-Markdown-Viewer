import Foundation

/// Option Analytic (1.4) — où et sous quel nom md Viewer range ce qu'il crée : les imports Word, PDF
/// et PowerPoint, leurs rapports d'analyse, les fiches de pages web (Patrick, 27/10/2026 : « si les
/// documents sont stockés dans le cloud, il faut les auto-organiser dans des répertoires année, mois,
/// jour » ; « est-ce qu'on peut normaliser automatiquement le nom du fichier ? » — noms lisibles).
///
/// - Dans **iCloud Drive**, dossier « md Viewer » : le même fichier sur tous les appareils de
///   l'utilisateur, et ses annotations le suivent (`SynchroICloud`, qui reconnaît un document à son
///   nom et à son contenu). Sans iCloud Drive, dans les documents de l'app, rangés pareil.
/// - Par **date de création** : `Importés/2026/10/27/`.
/// - Sous un **nom lisible et normalisé** : le titre, accents gardés, sans les caractères qu'un nom
///   de fichier n'admet pas, 80 caractères au plus, « (2) » en cas de doublon.
///
/// Les documents ouverts depuis Fichiers ne sont jamais déplacés ni renommés.
enum RangementDocuments {

    /// Le dossier du jour : `md Viewer/Importés/AAAA/MM/JJ` dans iCloud Drive, sinon dans les
    /// documents de l'app. ⚠️ Ne pas appeler sur le fil principal : la première demande du conteneur
    /// iCloud peut attendre.
    static func dossier(pour date: Date = Date()) -> URL {
        let racine = FileManager.default.url(forUbiquityContainerIdentifier: SynchroICloud.conteneur)?
            .appendingPathComponent("Documents", isDirectory: true)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return racine.appendingPathComponent("Importés", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", c.year ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", c.month ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", c.day ?? 0), isDirectory: true)
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
    static func ecrire(_ markdown: String, titre: String) throws -> URL {
        let dossier = dossier()
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
}
