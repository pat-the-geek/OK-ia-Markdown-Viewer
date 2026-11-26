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
        let francais = Localization.shared.code.hasPrefix("fr")
        Task {
            if let racine = await vault.racineHorsFil() {
                await Task.detached(priority: .utility) {
                    ecrire(racine: racine, rapports: rapports, entites: entites, francais: francais)
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

    nonisolated static func ecrire(racine: URL, rapports: [VaultReport], entites: [EntiteIndex], francais: Bool) {
        let acces = racine.startAccessingSecurityScopedResource()
        defer { if acces { racine.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default

        ecrireSiNotre(agents(francais: francais), a: racine.appendingPathComponent("AGENTS.md"))
        ecrireSiNotre(claude(francais: francais), a: racine.appendingPathComponent("CLAUDE.md"))

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
        ecrireSiChange(Data(index(fiches, francais: francais).utf8), a: cache.appendingPathComponent("index.md"))

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
            ecrireSiChange(Data(pageEntites(entites, francais: francais).utf8), a: cache.appendingPathComponent("entites.md"))
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

    nonisolated static func index(_ fiches: [Fiche], francais: Bool) -> String {
        var t = marque + "\n"
        t += francais
            ? "# Index du coffre\n\n\(fiches.count) documents, du plus récent au plus ancien. Écrit par md Viewer ; ne pas modifier.\n\n| Document | Titre | Date | Source | Étiquettes |\n|---|---|---|---|---|\n"
            : "# Vault index\n\n\(fiches.count) documents, newest first. Written by md Viewer; do not edit.\n\n| Document | Title | Date | Source | Tags |\n|---|---|---|---|---|\n"
        for f in fiches {
            let lien = "[\(cellule(f.chemin))](<../\(f.chemin)>)"
            t += "| \(lien) | \(cellule(f.titre)) | \(f.date ?? "") | \(cellule(f.source ?? "")) | \(cellule(f.etiquettes.joined(separator: ", "))) |\n"
        }
        return t
    }

    nonisolated static func pageEntites(_ entites: [EntiteIndex], francais: Bool) -> String {
        var t = marque + "\n"
        t += francais
            ? "# Les entités du coffre\n\nTrouvées par l'analyse du coffre de md Viewer, les plus présentes d'abord. Le détail, avec les documents, est dans `entites.json`.\n\n| Nom | Genre | Wikidata | Documents | Première | Dernière | Souvent avec |\n|---|---|---|---|---|---|---|\n"
            : "# Entities in the vault\n\nFound by md Viewer's vault analysis, most frequent first. The details, with the documents, are in `entites.json`.\n\n| Name | Kind | Wikidata | Documents | First | Last | Often with |\n|---|---|---|---|---|---|---|\n"
        for e in entites {
            t += "| \(cellule(e.nom)) | \(e.genre) | \(e.qid ?? "") | \(e.documents.count) | \(e.premiere) | \(e.derniere) | \(cellule(e.voisins.joined(separator: ", "))) |\n"
        }
        return t
    }

    nonisolated static func claude(francais: Bool) -> String {
        marque + "\n" + (francais
            ? "Les consignes pour ce coffre sont dans AGENTS.md :\n\n@AGENTS.md\n"
            : "The instructions for this vault are in AGENTS.md:\n\n@AGENTS.md\n")
    }

    nonisolated static func agents(francais: Bool) -> String {
        marque + "\n" + (francais ? agentsFR : agentsEN)
    }

    private static let agentsFR = """
        # Ce coffre, pour les assistants

        Ce dossier est un coffre de **md Viewer** (ok-ia.ch) : des documents Markdown. md Viewer a écrit ce
        fichier et le tient à jour. Pour y mettre vos propres consignes, retirez la première ligne : md Viewer
        ne le touchera plus.

        ## Où trouver quoi

        - `.mdviewer/index.md` : tous les documents, un par ligne, avec leur titre, leur date et leur source.
          Commencez par lui ; `index.json` en est la version pour les programmes.
        - `.mdviewer/entites.md` (après l'analyse du coffre) : les personnes, organisations, lieux… et les
          documents où ils apparaissent ; `entites.json` donne la liste des documents de chacun.
        - `coffre md viewer/AAAA/MM/` : les documents importés dans md Viewer (Word, PDF, PowerPoint, pages
          web…), rangés par année et par mois.
        - Les dossiers `rapports-…` : des rapports de fornews.ai. Les autres dossiers sont ceux de
          l'utilisateur.

        ## Lire un document

        - Un en-tête YAML facultatif entre deux lignes `---` : `titre` ou `title`, `date`, `source` ou `url`,
          `auteur`, `tags`.
        - Un diaporama : les diapositives sont séparées par une ligne `---` ; les commentaires HTML
          `<!-- … -->` d'une diapositive sont les notes de l'orateur.
        - Les blocs ```` ```mermaid ```` sont des diagrammes, ```` ```leaflet ```` des cartes ; `$…$` et
          `$$…$$` des formules en LaTeX.
        - Les rapports de fornews.ai ont une section « Entités » : des noms classés par genre, souvent
          reliés à Wikidata.
        - Un bloc `<!-- md-viewer-annotations … -->` à la fin d'un fichier garde les surlignages et les notes
          de l'utilisateur : ne le modifiez jamais et ne le recopiez pas.
        - Des images sont parfois intégrées en `data:` (base64) : vous pouvez les ignorer.

        ## Citer

        Citez chaque document par son chemin depuis la racine du coffre et son titre, par exemple :
        `coffre md viewer/2026/11/budget.md` — « Le budget 2027 ». N'avancez aucun fait, chiffre ou date
        qui ne soit dans un document.

        ## Écrire

        - Ne supprimez, ne déplacez et ne renommez aucun fichier sans que l'utilisateur le demande.
        - Un nouveau document va de préférence dans `coffre md viewer/AAAA/MM/`, avec un en-tête YAML
          (`titre`, `date`).
        - Ne modifiez pas le dossier `.mdviewer/` : md Viewer le réécrit.

        """

    private static let agentsEN = """
        # This vault, for assistants

        This folder is an **md Viewer** vault (ok-ia.ch): Markdown documents. md Viewer wrote this file and
        keeps it up to date. To put your own instructions here, remove the first line: md Viewer will not
        touch it again.

        ## Where to find what

        - `.mdviewer/index.md`: every document, one per line, with its title, date and source. Start there;
          `index.json` is the version for programs.
        - `.mdviewer/entites.md` (after the vault analysis): people, organizations, places… and the documents
          they appear in; `entites.json` lists each one's documents.
        - `coffre md viewer/YYYY/MM/`: documents imported into md Viewer (Word, PDF, PowerPoint, web
          pages…), filed by year and month.
        - `rapports-…` folders: reports from fornews.ai. Other folders are the user's own.

        ## Reading a document

        - An optional YAML header between two `---` lines: `titre` or `title`, `date`, `source` or `url`,
          `auteur` (author), `tags`.
        - A slideshow: slides are separated by a `---` line; the HTML comments `<!-- … -->` of a slide are
          the speaker notes.
        - ```` ```mermaid ```` blocks are diagrams, ```` ```leaflet ```` blocks are maps; `$…$` and `$$…$$`
          are LaTeX formulas.
        - fornews.ai reports have an "Entités" section: names grouped by kind, often linked to Wikidata.
        - A `<!-- md-viewer-annotations … -->` block at the end of a file holds the user's highlights and
          notes: never edit it and do not copy it.
        - Images are sometimes embedded as `data:` (base64): you can ignore them.

        ## Citing

        Cite each document by its path from the vault root and its title, for example:
        `coffre md viewer/2026/11/budget.md` — "Le budget 2027". State no fact, figure or date that is not
        in a document.

        ## Writing

        - Do not delete, move or rename any file unless the user asks.
        - A new document preferably goes in `coffre md viewer/YYYY/MM/`, with a YAML header (`titre`,
          `date`).
        - Do not edit the `.mdviewer/` folder: md Viewer rewrites it.

        """
}

private extension JSONEncoder {
    static var lisible: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
