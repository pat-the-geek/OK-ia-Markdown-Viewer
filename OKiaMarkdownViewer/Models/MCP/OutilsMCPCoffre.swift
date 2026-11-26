import Foundation

/// 1.6 — Les outils MCP du coffre, en lecture seule (TACHES-1.6.md, point B bis, lot 1).
///
/// Les conventions de fornews.ai Agence : des noms en anglais préfixés `mdviewer_` (un assistant
/// branché aussi sur fornews les distingue), des descriptions en français, des paramètres en
/// anglais. Chaque réponse cite le `path` (depuis la racine du coffre) et le `title` de chaque
/// document, pour qu'un assistant cite ses sources.
///
/// **Seuls les documents que le coffre liste se lisent** : un chemin qui n'y est pas (`..`, un
/// fichier caché, hors du coffre) est refusé. Aucun outil n'écrit, n'efface ni ne fait de requête
/// réseau ; aucun ne lance Apple Intelligence pour le compte d'un assistant.
@MainActor
enum OutilsMCPCoffre {

    static let presentation = """
        md Viewer — le coffre de documents Markdown de l'utilisateur, sur ce Mac. LECTURE SEULE : aucun outil \
        ne modifie, ne déplace ni ne supprime.

        Commencer par mdviewer_vault_info, puis mdviewer_search ou mdviewer_list_documents. Lire un long \
        document par sections : mdviewer_get_outline, puis mdviewer_get_document avec `section`.

        Citer chaque document par son `path` et son `title`. N'avancer aucun fait, chiffre ou date absent \
        des documents ; dire quand le coffre ne permet pas de répondre. Les entités (personnes, \
        organisations, lieux) viennent de l'analyse du coffre faite sur l'appareil ; leur identifiant \
        Wikidata (`qid`) est celui que donne aussi fornews.ai.
        """

    static let catalogue: [MCP.Outil] = [
        MCP.Outil("mdviewer_vault_info", "Le coffre",
                  "Le coffre : son nom, le nombre de documents, la dernière lecture, l'état de la recherche et de l'analyse des entités."),
        MCP.Outil("mdviewer_list_documents", "Lister les documents",
                  "Les documents du coffre, du plus récent au plus ancien, avec leur chemin, leur titre et leur date. Paginé par `cursor`.",
                  proprietes: ["folder": .texte("Ne garder que ce dossier (chemin depuis la racine du coffre, sous-dossiers compris)."),
                               "since": .texte("Date de modification minimale, AAAA-MM-JJ."),
                               "until": .texte("Date de modification maximale, AAAA-MM-JJ."),
                               "query": .texte("Mots à trouver dans le chemin ou le titre (sans casse ni accents)."),
                               "limit": .entier("Nombre de documents par page.", defaut: 50),
                               "cursor": .texte("La suite d'une page précédente (`next_cursor`).")]),
        MCP.Outil("mdviewer_search", "Chercher dans le coffre",
                  "Recherche plein texte dans tout le coffre : plusieurs mots (chacun doit y être), ou une expression entre guillemets ; sans casse ni accents. Rend des passages, avec leur document.",
                  proprietes: ["query": .texte("La recherche."),
                               "folder": .texte("Ne chercher que dans ce dossier."),
                               "limit": .entier("Nombre de documents au plus.", defaut: 20)],
                  requis: ["query"]),
        MCP.Outil("mdviewer_get_outline", "Plan d'un document",
                  "Le plan d'un document : ses titres, leur niveau, et la taille de chaque section en caractères.",
                  proprietes: ["path": .texte("Le chemin du document depuis la racine du coffre.")],
                  requis: ["path"]),
        MCP.Outil("mdviewer_get_document", "Lire un document",
                  "Un document en Markdown, l'en-tête YAML à part : entier, ou une section. Les images intégrées deviennent « [image : texte] », le bloc des annotations est retiré. Paginé par `cursor` au-delà de `max_chars`.",
                  proprietes: ["path": .texte("Le chemin du document depuis la racine du coffre."),
                               "section": .texte("Le titre d'une section (tel que le rend mdviewer_get_outline), ou son numéro."),
                               "include_notes": .booleen("Garder les commentaires HTML, dont les notes de l'orateur d'un diaporama (oui par défaut)."),
                               "max_chars": .entier("Taille d'une page.", defaut: 8000),
                               "cursor": .texte("La suite d'une page précédente (`next_cursor`).")],
                  requis: ["path"]),
        MCP.Outil("mdviewer_list_entities", "Les entités du coffre",
                  "Les personnes, organisations, lieux, produits… trouvés dans le coffre par l'analyse de md Viewer, les plus présents d'abord.",
                  proprietes: ["kind": .texte("person, org, gpe (pays, ville), loc, product, event, work…"),
                               "query": .texte("Mots à trouver dans le nom."),
                               "min_documents": .entier("Présentes dans au moins ce nombre de documents.", defaut: 1),
                               "limit": .entier("Nombre d'entités par page.", defaut: 50),
                               "cursor": .texte("La suite d'une page précédente (`next_cursor`).")]),
        MCP.Outil("mdviewer_get_entity", "Fiche d'une entité",
                  "Une entité : son genre, sa description, son identifiant Wikidata, sa première et sa dernière apparition, ses documents et les noms qui l'accompagnent le plus souvent.",
                  proprietes: ["name": .texte("Le nom de l'entité."),
                               "qid": .texte("Ou son identifiant Wikidata (Q…).")]),
    ]

    /// Exécute un outil ; rend le résultat MCP et le document lu (pour le journal).
    static func executer(_ nom: String, _ a: [String: MCP.Valeur]) async -> (Data, String?) {
        let vault = VaultStore.partage
        switch nom {
        case "mdviewer_vault_info": return (vaultInfo(vault), nil)
        case "mdviewer_list_documents": return (await listerDocuments(vault, a), nil)
        case "mdviewer_search": return (await chercher(vault, a), nil)
        // Le journal ne note que les documents vraiment lus : pas une demande refusée.
        case "mdviewer_get_outline":
            let chemin = a["path"]?.texteOuNil ?? ""
            let d = await plan(vault, chemin)
            return (d, resoudre(vault, chemin) != nil ? chemin : nil)
        case "mdviewer_get_document":
            let chemin = a["path"]?.texteOuNil ?? ""
            let d = await document(vault, a)
            return (d, resoudre(vault, chemin) != nil ? chemin : nil)
        case "mdviewer_list_entities": return (listerEntites(a), nil)
        case "mdviewer_get_entity": return (await entite(a), nil)
        default: return (MCP.erreurOutil("Outil inconnu : \(nom)"), nil)
        }
    }

    // MARK: - Le coffre

    private static func vaultInfo(_ vault: VaultStore) -> Data {
        var r: [String: Any] = [
            "name": vault.folderName ?? "",
            "documents": vault.reports.count,
            "in_icloud": vault.dansICloud,
            "network_share": vault.reseau,
            "unreachable": vault.injoignable,
            "truncated": vault.tronque,
            "read_only": true,
        ]
        if vault.folderName == nil { r["note"] = "Aucun coffre n'est choisi dans md Viewer." }
        let recherche: String
        switch RechercheCoffre.partage.etat {
        case .inactif: recherche = "pas encore lue (elle se lit au premier mdviewer_search)"
        case .lecture(let fait, let total): recherche = "en lecture : \(fait) / \(total)"
        case .pret: recherche = "prête"
        }
        r["search_index"] = recherche
        r["entities"] = AnalyseCoffre.partage.entites.count
        if AnalyseCoffre.partage.entites.isEmpty {
            r["entities_note"] = "L'analyse du coffre n'a pas été faite : elle se lance dans md Viewer (Analyse du coffre)."
        }
        return MCP.contenu(r)
    }

    private static func chemin(_ r: VaultReport) -> String { r.subfolder.isEmpty ? r.name : r.subfolder + "/" + r.name }

    private static func jour(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func dateDe(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    private static func plier(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func dansDossier(_ r: VaultReport, _ dossier: String?) -> Bool {
        guard let d = dossier?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")), !d.isEmpty else { return true }
        return r.subfolder == d || r.subfolder.hasPrefix(d + "/")
    }

    private static func listerDocuments(_ vault: VaultStore, _ a: [String: MCP.Valeur]) async -> Data {
        let depuis = dateDe(a["since"]?.texteOuNil)
        let jusqua = dateDe(a["until"]?.texteOuNil).map { $0.addingTimeInterval(86_400) }
        let requete = a["query"]?.texteOuNil.map(plier)
        let limite = min(max(a["limit"]?.entierOuNil ?? 50, 1), 200)
        let debut = max(Int(a["cursor"]?.texteOuNil ?? "") ?? 0, 0)
        let choisis = vault.reports.filter { r in
            dansDossier(r, a["folder"]?.texteOuNil)
                && (depuis.map { r.modified >= $0 } ?? true)
                && (jusqua.map { r.modified < $0 } ?? true)
        }
        // Les titres viennent de l'en-tête de chaque document de la page.
        let racine = await vault.racineHorsFil()
        let candidats = Array(choisis.dropFirst(debut))
        var page: [[String: Any]] = []
        var lus = 0
        for r in candidats {
            lus += 1
            let c = chemin(r)
            let fiche = await Task.detached { () -> CoffreExplique.Fiche in
                var f = CoffreExplique.Fiche(chemin: c, titre: (r.name as NSString).deletingPathExtension,
                                             date: nil, source: nil, etiquettes: [], modifie: 0)
                if r.downloaded, let racine, let texte = lireDebut(racine, c) { CoffreExplique.lireEntete(texte, dans: &f) }
                return f
            }.value
            if let requete, !plier(c + " " + fiche.titre).contains(requete) { continue }
            var d: [String: Any] = ["path": c, "title": fiche.titre, "modified": jour(r.modified)]
            if let date = fiche.date { d["date"] = date }
            if let s = fiche.source { d["source"] = s }
            if !fiche.etiquettes.isEmpty { d["tags"] = fiche.etiquettes }
            if !r.downloaded { d["note"] = "encore dans iCloud, pas téléchargé sur ce Mac" }
            page.append(d)
            if page.count >= limite { break }
        }
        var r: [String: Any] = ["documents": page, "total_matching_dates": choisis.count]
        if debut + lus < choisis.count { r["next_cursor"] = String(debut + lus) }
        return MCP.contenu(r)
    }

    /// Le titre d'un document : son en-tête, sinon son premier titre, sinon son nom.
    private static func titre(_ r: VaultReport, racine: URL?) async -> String {
        let c = chemin(r)
        return await Task.detached { () -> String in
            var f = CoffreExplique.Fiche(chemin: c, titre: (r.name as NSString).deletingPathExtension,
                                         date: nil, source: nil, etiquettes: [], modifie: 0)
            if r.downloaded, let racine, let texte = lireDebut(racine, c) { CoffreExplique.lireEntete(texte, dans: &f) }
            return f.titre
        }.value
    }

    // MARK: - La recherche

    private static func chercher(_ vault: VaultStore, _ a: [String: MCP.Valeur]) async -> Data {
        guard let requete = a["query"]?.texteOuNil, !requete.trimmingCharacters(in: .whitespaces).isEmpty else {
            return MCP.erreurOutil("Paramètre « query » manquant.")
        }
        let recherche = RechercheCoffre.partage
        if recherche.etat != .pret || recherche.documents.isEmpty {
            recherche.actualiser()
            // Le premier passage lit tout le coffre : on l'attend, une minute au plus.
            for _ in 0..<240 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if recherche.etat == .pret { break }
            }
        }
        let limite = min(max(a["limit"]?.entierOuNil ?? 20, 1), 100)
        let dossier = a["folder"]?.texteOuNil
        let parId = Dictionary(vault.reports.map { ("coffre:" + $0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let docs = Array(recherche.documents.values).filter { $0.source == .coffre }
        let resultats = await Task.detached { RechercheCoffre.chercher(requete, dans: docs) }.value
        var page: [[String: Any]] = []
        let racine = await vault.racineHorsFil()
        for res in resultats {
            guard let r = parId[res.id], dansDossier(r, dossier) else { continue }
            page.append(["path": chemin(r), "title": await titre(r, racine: racine), "date": jour(res.date),
                         "occurrences": res.occurrences, "excerpt": res.extrait])
            if page.count >= limite { break }
        }
        var r: [String: Any] = ["query": requete, "results": page]
        if case .lecture(let fait, let total) = recherche.etat {
            r["note"] = "L'index de recherche est encore en lecture (\(fait) / \(total)) : des documents peuvent manquer."
        }
        if page.isEmpty { r["note"] = (r["note"] as? String) ?? "Aucun document ne contient cette recherche." }
        return MCP.contenu(r)
    }

    // MARK: - Lire un document

    /// Le document, s'il est dans la liste du coffre : jamais un autre fichier.
    private static func resoudre(_ vault: VaultStore, _ brut: String) -> VaultReport? {
        let c = brut.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !c.isEmpty, !c.split(separator: "/").contains("..") else { return nil }
        return vault.reports.first { chemin($0) == c }
    }

    nonisolated private static func lireDebut(_ racine: URL, _ chemin: String) -> String? {
        let acces = racine.startAccessingSecurityScopedResource()
        defer { if acces { racine.stopAccessingSecurityScopedResource() } }
        guard let h = try? FileHandle(forReadingFrom: racine.appendingPathComponent(chemin)) else { return nil }
        defer { try? h.close() }
        return (try? h.read(upToCount: 16_384)).map { String(decoding: $0, as: UTF8.self) }
    }

    nonisolated private static func lireTout(_ racine: URL, _ chemin: String) -> String? {
        let acces = racine.startAccessingSecurityScopedResource()
        defer { if acces { racine.stopAccessingSecurityScopedResource() } }
        var erreur: NSError?
        var texte: String?
        NSFileCoordinator().coordinate(readingItemAt: racine.appendingPathComponent(chemin), options: [], error: &erreur) { u in
            texte = try? String(contentsOf: u, encoding: .utf8)
        }
        return texte
    }

    private static func texteDocument(_ vault: VaultStore, _ brut: String) async -> (VaultReport, String)? {
        guard let r = resoudre(vault, brut), r.downloaded, let racine = await vault.racineHorsFil() else { return nil }
        let c = chemin(r)
        guard let texte = await Task.detached(operation: { lireTout(racine, c) }).value else { return nil }
        return (r, AnnotationsIntegrees.sans(texte))
    }

    private static func introuvable(_ vault: VaultStore, _ brut: String) -> Data {
        if let r = resoudre(vault, brut), !r.downloaded {
            return MCP.erreurOutil("« \(brut) » est encore dans iCloud, pas téléchargé sur ce Mac.")
        }
        return MCP.erreurOutil("« \(brut) » n'est pas un document du coffre. Les chemins se lisent dans mdviewer_list_documents ou mdviewer_search.")
    }

    /// L'en-tête YAML à part, et le corps.
    nonisolated static func separerEntete(_ texte: String) -> (entete: [String: String], corps: String) {
        guard texte.hasPrefix("---\n") || texte.hasPrefix("---\r\n"),
              let fin = texte.dropFirst(4).range(of: "\n---") else { return ([:], texte) }
        var entete: [String: String] = [:]
        for ligne in texte[texte.index(texte.startIndex, offsetBy: 4)..<fin.lowerBound].split(whereSeparator: \.isNewline) {
            guard let deux = ligne.firstIndex(of: ":") else { continue }
            let cle = ligne[..<deux].trimmingCharacters(in: .whitespaces)
            let valeur = ligne[ligne.index(after: deux)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'\t"))
            if !cle.isEmpty { entete[cle] = valeur }
        }
        var corps = String(texte[fin.upperBound...])
        if let saut = corps.firstIndex(of: "\n") { corps = String(corps[corps.index(after: saut)...]) } else { corps = "" }
        return (entete, corps)
    }

    /// Les titres hors des blocs de code : (niveau, titre, début de la section).
    nonisolated static func titres(_ corps: String) -> [(niveau: Int, titre: String, debut: String.Index)] {
        var liste: [(Int, String, String.Index)] = []
        var dansBloc = false
        var i = corps.startIndex
        while i < corps.endIndex {
            let finLigne = corps[i...].firstIndex(of: "\n") ?? corps.endIndex
            let ligne = corps[i..<finLigne]
            let l = ligne.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("```") || l.hasPrefix("~~~") { dansBloc.toggle() }
            else if !dansBloc, l.hasPrefix("#") {
                let niveau = l.prefix(while: { $0 == "#" }).count
                let reste = l.dropFirst(niveau)
                if niveau <= 6, reste.hasPrefix(" ") {
                    liste.append((niveau, reste.trimmingCharacters(in: .whitespaces), i))
                }
            }
            i = finLigne < corps.endIndex ? corps.index(after: finLigne) : corps.endIndex
        }
        return liste
    }

    private static func plan(_ vault: VaultStore, _ brut: String) async -> Data {
        guard let (r, texte) = await texteDocument(vault, brut) else { return introuvable(vault, brut) }
        let corps = separerEntete(texte).corps
        let t = titres(corps)
        var sections: [[String: Any]] = []
        for (k, x) in t.enumerated() {
            // Une section va jusqu'au titre suivant de même niveau ou plus haut.
            let fin = t[(k + 1)...].first { $0.niveau <= x.niveau }?.debut ?? corps.endIndex
            sections.append(["index": k + 1, "level": x.niveau, "title": x.titre,
                             "chars": corps.distance(from: x.debut, to: fin)])
        }
        let diapositives = corps.components(separatedBy: "\n---\n").count
        var res: [String: Any] = ["path": chemin(r), "chars": corps.count, "sections": sections]
        if diapositives > 1 { res["slides"] = diapositives }
        return MCP.contenu(res)
    }

    nonisolated private static func nettoyer(_ texte: String, notes: Bool) -> String {
        var t = texte
        t = t.replacingOccurrences(of: #"!\[([^\]]*)\]\(data:[^)]*\)"#, with: "[image : $1]", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<img[^>]*src=["']data:[^"']*["'][^>]*>"#, with: "[image]", options: .regularExpression)
        if !notes {
            t = t.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
        }
        return t
    }

    private static func document(_ vault: VaultStore, _ a: [String: MCP.Valeur]) async -> Data {
        let brut = a["path"]?.texteOuNil ?? ""
        guard let (r, texte) = await texteDocument(vault, brut) else { return introuvable(vault, brut) }
        let (entete, corpsEntier) = separerEntete(texte)
        var corps = corpsEntier
        var sectionTrouvee: String?
        if let s = a["section"]?.texteOuNil ?? a["section"]?.entierOuNil.map(String.init), !s.isEmpty {
            let t = titres(corpsEntier)
            let k: Int? = Int(s).flatMap { $0 >= 1 && $0 <= t.count ? $0 - 1 : nil }
                ?? t.firstIndex { plier($0.titre) == plier(s) }
                ?? t.firstIndex { plier($0.titre).contains(plier(s)) }
            guard let k else {
                return MCP.erreurOutil("Section « \(s) » introuvable dans \(chemin(r)). Le plan se lit avec mdviewer_get_outline.")
            }
            let fin = t[(k + 1)...].first { $0.niveau <= t[k].niveau }?.debut ?? corpsEntier.endIndex
            corps = String(corpsEntier[t[k].debut..<fin])
            sectionTrouvee = t[k].titre
        }
        corps = nettoyer(corps, notes: a["include_notes"]?.booleenOuNil ?? true)
        let maxChars = min(max(a["max_chars"]?.entierOuNil ?? 8000, 500), 50_000)
        let debut = min(max(Int(a["cursor"]?.texteOuNil ?? "") ?? 0, 0), corps.count)
        let i0 = corps.index(corps.startIndex, offsetBy: debut)
        let i1 = corps.index(i0, offsetBy: maxChars, limitedBy: corps.endIndex) ?? corps.endIndex
        var res: [String: Any] = ["path": chemin(r), "modified": jour(r.modified), "content": String(corps[i0..<i1]),
                                  "chars": corps.count]
        let titre = entete["titre"] ?? entete["title"] ?? titres(corpsEntier).first?.titre
        if let titre { res["title"] = titre }
        if !entete.isEmpty { res["front_matter"] = entete }
        if let sectionTrouvee { res["section"] = sectionTrouvee }
        if i1 < corps.endIndex { res["next_cursor"] = String(corps.distance(from: corps.startIndex, to: i1)) }
        return MCP.contenu(res)
    }

    // MARK: - Les entités

    private static func sansAnalyse() -> Data {
        MCP.erreurOutil("L'analyse du coffre n'a pas encore été faite. L'utilisateur la lance dans md Viewer (Analyse du coffre) ; elle se calcule sur l'appareil.")
    }

    private static func listerEntites(_ a: [String: MCP.Valeur]) -> Data {
        let analyse = AnalyseCoffre.partage
        guard !analyse.entites.isEmpty else { return sansAnalyse() }
        let genre = a["kind"]?.texteOuNil?.lowercased()
        let requete = a["query"]?.texteOuNil.map(plier)
        let minimum = max(a["min_documents"]?.entierOuNil ?? 1, 1)
        let limite = min(max(a["limit"]?.entierOuNil ?? 50, 1), 200)
        let debut = max(Int(a["cursor"]?.texteOuNil ?? "") ?? 0, 0)
        let choisies = analyse.entites.filter { e in
            (genre.map { e.entite.type.rawValue == $0 } ?? true)
                && (requete.map { plier(e.entite.nom).contains($0) } ?? true)
                && e.presences.count >= minimum
        }
        let page = choisies.dropFirst(debut).prefix(limite).map { e -> [String: Any] in
            var d: [String: Any] = ["name": e.entite.nom, "kind": e.entite.type.rawValue,
                                    "documents": e.presences.count, "mentions": e.mentions,
                                    "first": jour(e.premiere), "last": jour(e.derniere)]
            if let q = e.entite.qid { d["qid"] = q }
            if let desc = e.entite.description { d["description"] = desc }
            return d
        }
        var r: [String: Any] = ["entities": Array(page), "total": choisies.count]
        if debut + page.count < choisies.count { r["next_cursor"] = String(debut + page.count) }
        return MCP.contenu(r)
    }

    private static func entite(_ a: [String: MCP.Valeur]) async -> Data {
        let analyse = AnalyseCoffre.partage
        guard !analyse.entites.isEmpty else { return sansAnalyse() }
        let trouvee: AnalyseCoffre.EntiteCoffre?
        if let q = a["qid"]?.texteOuNil, !q.isEmpty {
            trouvee = analyse.entites.first { $0.entite.qid?.caseInsensitiveCompare(q) == .orderedSame }
        } else if let n = a["name"]?.texteOuNil, !n.isEmpty {
            trouvee = analyse.entite(nommee: n)
                ?? analyse.entites.first { plier($0.entite.nom) == plier(n) }
        } else {
            return MCP.erreurOutil("Donner « name » ou « qid ».")
        }
        guard let e = trouvee else { return MCP.erreurOutil("Cette entité n'apparaît pas dans le coffre.") }
        let parId = Dictionary(VaultStore.partage.reports.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let racine = await VaultStore.partage.racineHorsFil()
        var documents: [[String: Any]] = []
        for p in e.presences.prefix(100) {
            var d: [String: Any] = ["title": (p.nom as NSString).deletingPathExtension, "date": jour(p.date), "mentions": p.mentions]
            if let r = parId[p.document] {
                d["path"] = chemin(r)
                d["title"] = await titre(r, racine: racine)
            } else {
                d["note"] = "document analysé hors du coffre"
            }
            documents.append(d)
        }
        var r: [String: Any] = ["name": e.entite.nom, "kind": e.entite.type.rawValue,
                                "first": jour(e.premiere), "last": jour(e.derniere),
                                "documents": documents, "mentions": e.mentions,
                                "often_with": analyse.compagnons(de: e, limite: 10).map { ["name": $0.0.entite.nom, "shared_documents": $0.1] }]
        if let q = e.entite.qid { r["qid"] = q }
        if let d = e.entite.description { r["description"] = d }
        if e.entite.aDesCoordonnees, let lat = e.entite.latitude, let lon = e.entite.longitude {
            r["coordinates"] = ["lat": lat, "lon": lon]
        }
        return MCP.contenu(r)
    }
}
