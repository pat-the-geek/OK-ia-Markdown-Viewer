import Foundation
import FoundationModels
import NaturalLanguage

// Option Analytic (1.4) — ce qu'Apple Intelligence rédige à l'import, quand l'utilisateur le
// demande : le texte que demandent les commentaires de relecture, et un rapport d'analyse du
// document à la manière de fornews.
//
// ⛔ Uniquement `SystemLanguageModel.default`, le modèle de l'appareil — jamais Private Cloud
// Compute (décision de Patrick du 25/10/2026) : le document ne quitte pas l'appareil.
// ⛔ Le texte de l'auteur n'est jamais remplacé : ce qui est rédigé s'ajoute, marqué comme tel.

/// Le modèle de l'appareil, un appel par section, une session jetable à chaque fois — comme le
/// moteur de fornews : le modèle ne voit qu'une consigne et sa matière, sans mémoire de l'appel
/// précédent.
enum MoteurRedaction {
    static var disponible: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// La consigne en instructions, la matière en invite, coupée à ce que la fenêtre admet
    /// (`BudgetContexteLLM`, de fornews). nil sur échec, délai dépassé ou refus des garde-fous :
    /// une section qui échoue est absente, jamais comblée.
    static func rediger(consigne: String, matiere: String, motsAttendus: Int = 220) async -> String? {
        let budget = BudgetContexteLLM.budgetEntree(motsReponseAttendus: motsAttendus, instructions: consigne)
        let m = String(matiere.prefix(budget))
        guard !m.isEmpty, budget > 200 else { return nil }
        let brut = try? await avecDelaiMaxFond(120) {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: consigne)
            return try await session.respond(to: m).content
        }
        guard var t = brut?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        // « RIEN » : la section n'a pas lieu d'être, le modèle le dit (règle de fornews).
        if t.trimmingCharacters(in: .punctuationCharacters).uppercased() == "RIEN" { return nil }
        t = t.replacingOccurrences(of: "\\s*\\bRIEN\\.?\\s*$", with: "", options: .regularExpression)
        t = NettoyageRapport.sansTics(NettoyageRapport.sansRedite(NettoyageRapport.sansMarques(t)))
        return sansInventions(t, matiere: m)
    }

    /// ⛔ Une phrase qui avance un nombre ou une année absents de la matière part — les contrôles de
    /// fornews (`nombresAbsents`, `anneesInventees`) : une interdiction énoncée dans la consigne
    /// n'est jamais une interdiction tenue (essai du 25/10 : « entre 2005 et 2020 », sur un passage
    /// qui ne datait rien). Plus rien ne reste : la section est absente.
    static func sansInventions(_ texte: String, matiere: String) -> String? {
        var paragraphes: [String] = []
        for p in texte.components(separatedBy: "\n\n") {
            let decoupe = NLTokenizer(unit: .sentence)
            decoupe.string = p
            let phrases = decoupe.tokens(for: p.startIndex..<p.endIndex).map { String(p[$0]) }
            let gardees = phrases.filter {
                NettoyageRapport.nombresAbsents($0, dans: matiere).isEmpty
                    && NettoyageRapport.anneesInventees($0, dans: matiere).isEmpty
            }
            let r = gardees.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !r.isEmpty { paragraphes.append(r) }
        }
        return paragraphes.isEmpty ? nil : paragraphes.joined(separator: "\n\n")
    }

    /// La langue d'un texte (code à deux lettres), le français à défaut.
    static func langue(_ texte: String) -> String {
        let r = NLLanguageRecognizer()
        r.processString(String(texte.prefix(4000)))
        let code = r.dominantLanguage?.rawValue ?? "fr"
        return ["fr", "en", "de", "es", "it"].contains(code) ? code : "fr"
    }
}

// MARK: - Les commentaires comme consignes

enum RedactionConsignes {

    /// La consigne, écrite pour md Viewer sur le modèle de celles de fornews : une tâche, ses
    /// interdits, la langue en dernier.
    static func consigne(langue: String) -> String {
        """
        Tu aides l'auteur d'un document, en \(ConsignesAnalyste.nomLangue(langue)). Un relecteur a laissé un commentaire sur un passage.
        Rédige le texte que ce commentaire demande : UN paragraphe, à insérer après le passage, dans le ton du document.
        ⛔ Tout nom propre, chiffre et date doit figurer dans le passage ou le commentaire : n'en invente aucun. S'il faut un chiffre qu'on n'a pas, écris [à compléter].
        ⛔ Rends le paragraphe seul : ni titre, ni guillemets, ni commentaire sur ta tâche.
        ⛔ Si le commentaire ne demande aucun texte (une question, un accord, une remarque de forme), réponds seulement : RIEN.
        \(ConsignesAnalyste.styleSansTics)
        """ + ConsignesAnalyste.ordreDeLangue(langue)
    }

    static func matiere(_ c: ConsigneImport) -> String {
        var m = ""
        if let s = c.section, !s.isEmpty { m += "Partie : \(s)\n" }
        m += "Passage :\n\(c.passage)\n\nCommentaire"
        m += c.auteur.isEmpty ? "" : " de \(c.auteur)"
        return m + " :\n\(c.commentaire)"
    }

    /// Les textes rédigés, par numéro de consigne ; un commentaire sans réponse n'y est pas.
    static func rediger(_ consignes: [ConsigneImport], langue: String,
                        suivi: SuiviImport?) async -> [Int: String] {
        var r: [Int: String] = [:]
        let consigne = consigne(langue: langue)
        for (i, c) in consignes.enumerated() {
            if Task.isCancelled { break }
            await suivi?(AvancementImport(etape: tr("Commentaires"), fait: i, total: consignes.count,
                                          dernier: c.commentaire))
            if let t = await MoteurRedaction.rediger(consigne: consigne, matiere: matiere(c), motsAttendus: 160) {
                r[c.numero] = t
            }
        }
        return r
    }

    /// Les marques remplacées par le texte rédigé, dans un encadré qui dit d'où il vient ; les
    /// autres retirées.
    static func appliquer(_ markdown: String, consignes: [ConsigneImport], redactions: [Int: String]) -> String {
        var md = markdown
        for c in consignes {
            let marque = ConsigneImport.marque(c.numero)
            guard let texte = redactions[c.numero] else {
                md = md.replacingOccurrences(of: "\n\n" + marque, with: "").replacingOccurrences(of: marque, with: "")
                continue
            }
            let qui = c.auteur.isEmpty ? tr("d’après un commentaire") : tr("d’après le commentaire de %@", c.auteur)
            var encadre = ["> [!ia] " + tr("Rédigé par Apple Intelligence, %@", qui),
                           "> *« \(MarkdownImport.echapper(c.commentaire)) »*", ">"]
            encadre += texte.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }
            md = md.replacingOccurrences(of: marque, with: encadre.joined(separator: "\n"))
        }
        return md
    }

    /// Les marques retirées, sans rien rédiger.
    static func retirer(_ markdown: String, consignes: [ConsigneImport]) -> String {
        appliquer(markdown, consignes: consignes, redactions: [:])
    }
}

// MARK: - Le rapport d'analyse

/// Un rapport d'analyse du document importé, à la manière du rapport d'analyste de fornews
/// (`GenerateurRapportAnalyste`) : ses consignes, section par section (`ConsignesAnalyste`, copié
/// de fornews), et son nettoyage de la prose (`NettoyageRapport`). Ce qui diffère : la matière est
/// UN document, pas un corpus d'articles — les points clés suivent ses grandes parties, et il n'y a
/// ni sources à compter ni chronologie à découper.
enum RapportAnalyseImport {

    /// Une partie du document : son titre et ses paragraphes, en texte simple.
    struct Partie {
        var titre: String?
        var paragraphes: [String]
        var longueur: Int { paragraphes.reduce(0) { $0 + $1.count } }
    }

    /// Les parties du Markdown, coupées à ses titres jusqu'au troisième niveau : un PDF range
    /// souvent ses vraies parties en `###`, sous un ou deux grands titres.
    static func parties(_ markdown: String) -> [Partie] {
        var r: [Partie] = [Partie(titre: nil, paragraphes: [])]
        var corps = markdown
        if let m = corps.range(of: "^---\\n[\\s\\S]*?\\n---\\n", options: .regularExpression) { corps.removeSubrange(m) }
        corps = corps.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        var paragraphe: [String] = []
        func fermer() {
            let p = paragraphe.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if p.count > 1 { r[r.count - 1].paragraphes.append(p) }
            paragraphe = []
        }
        for ligne in corps.components(separatedBy: "\n") {
            let l = ligne.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.range(of: "^-{3,}$", options: .regularExpression) != nil { fermer(); continue }
            // Définitions de référence (images) et de notes : pas du texte.
            if l.range(of: "^\\[[^\\]]+\\]:", options: .regularExpression) != nil { fermer(); continue }
            if let t = l.range(of: "^#{1,3}\\s+", options: .regularExpression) {
                fermer()
                r.append(Partie(titre: texteSimple(String(l[t.upperBound...])), paragraphes: []))
                continue
            }
            if l.hasPrefix("|") {
                // Une rangée de tableau : ses cellules, séparées.
                if l.range(of: "^\\|[\\s:|-]+\\|$", options: .regularExpression) != nil { continue }
                paragraphe.append(l.split(separator: "|").map { texteSimple(String($0)) }.filter { !$0.isEmpty }.joined(separator: " ; "))
                continue
            }
            let t = texteSimple(l)
            if !t.isEmpty { paragraphe.append(t) }
        }
        fermer()
        return r.filter { !$0.paragraphes.isEmpty }
    }

    /// Le Markdown d'une ligne réduit à son texte.
    static func texteSimple(_ s: String) -> String {
        var t = s
        let regles: [(String, String)] = [
            ("!\\[[^\\]]*\\]\\[[^\\]]*\\]", ""), ("!\\[[^\\]]*\\]\\([^)]*\\)", ""),     // images
            ("\\[\\^[^\\]]+\\]", ""),                                                  // appels de note
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"), ("\\[([^\\]]+)\\]\\[[^\\]]*\\]", "$1"), // liens
            ("^#{1,6}\\s+", ""), ("^>\\s?", ""), ("^\\s*(?:[-*+]|\\d+[.)])\\s+", ""),    // titre, citation, puce
            ("(\\*\\*|__|~~|\\*|_)", ""), ("\\\\(.)", "$1"), ("<br>", " "),
        ]
        for (motif, par) in regles {
            t = t.replacingOccurrences(of: motif, with: par, options: .regularExpression)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// La matière d'un appel : les paragraphes, pris tour à tour dans chaque partie, jusqu'au budget
    /// — tout le document y est représenté, pas seulement son début.
    static func matiere(_ parties: [Partie], budget: Int) -> String {
        var r: [String] = []
        var taille = 0
        var rang = 0
        while true {
            var ajoute = false
            for p in parties where rang < p.paragraphes.count {
                let par = p.paragraphes[rang]
                guard taille + par.count + 2 <= budget else { return r.joined(separator: "\n\n") }
                r.append(par); taille += par.count + 2; ajoute = true
            }
            if !ajoute { break }
            rang += 1
        }
        return r.joined(separator: "\n\n")
    }

    /// La consigne de fornews pour une section, adaptée d'un mot : la matière est un document, pas
    /// une revue de presse.
    static func consigne(_ s: ConsignesAnalyste.Section, langue: String, sujet: String? = nil) -> String {
        ConsignesAnalyste.consigne(s, langue: langue, sujet: sujet)
            .replacingOccurrences(of: " de presse", with: "")
            .replacingOccurrences(of: " du corpus", with: " du document")
    }

    /// Le titre lu sur la première ligne d'une section qui en a un ; le reste, le paragraphe.
    static func separerTitre(_ t: String) -> (String?, String) {
        var lignes = t.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lignes.count >= 2 else { return (nil, t) }
        var titre = lignes.removeFirst()
        titre = titre.replacingOccurrences(of: "^(#+\\s*|\\*\\*|Titre\\s*:\\s*|Title\\s*:\\s*)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:«»\"'"))
        guard titre.split(separator: " ").count <= 14 else { return (nil, t) }
        return (titre, lignes.joined(separator: "\n\n"))
    }

    /// Les intitulés du rapport, dans la langue du document.
    static func intitule(_ cle: String, _ langue: String) -> String {
        let table: [String: [String: String]] = [
            "resume": ["fr": "Résumé exécutif", "en": "Executive summary", "de": "Zusammenfassung", "es": "Resumen ejecutivo", "it": "Sintesi"],
            "points": ["fr": "Points clés", "en": "Key points", "de": "Kernpunkte", "es": "Puntos clave", "it": "Punti chiave"],
            "humain": ["fr": "Dimension humaine", "en": "Human dimension", "de": "Menschliche Dimension", "es": "Dimensión humana", "it": "Dimensione umana"],
            "perspectives": ["fr": "Perspectives", "en": "Outlook", "de": "Ausblick", "es": "Perspectivas", "it": "Prospettive"],
            "critiques": ["fr": "Voix critiques", "en": "Critical voices", "de": "Kritische Stimmen", "es": "Voces críticas", "it": "Voci critiche"],
            "avertissement": ["fr": "Rapport rédigé sur l’appareil par Apple Intelligence, à partir du seul document « %@ ». Il peut se tromper : relisez-le avant de vous en servir.",
                              "en": "Report written on device by Apple Intelligence, from the document “%@” alone. It can be wrong: review it before using it.",
                              "de": "Bericht, auf dem Gerät von Apple Intelligence verfasst, allein aus dem Dokument „%@“. Er kann irren: Prüfen Sie ihn vor der Verwendung.",
                              "es": "Informe redactado en el dispositivo por Apple Intelligence, a partir únicamente del documento «%@». Puede equivocarse: revíselo antes de usarlo.",
                              "it": "Rapporto redatto sul dispositivo da Apple Intelligence, a partire dal solo documento «%@». Può sbagliare: rileggetelo prima di usarlo."],
            "analyse": ["fr": "Analyse", "en": "Analysis", "de": "Analyse", "es": "Análisis", "it": "Analisi"],
        ]
        return table[cle]?[langue] ?? table[cle]?["fr"] ?? cle
    }

    /// Le rapport, en Markdown ; nil si le document est trop mince ou si rien n'a pu être rédigé.
    static func produire(markdown: String, titreDocument: String, nomSource: String,
                         suivi: SuiviImport?) async -> String? {
        let parts = parties(markdown)
        let tout = parts.flatMap(\.paragraphes).joined(separator: "\n")
        guard tout.count >= 400 else { return nil }
        let langue = MoteurRedaction.langue(tout)
        // Les aspects : les grandes parties du document, cinq au plus, dans leur ordre.
        let grandes = parts.enumerated().filter { $0.element.titre != nil && $0.element.longueur >= 300 }
            .sorted { $0.element.longueur > $1.element.longueur }.prefix(pointsVises)
            .sorted { $0.offset < $1.offset }.map(\.element)
        let total = 4 + max(1, grandes.count)
        var fait = 0
        func avancer(_ quoi: String) async {
            await suivi?(AvancementImport(etape: tr("Rapport d’analyse"), fait: fait, total: total, dernier: quoi))
            fait += 1
        }
        func rediger(_ s: ConsignesAnalyste.Section, sujet: String? = nil, matiere: String, mots: Int = 220) async -> String? {
            let c = consigne(s, langue: langue, sujet: sujet)
            let budget = BudgetContexteLLM.budgetEntree(motsReponseAttendus: mots, instructions: c)
            return await MoteurRedaction.rediger(consigne: c, matiere: String(matiere.prefix(budget)), motsAttendus: mots)
        }
        let globale = matiere(parts, budget: 9000)

        await avancer(intitule("resume", langue))
        guard let resume = await rediger(.resumeExecutif, matiere: globale, mots: 260) else { return nil }
        if Task.isCancelled { return nil }
        let titre = await rediger(.titre, matiere: resume, mots: 20)
            .map { $0.components(separatedBy: "\n").first ?? $0 }
            .map { $0.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " #*«»\"'.")) }
            // Un titre énonce une thèse : une énumération (« les modèles, les outils, les annonces… »)
            // ou une phrase trop longue n'en est pas un — on garde alors le titre du document.
            .flatMap { t in t.filter { $0 == "," }.count >= 2 || t.split(separator: " ").count > 14 ? nil : t }

        var points: [(String?, String)] = []
        if grandes.isEmpty {
            await avancer(intitule("points", langue))
            if let t = await rediger(.pointsCles, matiere: globale) { points.append(separerTitre(t)) }
        } else {
            for p in grandes {
                if Task.isCancelled { return nil }
                await avancer(p.titre ?? "")
                if let t = await rediger(.pointsCles, sujet: "« \(p.titre ?? "") »", matiere: matiere([p], budget: 9000)) {
                    var (titrePoint, texte) = separerTitre(t)
                    if titrePoint == nil { titrePoint = p.titre }
                    points.append((titrePoint, texte))
                }
            }
        }
        await avancer(intitule("humain", langue))
        let humain = await rediger(.dimensionHumaine, matiere: globale)
        await avancer(intitule("perspectives", langue))
        let perspective = await rediger(.perspectives, matiere: globale).map(separerTitre)
        await avancer(intitule("critiques", langue))
        let critiques = await rediger(.resonances, matiere: globale)
        if Task.isCancelled { return nil }

        let titreRapport = (titre?.isEmpty == false ? titre! : "\(intitule("analyse", langue)) — \(titreDocument)")
        var md = MarkdownImport.entete(titre: titreRapport, source: nomSource, genre: "rapport",
                                       extra: ["redige-par": "Apple Intelligence"])
        md += "\n\n# \(titreRapport)\n\n"
        md += "> [!ia] " + String(format: intitule("avertissement", langue), titreDocument) + "\n\n"
        md += "## \(intitule("resume", langue))\n\n\(resume)\n"
        if !points.isEmpty {
            md += "\n## \(intitule("points", langue))\n"
            for (t, texte) in points { md += (t.map { "\n### \($0)\n" } ?? "") + "\n\(texte)\n" }
        }
        if let humain { md += "\n## \(intitule("humain", langue))\n\n\(humain)\n" }
        if let (t, texte) = perspective {
            md += "\n## \(intitule("perspectives", langue))\n" + (t.map { "\n### \($0)\n" } ?? "") + "\n\(texte)\n"
        }
        if let critiques { md += "\n## \(intitule("critiques", langue))\n\n\(critiques)\n" }
        return md
    }

    /// Autant de points clés que fornews en vise.
    private static let pointsVises = 5
}
