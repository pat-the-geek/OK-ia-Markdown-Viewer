import Foundation

/// 1.6 — Un coffre qui s'explique (pour tous, réglage coupé par défaut ; TACHES-1.6.md, point A).
///
/// Le coffre est déjà ce que Claude, Codex, Copilot ou Cursor lisent le mieux : un dossier de
/// fichiers Markdown. md Viewer y écrit ce qu'un assistant doit savoir pour s'y retrouver, et rien
/// d'autre ; c'est l'utilisateur qui ouvre le dossier dans l'assistant de son choix. md Viewer
/// n'envoie rien.
///
/// - `AGENTS.md` à la racine : la convention que lisent Codex, Copilot, Cursor, Gemini CLI… Le
///   rangement, l'en-tête YAML, les diaporamas et leurs notes, le bloc des annotations à ne pas
///   toucher, comment citer.
/// - `CLAUDE.md` : une ligne qui renvoie à `AGENTS.md` (Claude Code lit `@fichier`).
/// - `.mdviewer/index.md` (et `index.json`) : un document par ligne, avec son titre, sa date, sa
///   source. Dossier caché : la lecture du coffre l'ignore.
/// - `.mdviewer/entites.md` (et `.json`) : quand l'analyse du coffre (option Analytic) a été faite,
///   chaque entité, ses documents et ses voisins.
///
/// Un `AGENTS.md` ou un `CLAUDE.md` que l'utilisateur a écrit lui-même (sans la marque de la
/// première ligne) n'est jamais remplacé. Seuls les documents modifiés depuis la dernière fois sont
/// relus, et un fichier n'est réécrit que si son contenu change : pas de va-et-vient inutile dans
/// iCloud ou sur un partage.
enum CoffreExplique {
    static let cleReglage = "okia.coffre.explique"
    static let marque = "<!-- md-viewer:agents -->"
    static let dossier = ".mdviewer"
    /// Les fichiers de la racine qui s'adressent aux assistants : la lecture du coffre ne les
    /// montre pas comme des documents.
    static let fichiersRacine: Set<String> = ["AGENTS.md", "CLAUDE.md"]

    static var actif: Bool { UserDefaults.standard.bool(forKey: cleReglage) }

    /// Une ligne de l'index.
    struct Fiche: Codable, Sendable, Equatable {
        var chemin: String
        var titre: String
        var date: String?
        var source: String?
        var etiquettes: [String]
        var modifie: Double
    }

    /// Une entité du coffre, pour `entites.json`.
    struct EntiteIndex: Codable, Sendable {
        var nom: String
        var genre: String
        var qid: String?
        var description: String?
        var mentions: Int
        var premiere: String
        var derniere: String
        var documents: [String]
        var voisins: [String]
    }

    // MARK: - Mise à jour

    @MainActor private static var enCours = false
    @MainActor private static var encore = false

    /// Après une relecture du coffre, une analyse, ou quand l'utilisateur ouvre le réglage. Une mise
    /// à jour à la fois ; demandée pendant une autre, elle la suit.
    @MainActor static func mettreAJour(_ vault: VaultStore = .partage) {
        guard actif, !vault.reports.isEmpty else { return }
        if enCours { encore = true; return }
        enCours = true
        let rapports = vault.reports
        let entites = indexEntites(AnalyseCoffre.partage, documents: Set(rapports.map(\.id)))
        // La langue de l'app : AGENTS.md, CLAUDE.md et les index sont écrits dans celle de l'utilisateur.
        let langue = Localization.shared.code
        Task {
            if let racine = await vault.racineHorsFil() {
                await Task.detached(priority: .utility) {
                    ecrire(racine: racine, rapports: rapports, entites: entites, langue: langue)
                }.value
            }
            enCours = false
            if encore { encore = false; mettreAJour(vault) }
        }
    }

    /// Les entités de l'analyse, réduites aux documents de ce coffre : l'analyse compte aussi les
    /// documents analysés hors du coffre, et peut dater d'un autre coffre.
    @MainActor private static func indexEntites(_ analyse: AnalyseCoffre, documents: Set<String>) -> [EntiteIndex] {
        let jour = DateFormatter()
        jour.locale = Locale(identifier: "en_US_POSIX")
        jour.dateFormat = "yyyy-MM-dd"
        var liste: [EntiteIndex] = []
        for e in analyse.entites {
            let ici = e.presences.filter { documents.contains($0.document) }
            guard !ici.isEmpty else { continue }
            let dates = ici.map(\.date)
            liste.append(EntiteIndex(nom: e.entite.nom, genre: e.entite.type.rawValue, qid: e.entite.qid,
                                     description: e.entite.description, mentions: ici.reduce(0) { $0 + $1.mentions },
                                     premiere: jour.string(from: dates.min() ?? .distantPast),
                                     derniere: jour.string(from: dates.max() ?? .distantPast),
                                     documents: ici.map(\.document).map(cheminDocument),
                                     voisins: analyse.compagnons(de: e, limite: 6).map { $0.0.entite.nom }))
            if liste.count >= 500 { break }
        }
        return liste
    }

    /// `VaultReport.id` (« sous-dossier/nom », « /nom » à la racine) en chemin depuis la racine.
    nonisolated static func cheminDocument(_ id: String) -> String {
        id.hasPrefix("/") ? String(id.dropFirst()) : id
    }

    // MARK: - Écriture (hors du fil principal)

    nonisolated static func ecrire(racine: URL, rapports: [VaultReport], entites: [EntiteIndex], langue: String) {
        let acces = racine.startAccessingSecurityScopedResource()
        defer { if acces { racine.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default

        ecrireSiNotre(agents(langue: langue), a: racine.appendingPathComponent("AGENTS.md"))
        ecrireSiNotre(claude(langue: langue), a: racine.appendingPathComponent("CLAUDE.md"))

        let cache = racine.appendingPathComponent(dossier, isDirectory: true)
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)

        // L'index : la fiche gardée vaut tant que le document n'a pas changé.
        let urlJSON = cache.appendingPathComponent("index.json")
        let anciennes = (try? Data(contentsOf: urlJSON)).flatMap { try? JSONDecoder().decode([Fiche].self, from: $0) } ?? []
        var parChemin: [String: Fiche] = [:]
        for f in anciennes { parChemin[f.chemin] = f }
        let fin = Date().addingTimeInterval(90)
        var fiches: [Fiche] = []
        for r in rapports.prefix(5000) {
            let chemin = r.subfolder.isEmpty ? r.name : r.subfolder + "/" + r.name
            let modifie = r.modified.timeIntervalSince1970
            if let f = parChemin[chemin], f.modifie == modifie { fiches.append(f); continue }
            var f = Fiche(chemin: chemin, titre: (r.name as NSString).deletingPathExtension, date: nil, source: nil,
                          etiquettes: [], modifie: modifie)
            // Un document encore dans iCloud, ou la borne de durée passée (un partage lent) : son
            // nom seul, relu la fois suivante.
            if r.downloaded, Date() < fin, let debut = lireDebut(racine.appendingPathComponent(chemin)) {
                lireEntete(debut, dans: &f)
            } else {
                f.modifie = -1
            }
            fiches.append(f)
        }
        if fiches != anciennes, let d = try? JSONEncoder.lisible.encode(fiches) {
            ecrireSiChange(d, a: urlJSON)
        }
        ecrireSiChange(Data(index(fiches, langue: langue).utf8), a: cache.appendingPathComponent("index.md"))

        if entites.isEmpty {
            // Plus d'entités pour ce coffre : les anciens fichiers ne disent plus rien de juste.
            for nom in ["entites.json", "entites.md"] {
                let u = cache.appendingPathComponent(nom)
                if fm.fileExists(atPath: u.path) {
                    var erreur: NSError?
                    NSFileCoordinator().coordinate(writingItemAt: u, options: .forDeleting, error: &erreur) { try? fm.removeItem(at: $0) }
                }
            }
        } else {
            if let d = try? JSONEncoder.lisible.encode(entites) {
                ecrireSiChange(d, a: cache.appendingPathComponent("entites.json"))
            }
            ecrireSiChange(Data(pageEntites(entites, langue: langue).utf8), a: cache.appendingPathComponent("entites.md"))
        }
    }

    /// Les premiers 16 Ko d'un document : l'en-tête et le premier titre y sont.
    nonisolated private static func lireDebut(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 16_384) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    /// L'en-tête YAML (titre, date, source, étiquettes), sinon le premier titre.
    nonisolated static func lireEntete(_ texte: String, dans f: inout Fiche) {
        var corps = Substring(texte.hasPrefix("\u{FEFF}") ? String(texte.dropFirst()) : texte)
        var titre: String?
        if corps.hasPrefix("---\n") || corps.hasPrefix("---\r\n"),
           let fin = corps.dropFirst(4).range(of: "\n---") {
            let bloc = corps[corps.index(corps.startIndex, offsetBy: 4)..<fin.lowerBound]
            for ligne in bloc.split(whereSeparator: \.isNewline) {
                guard let deux = ligne.firstIndex(of: ":") else { continue }
                let cle = ligne[..<deux].trimmingCharacters(in: .whitespaces).lowercased()
                let valeur = ligne[ligne.index(after: deux)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'\t"))
                guard !valeur.isEmpty else { continue }
                switch cle {
                case "titre", "title": titre = titre ?? valeur
                case "date": f.date = f.date ?? String(valeur.prefix(10))
                case "source", "url": f.source = f.source ?? valeur
                case "tags", "etiquettes", "étiquettes":
                    f.etiquettes = valeur.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                        .split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'#")) }
                        .filter { !$0.isEmpty }
                default: break
                }
            }
            corps = corps[fin.upperBound...]
        }
        if titre == nil {
            var dansBloc = false
            for ligne in corps.split(whereSeparator: \.isNewline).prefix(200) {
                let l = ligne.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("```") || l.hasPrefix("~~~") { dansBloc.toggle(); continue }
                if !dansBloc, l.hasPrefix("# ") { titre = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces); break }
            }
        }
        if let titre, !titre.isEmpty { f.titre = titre }
    }

    /// N'écrit que si le fichier est absent ou porte notre marque : jamais celui de l'utilisateur.
    nonisolated private static func ecrireSiNotre(_ texte: String, a url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            guard let d = try? Data(contentsOf: url), String(decoding: d.prefix(200), as: UTF8.self).contains(marque) else { return }
        }
        ecrireSiChange(Data(texte.utf8), a: url)
    }

    /// Une écriture coordonnée (iCloud, autres apps), seulement si le contenu change.
    nonisolated private static func ecrireSiChange(_ donnees: Data, a url: URL) {
        if let ancien = try? Data(contentsOf: url), ancien == donnees { return }
        var erreur: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &erreur) { u in
            try? donnees.write(to: u, options: .atomic)
        }
    }

    // MARK: - Les textes

    nonisolated private static func cellule(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    nonisolated static func index(_ fiches: [Fiche], langue: String) -> String {
        let l = Textes.pour(langue)
        var t = marque + "\n"
        t += "# \(l.indexTitre)\n\n" + l.indexIntro.replacingOccurrences(of: "%d", with: String(fiches.count)) + "\n\n"
        t += "| " + l.indexColonnes.joined(separator: " | ") + " |\n|---|---|---|---|---|\n"
        for f in fiches {
            let lien = "[\(cellule(f.chemin))](<../\(f.chemin)>)"
            t += "| \(lien) | \(cellule(f.titre)) | \(f.date ?? "") | \(cellule(f.source ?? "")) | \(cellule(f.etiquettes.joined(separator: ", "))) |\n"
        }
        return t
    }

    nonisolated static func pageEntites(_ entites: [EntiteIndex], langue: String) -> String {
        let l = Textes.pour(langue)
        var t = marque + "\n"
        t += "# \(l.entitesTitre)\n\n\(l.entitesIntro)\n\n"
        t += "| " + l.entitesColonnes.joined(separator: " | ") + " |\n|---|---|---|---|---|---|---|\n"
        for e in entites {
            t += "| \(cellule(e.nom)) | \(e.genre) | \(e.qid ?? "") | \(e.documents.count) | \(e.premiere) | \(e.derniere) | \(cellule(e.voisins.joined(separator: ", "))) |\n"
        }
        return t
    }

    nonisolated static func claude(langue: String) -> String {
        marque + "\n" + Textes.pour(langue).claude + "\n\n@AGENTS.md\n"
    }

    nonisolated static func agents(langue: String) -> String {
        marque + "\n" + Textes.pour(langue).agents
    }
}

private extension JSONEncoder {
    static var lisible: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
