// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsFeatures/Explorer/RapportObsidian.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : la composition du rapport d'un article à partir de ses données (`generer(donnees:)`), avec
// ses aides et ses libellés ; le reste du fichier lit le modèle SwiftData de fornews.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

enum RapportObsidian {
    /// Une entité (nom + type) — forme **Sendable** pour régénérer le rapport hors du `@Model`.
    struct EntiteRapport: Sendable { let nom: String; let type: TypeEntite }

    /// Un lieu géolocalisé (entité `loc`/`gpe` avec coordonnées) — pour la carte Leaflet du rapport.
    struct GeoPoint: Sendable, Equatable { let nom: String; let type: TypeEntite; let lat: Double; let lon: Double }

    /// Données d'article **Sendable** extraites du `@Model` (sur le MainActor) — permettent de
    /// (re)générer le rapport en arrière-plan (page complète + images) sans traverser un `@Model`.
    struct DonneesRapport: Sendable {
        let titre: String, source: String, url: String, dateStr: String, langueSource: String
        let imagePrincipale: String?
        let resumeMd: String
        let entites: [EntiteRapport]
        /// **Note personnelle** de l'utilisateur (§7.9), en Markdown. Elle ouvre le rapport, avant
        /// la matière collectée : c'est sa voix, et la seule partie du document qu'il a écrite.
        var note: String? = nil
        /// Lieux géolocalisés issus des **coordonnées stockées** sur les entités (enrichies par le Mac).
        var geo: [GeoPoint] = []
        /// Ce que la fiche de lecture ajoute (04/10/2026, maquette `docs/maquettes/fiche-article.html`) : le titre
        /// dans la langue de l'article, le logo du média, si le texte est traduit, et la longueur du texte
        /// original (pour savoir si le résumé rangé porte le texte entier ou seulement ses points clés).
        var titreOriginal: String? = nil
        var logoSource: String? = nil
        var traduit = false
        var longueurContenuOriginal = 0
    }

    /// Génère le rapport. `corpsComplet` : texte intégral de la page rechargée (sinon le résumé md).
    /// `imagesInline` : images de la page à **intégrer** dans le corps (intercalées). `diagramme` :
    /// corps Mermaid prêt (IA) ; sinon flowchart déterministe coloré.
    /// `carteDataURI` : carte des lieux (PNG en data-URI base64) intégrée comme image — portable,
    /// rendue hors-ligne partout (Obsidian / iA Writer / GitHub / PDF), sans plugin. `pointsGeo` :
    /// mêmes lieux pour un bloc **Leaflet** interactif (plugin Obsidian Leaflet). Les deux cohabitent
    /// sous une seule section « Carte des lieux » : l'image rend toujours, la carte interactive en plus.
    ///
    /// ⭐ **La fiche de lecture** (Patrick, 04/10/2026, maquette `docs/maquettes/fiche-article.html` validée) : sous le
    /// frontmatter, inchangé, le corps est composé par `FicheArticle` — grande image, en-tête, « En bref » (`resume` :
    /// le résumé rédigé au partage, déjà contrôlé ; sinon le chapeau rangé), « En chiffres » (`lots` : relevés par le
    /// modèle puis contrôlés contre le texte ; sinon relevés par le code seul), « Qui est cité », le schéma en
    /// figure, le texte avec sa lettrine et sa citation en exergue, la carte des lieux, « L'article d'origine ».
    /// ⛔ La section `## Entités` en liens `[[…]]` et le tableau de référence sont partis : la fiche doit se lire
    /// sans md Viewer ni Obsidian (« les documents doivent pouvoir être consultés par des personnes qui n'ont pas
    /// fornews »), et un tableau Markdown porte une ligne `|---|`.
    static func generer(donnees d: DonneesRapport, langue: String, diagramme: String? = nil,
                        corpsComplet: String? = nil, imagesInline: [String] = [],
                        pointsGeo: [GeoPoint]? = nil, carteDataURI: String? = nil,
                        resume: String? = nil, lots: [FicheArticle.Lot]? = nil) -> String {
        let L = labels(langue)
        let parType = Dictionary(grouping: d.entites) { $0.type }

        // ── Frontmatter YAML ───────────────────────────────────────────────────────────────────
        var tags = [Self.slugTag(L.tagBase)]
        for t in TypeEntite.allCases where parType[t] != nil { tags.append(Self.slugTag(L.tag(t))) }
        var out = "---\n"
        out += "\(L.cleTitre): \"\(Self.echapYAML(d.titre))\"\n"
        if !d.source.isEmpty { out += "\(L.cleSource): \"\(Self.echapYAML(d.source))\"\n" }
        if !d.url.isEmpty { out += "\(L.cleURL): \(d.url)\n" }
        if !d.dateStr.isEmpty { out += "\(L.cleDate): \(d.dateStr)\n" }
        if !d.langueSource.isEmpty { out += "\(L.cleLangue): \(d.langueSource)\n" }
        out += "\(L.cleTags): [\(tags.joined(separator: ", "))]\n"
        out += "---\n\n"

        // ⚠️ **Chaque image UNE SEULE FOIS dans le document.** L'image principale figure presque
        // toujours aussi dans `imagesInline` (c'est la même og:image que le collecteur a rangée avec
        // les autres) : sans cette mémoire, le rapport s'ouvrait sur une photo qu'il ré-affichait
        // trois paragraphes plus bas. Clé normalisée (hôte + chemin) parce que le CDN sert la même
        // photo sous plusieurs tailles — cf. `CleImage`.
        var imagesMontrees = Set<String>()
        if let image = d.imagePrincipale { imagesMontrees.insert(CleImage.cle(image)) }
        let imagesUniques = CleImage.dedupliquer(imagesInline, deja: &imagesMontrees)

        // ── Carte des lieux : image PNG **portable** (rend partout, sans plugin) + bloc **Leaflet**
        //    interactif (plugin Obsidian Leaflet) — sous une seule section. Points résolus (réseau)
        //    fournis par l'appelant en priorité ; sinon coordonnées stockées (`d.geo`).
        let geo = (pointsGeo ?? d.geo).filter { $0.lat.isFinite && $0.lon.isFinite }

        // ── Diagramme Mermaid : version IA fournie, sinon flowchart déterministe coloré ─────────
        let diagIA = (diagramme?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let corpsDiag = diagIA ?? Self.flowchartDeterministe(titre: d.titre, parType: parType, L: L)

        let entree = FicheArticle.Entree(
            texte: FicheArticle.texte(d, corpsComplet: corpsComplet), resume: resume, lots: lots,
            diagramme: corpsDiag, diagrammeDeterministe: diagIA == nil, imagesInline: imagesUniques,
            carteDataURI: carteDataURI, blocLeaflet: Self.blocLeaflet(geo),
            sectionLieux: L.sectionLieux, sectionNote: L.sectionNote)
        out += FicheArticle.corps(d, entree, langue: langue)

        // La signature et l'avertissement IA, à la fin de chaque document généré (04/10/2026).
        return AvertissementIA.ajouter(out, langue: langue)
    }

    /// Retire la 1ʳᵉ ligne du corps si elle reprend le titre (heading ou texte) → évite le doublon
    /// avec le H1 du rapport. Comparaison tolérante (sans dièses, guillemets, accents ni casse).
    static func retirerTitreEnTete(_ corps: String, titre: String) -> String {
        func norm(_ s: String) -> String {
            s.replacingOccurrences(of: "[#*_\"'«»‘’“”]", with: "", options: .regularExpression)
                .folding(options: .diacriticInsensitive, locale: nil).lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        let cible = norm(titre)
        guard !cible.isEmpty else { return corps }
        var lignes = corps.components(separatedBy: "\n")
        while let f = lignes.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lignes.removeFirst() }
        if let f = lignes.first, norm(f) == cible {
            lignes.removeFirst()
            while let g = lignes.first, g.trimmingCharacters(in: .whitespaces).isEmpty { lignes.removeFirst() }
        }
        return lignes.joined(separator: "\n")
    }

    /// Bloc **Leaflet** (plugin Obsidian) des lieux géolocalisés : markers + lien `[[…]]` vers la note
    /// d'entité, centrés sur le barycentre, zoom adapté à l'étendue. `nil` si aucun point. Renvoie le
    /// **seul bloc de code** (sans titre de section : l'appelant l'émet sous « Carte des lieux », avec
    /// l'image PNG). Sans le plugin, Obsidian affiche simplement le bloc en code — le rapport reste lisible.
    static func blocLeaflet(_ points: [GeoPoint]) -> String? {
        // ⚠️ ÉMETTEUR DÉPLACÉ dans `CarteLeaflet` (FornewsServices) : le générateur de dossiers
        // vit plus bas dans la pile et doit produire la MÊME carte. Ce qui reste ici n'est que
        // la traduction du type local.
        CarteLeaflet.bloc(points.map {
            CarteLeaflet.Point(nom: $0.nom, type: $0.type, lat: $0.lat, lon: $0.lon)
        })
    }

    private static func nomsUniques(_ entites: [EntiteRapport]) -> [String] {
        var vus = Set<String>(); var res: [String] = []
        for e in entites {
            let v = e.nom.trimmingCharacters(in: .whitespaces)
            guard !v.isEmpty, vus.insert(v.lowercased()).inserted else { continue }
            res.append(v)
        }
        return res
    }

    /// Construit un **flowchart déterministe coloré** : nœud article au sommet, relié à ses entités
    /// (max 4 par type, ~12 au total), arêtes labellisées par type, nœuds colorés par `classDef`.
    private static func flowchartDeterministe(titre: String, parType: [TypeEntite: [EntiteRapport]], L: Labels) -> String? {
        var noeuds = ["  ART[\"\(nettoyerNoeud(titre, max: 48))\"]"]
        var aretes: [String] = []
        var parClasse: [String: [String]] = [:]
        var i = 0
        for t in TypeEntite.allCases {
            guard let liste = parType[t] else { continue }
            for n in nomsUniques(liste).prefix(4) {
                guard i < 12 else { break }
                let id = "N\(i)"; i += 1
                noeuds.append("  \(id)[\"\(nettoyerNoeud(n, max: 30))\"]")
                aretes.append("  ART -->|\(nettoyerNoeud(L.tag(t), max: 18))| \(id)")
                parClasse[t.rawValue, default: []].append(id)
            }
        }
        guard i > 0 else { return nil }
        var l = ["flowchart TD"] + noeuds + aretes
        l.append("  classDef art fill:#e8a33d,stroke:#b9791f,color:#1a1a1a;")
        for cls in parClasse.keys.sorted() { l.append("  classDef \(cls) \(couleurClasse(cls));") }
        l.append("  class ART art;")
        for cls in parClasse.keys.sorted() { l.append("  class \(parClasse[cls]!.joined(separator: ",")) \(cls);") }
        return l.joined(separator: "\n")
    }

    private static func couleurClasse(_ rawType: String) -> String {
        switch rawType {
        case "person":  return "fill:#f7c6e0,stroke:#c2557f,color:#222"
        case "org":     return "fill:#cfe3f7,stroke:#3f78b0,color:#222"
        case "gpe":     return "fill:#d8f0d8,stroke:#4a9a4a,color:#222"
        case "loc":     return "fill:#e6f7d8,stroke:#6aa83f,color:#222"
        case "product": return "fill:#efe0fa,stroke:#8a5cc2,color:#222"
        case "event":   return "fill:#fce3cf,stroke:#c2774a,color:#222"
        case "work":    return "fill:#f7eccf,stroke:#b09a3f,color:#222"
        default:        return "fill:#ececec,stroke:#999,color:#222"
        }
    }

    /// Valide/normalise un corps Mermaid **généré par IA** : retire d'éventuelles barrières ``` puis
    /// applique une validation **par type de diagramme** (chacun a sa structure minimale propre — une
    /// `timeline` ou un `pie` n'ont pas d'arête `-->`). `nil` si invalide : l'appelant se rabat alors
    /// sur le flowchart déterministe, ce qui garantit toujours un diagramme rendu.
    static func validerDiagrammeIA(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {   // retire d'éventuelles barrières de code
            t = t.replacingOccurrences(of: "(?s)^```[a-zA-Z]*\\n?|```\\s*$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Le gras Markdown « ** » que l'IA insère parfois dans les libellés casse le parseur Mermaid.
        t = t.replacingOccurrences(of: "**", with: "")
        let bas = t.lowercased()
        // Lignes de contenu = tout sauf l'en-tête de type et une éventuelle ligne `title`.
        let lignesContenu = t.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .dropFirst()
            .filter { !$0.lowercased().hasPrefix("title") }

        if bas.hasPrefix("flowchart") || bas.hasPrefix("graph ") || bas.hasPrefix("graph\n") {
            // ⛔ **Une arête ne suffit PAS : il faut qu'elle relie deux choses DIFFÉRENTES.** Vu le
            // 10/09/2026 sur le corpus réel, deux fois de suite : le modèle rendait
            // « graph TD / Elon Musk --> Elon Musk ». C'est du Mermaid valide, ça s'affiche, et ça
            // n'apprend rien — une flèche d'un sujet vers lui-même occupe la place d'une carte des
            // acteurs et laisse croire qu'on en a une.
            return flowchartPropre(t)
        }
        if bas.hasPrefix("sequencediagram") {
            return (t.contains("->>") || t.contains("-->>") || t.contains("->")) ? t : nil
        }
        if bas.hasPrefix("mindmap") {
            // Mermaid mindmap est TRÈS fragile : parenthèses/crochets dans un libellé, indentation
            // incohérente → erreur de syntaxe. On le RECONSTRUIT proprement (libellés nettoyés via
            // `nettoyerNoeud`, indentation normalisée) au lieu de renvoyer le texte IA brut.
            return mindmapPropre(t)
        }
        if bas.hasPrefix("timeline") {
            return lignesContenu.filter { $0.contains(":") }.count >= 2 ? t : nil   // ≥ 2 « période : évènement »
        }
        if bas.hasPrefix("pie") {
            let ns = t as NSString
            let re = try? NSRegularExpression(pattern: "\"[^\"]+\"\\s*:\\s*[0-9]")  // ≥ 1 « "libellé" : nombre »
            return (re?.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) != nil) ? t : nil
        }
        if bas.hasPrefix("classdiagram") {
            return (t.contains("class ") || t.contains("--")) ? t : nil
        }
        // ⭐ **`xychart-beta`** — demandé par le prompt de rapport d'analyste (10/09/2026) pour les
        //    séries chiffrées. Il était REJETÉ jusqu'ici faute d'être reconnu : un diagramme
        //    parfaitement valide retombait sur le flowchart déterministe, sans que rien ne le dise.
        //
        // ⚠️ Sa structure minimale n'est pas une arête mais une SÉRIE : `line [1, 2, 3]` ou
        //    `bar [1, 2, 3]`. Sans elle, le bloc se rend vide — pire qu'absent, parce qu'il occupe
        //    la place d'un diagramme et laisse croire à une donnée.
        if bas.hasPrefix("xychart") {
            let ns = t as NSString
            let re = try? NSRegularExpression(pattern: "(?i)\\b(line|bar)\\s*\\[[^\\]]*[0-9][^\\]]*\\]")
            return (re?.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) != nil) ? t : nil
        }
        return nil
    }

    /// Reconstruit un **mindmap Mermaid garanti valide** à partir d'une sortie IA approximative : les
    /// libellés sont nettoyés (`nettoyerNoeud` retire `()[]{}` etc. qui cassent le parseur mindmap) et
    /// l'indentation est normalisée par niveau (chaque largeur d'indent distincte → un niveau). La
    /// racine (1ʳᵉ ligne de contenu) devient `root((…))`. `nil` (→ flowchart déterministe) si moins de
    /// deux nœuds exploitables.
    /// **Reconstruit un flowchart au lieu de faire confiance au texte de l'IA.**
    ///
    /// ⛔ Défaut vu par Patrick le 10/09/2026, capture à l'appui : « Syntax error in text,
    /// mermaid version 11.15.0 » à la place de la cartographie. Le modèle écrivait
    /// « Elon Musk --> Alex Gibney » — **un identifiant de nœud ne peut pas contenir d'espace**.
    /// Le validateur ne regardait que la présence d'une flèche, donc il laissait passer.
    ///
    /// ⭐ Même parti que `mindmapPropre`, et pour la même raison : sur une syntaxe fragile, valider
    /// le texte de l'IA revient à espérer qu'il soit correct. On le RÉÉCRIT — identifiants
    /// synthétiques `N1`, `N2`…, libellés entre guillemets, apostrophes et crochets neutralisés.
    ///
    /// ⚠️ Rend `nil` si, après réécriture, aucune arête ne relie deux libellés DIFFÉRENTS : une
    /// flèche d'un sujet vers lui-même occupe la place d'une carte des acteurs et laisse croire
    /// qu'on en a une.
    static func flowchartPropre(_ t: String) -> String? {
        let lignes = t.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let entete = lignes.first else { return nil }

        // Les nœuds d'une ligne, dans l'ordre : « A[x] --> B[y] --> C » en donne trois, donc deux arêtes.
        // ⚠️ Un libellé d'arête « -->|texte| » collerait au nœud de droite : on le retire.
        func cotes(_ ligne: String) -> (sep: String, noeuds: [String])? {
            guard let sep = ["-->", "---"].first(where: { ligne.contains($0) }) else { return nil }
            return (sep, ligne.components(separatedBy: sep).map { cote in
                var c = cote.trimmingCharacters(in: .whitespaces)
                if c.hasPrefix("|"), let fin = c.dropFirst().firstIndex(of: "|") {
                    c = String(c[c.index(after: fin)...]).trimmingCharacters(in: .whitespaces)
                }
                return c
            })
        }

        // ⭐ **Le nom que l'IA donne à un nœud** (« B » dans « B[21,95 dollars] »), relevé sur TOUTES les lignes,
        // déclarations seules comprises. ⛔ Vu le 06/10/2026 sur une fiche réelle : le modèle écrivait
        // « A[Tarif initial] --> B[21,95 dollars] » puis rappelait le nœud par « B » tout court — qui devenait un
        // nœud nommé « B », relié à rien de ce qu'il voulait dire.
        var libellesIA: [String: String] = [:]
        for ligne in lignes.dropFirst() {
            for c in cotes(ligne)?.noeuds ?? [ligne] {
                guard let d = c.firstIndex(where: { "[({".contains($0) }) else { continue }
                let id = c[..<d].trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
                let libelle = libelleNoeud(c)
                if !libelle.isEmpty, libellesIA[id] == nil { libellesIA[id] = libelle }
            }
        }

        var ids: [String: String] = [:]      // libellé plié → identifiant
        var declarations: [String] = []
        var aretes: [String] = []

        func identifiant(_ brut: String) -> String? {
            let c = brut.trimmingCharacters(in: .whitespaces)
            let libelle = libellesIA[c] ?? libelleNoeud(c)   // un nœud déjà nommé, rappelé par son seul identifiant
            guard !libelle.isEmpty else { return nil }
            let cle = libelle.lowercased()
            if let deja = ids[cle] { return deja }
            let id = "N\(ids.count + 1)"
            ids[cle] = id
            declarations.append("    \(id)[\"\(libelle)\"]")
            return id
        }

        for ligne in lignes.dropFirst() {
            guard let (sep, noeuds) = cotes(ligne), noeuds.count >= 2 else { continue }
            for k in 0..<(noeuds.count - 1) {
                guard let a = identifiant(noeuds[k]), let b = identifiant(noeuds[k + 1]), a != b else { continue }
                let arete = "    \(a) \(sep) \(b)"
                if !aretes.contains(arete) { aretes.append(arete) }
            }
        }
        guard !aretes.isEmpty else { return nil }
        return ([entete] + declarations + aretes).joined(separator: "\n")
    }

    /// Le libellé d'un nœud, qu'il soit écrit « A[Texte] », « A(Texte) » ou « Texte » tout court.
    static func libelleNoeud(_ brut: String) -> String {
        let c = brut.trimmingCharacters(in: .whitespaces)
        var texte = c
        if let d = c.firstIndex(where: { "[({".contains($0) }),
           let f = c.lastIndex(where: { "])}".contains($0) }), d < f {
            texte = String(c[c.index(after: d)..<f])
        }
        // ⛔ Les guillemets et les crochets casseraient le libellé qu'on va justement guillemeter.
        return nettoyerNoeud(texte, max: 40)
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "' "))
    }

    private static func mindmapPropre(_ t: String) -> String? {
        var lignes: [(indent: Int, texte: String)] = []
        for brut in t.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(brut)
            let trim = s.trimmingCharacters(in: .whitespaces)
            if trim.isEmpty || trim.lowercased() == "mindmap" { continue }
            let indent = s.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            let texte = nettoyerNoeud(trim, max: 40)
            guard !texte.isEmpty else { continue }
            lignes.append((indent, texte))
        }
        guard lignes.count >= 2 else { return nil }
        // Mappe chaque largeur d'indentation distincte à un niveau (0,1,2…) → hiérarchie préservée.
        let niveaux = Array(Set(lignes.map(\.indent))).sorted()
        var out = ["mindmap"]
        for (k, l) in lignes.enumerated() {
            let prof = (niveaux.firstIndex(of: l.indent) ?? 0) + 1
            let prefixe = String(repeating: "  ", count: prof)
            if k == 0 {
                // La racine vient de la syntaxe IA « root((Sujet)) » : nettoyerNoeud a retiré les
                // parenthèses mais laissé le mot-clé « root » → on le retire pour ne pas le dupliquer.
                var racine = l.texte
                if racine.lowercased() == "root" { racine = "" }
                else if racine.lowercased().hasPrefix("root ") { racine = String(racine.dropFirst(5)) }
                racine = racine.trimmingCharacters(in: .whitespaces)
                guard !racine.isEmpty else { return nil }
                out.append("\(prefixe)root((\(racine)))")
            } else {
                out.append("\(prefixe)\(l.texte)")
            }
        }
        return out.joined(separator: "\n")
    }

    /// Texte de nœud Mermaid : retire les caractères de syntaxe (`"[]{}()|#\``) et borne la longueur.
    static func nettoyerNoeud(_ s: String, max: Int) -> String {
        let t = s.replacingOccurrences(of: "[\\(\\)\\[\\]{}\"`|#]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return t.count > max ? String(t.prefix(max)) + "…" : t
    }

    static func echapYAML(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "'") }

    static func echapMD(_ s: String) -> String { s.replacingOccurrences(of: "]", with: ")") }

    /// Tag Obsidian : minuscules, sans accents, espaces → tirets.
    static func slugTag(_ s: String) -> String {
        let base = s.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        let autorise = base.map { ($0.isLetter || $0.isNumber) ? $0 : "-" }
        return String(autorise).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
    }

    struct Labels {
        let cleTitre, cleSource, cleURL, cleDate, cleLangue, cleTags: String
        let sectionEntites, sectionLieux, sectionCarte, sectionReference: String
        let sectionNote: String
        let refSource, refDate, refURL, refScore, tagBase: String
        let tagPerson, tagOrg, tagGpe, tagLoc, tagProduct, tagEvent, tagWork, tagDate, tagMoney, tagAutre: String
        let tagMaladie: String
        func tag(_ t: TypeEntite) -> String {
            switch t {
            case .person: return tagPerson; case .org: return tagOrg; case .gpe: return tagGpe
            case .loc: return tagLoc; case .product: return tagProduct; case .event: return tagEvent
            case .work: return tagWork; case .date: return tagDate; case .money: return tagMoney
            case .maladie: return tagMaladie; case .autre: return tagAutre
            }
        }
    }

    static func labels(_ langue: String) -> Labels {
        switch langue.prefix(2) {
        case "en": return Labels(cleTitre: "title", cleSource: "source", cleURL: "url", cleDate: "date", cleLangue: "language", cleTags: "tags",
                                 sectionEntites: "Entities", sectionLieux: "Map of places", sectionCarte: "Mind map", sectionReference: "Reference",
                                 sectionNote: "My note",
                                 refSource: "Source", refDate: "Date", refURL: "URL", refScore: "Credibility", tagBase: "news",
                                 tagPerson: "Person", tagOrg: "Organization", tagGpe: "Country/Region", tagLoc: "Place", tagProduct: "Product",
                                 tagEvent: "Event", tagWork: "Work", tagDate: "Date", tagMoney: "Amount", tagAutre: "Entity", tagMaladie: "Disease")
        case "es": return Labels(cleTitre: "titulo", cleSource: "fuente", cleURL: "url", cleDate: "fecha", cleLangue: "idioma", cleTags: "etiquetas",
                                 sectionEntites: "Entidades", sectionLieux: "Mapa de lugares", sectionCarte: "Mapa mental", sectionReference: "Referencia",
                                 sectionNote: "Mi nota",
                                 refSource: "Fuente", refDate: "Fecha", refURL: "URL", refScore: "Credibilidad", tagBase: "noticias",
                                 tagPerson: "Persona", tagOrg: "Organización", tagGpe: "País/Región", tagLoc: "Lugar", tagProduct: "Producto",
                                 tagEvent: "Evento", tagWork: "Obra", tagDate: "Fecha", tagMoney: "Importe", tagAutre: "Entidad", tagMaladie: "Enfermedad")
        case "de": return Labels(cleTitre: "titel", cleSource: "quelle", cleURL: "url", cleDate: "datum", cleLangue: "sprache", cleTags: "tags",
                                 sectionEntites: "Entitäten", sectionLieux: "Ortskarte", sectionCarte: "Mindmap", sectionReference: "Referenz",
                                 sectionNote: "Meine Notiz",
                                 refSource: "Quelle", refDate: "Datum", refURL: "URL", refScore: "Glaubwürdigkeit", tagBase: "nachrichten",
                                 tagPerson: "Person", tagOrg: "Organisation", tagGpe: "Land/Region", tagLoc: "Ort", tagProduct: "Produkt",
                                 tagEvent: "Ereignis", tagWork: "Werk", tagDate: "Datum", tagMoney: "Betrag", tagAutre: "Entität", tagMaladie: "Krankheit")
        case "it": return Labels(cleTitre: "titolo", cleSource: "fonte", cleURL: "url", cleDate: "data", cleLangue: "lingua", cleTags: "tag",
                                 sectionEntites: "Entità", sectionLieux: "Mappa dei luoghi", sectionCarte: "Mappa mentale", sectionReference: "Riferimento",
                                 sectionNote: "La mia nota",
                                 refSource: "Fonte", refDate: "Data", refURL: "URL", refScore: "Credibilità", tagBase: "attualità",
                                 tagPerson: "Persona", tagOrg: "Organizzazione", tagGpe: "Paese/Regione", tagLoc: "Luogo", tagProduct: "Prodotto",
                                 tagEvent: "Evento", tagWork: "Opera", tagDate: "Data", tagMoney: "Importo", tagAutre: "Entità", tagMaladie: "Malattia")
        default:   return Labels(cleTitre: "titre", cleSource: "source", cleURL: "url", cleDate: "date", cleLangue: "langue", cleTags: "tags",
                                 sectionEntites: "Entités", sectionLieux: "Carte des lieux", sectionCarte: "Carte mentale", sectionReference: "Référence",
                                 sectionNote: "Ma note",
                                 refSource: "Source", refDate: "Date", refURL: "URL", refScore: "Crédibilité", tagBase: "actualité",
                                 tagPerson: "Personne", tagOrg: "Organisation", tagGpe: "Pays/Région", tagLoc: "Lieu", tagProduct: "Produit",
                                 tagEvent: "Événement", tagWork: "Œuvre", tagDate: "Date", tagMoney: "Montant", tagAutre: "Entité", tagMaladie: "Maladie")
        }
    }
}
