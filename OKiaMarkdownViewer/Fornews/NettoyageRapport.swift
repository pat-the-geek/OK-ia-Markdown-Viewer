// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsPipeline/GenerateurRapportAnalyste.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// EXTRAIT : le nettoyage de la prose (tics d'ouverture, marques recopiées, redites) et les contrôles
// des nombres et des années inventés, pour ce qu'md Viewer rédige à l'import ; le reste du
// générateur tient au pipeline d'articles.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

enum NettoyageRapport {
    // MARK: - Les tics de langage

    /// **Ouvertures de phrase qui n'apportent rien** — les tics que le modèle embarqué pose en tête
    /// de phrase. Retirées par le CODE (Patrick, 03/10/2026) : la phrase garde son contenu, perd
    /// son préambule. ⚠️ Seulement en OUVERTURE : au milieu d'une phrase, retirer « crucial »
    /// casserait la syntaxe ; ceux-là restent l'affaire de la consigne.
    static let ouverturesTics = [
        "il est important de noter que ", "il est important de souligner que ",
        "il convient de noter que ", "il convient de souligner que ", "il est intéressant de noter que ",
        "il est crucial de noter que ", "force est de constater que ", "notons que ",
        "en conclusion, ", "en définitive, ", "en somme, ", "en fin de compte, ", "au final, ",
        "dans un monde où ", "à l'heure où ",
        "it is important to note that ", "it is worth noting that ", "in conclusion, ", "ultimately, ",
        "es ist wichtig zu beachten, dass ", "zusammenfassend ",
        "es importante señalar que ", "en conclusión, ",
        "è importante notare che ", "in conclusione, ",
        // ⛔ La SUCCESSION affirmée sans date (03/10/2026, quatrième rapport réel : « La situation a
        // commencé par… », « Ensuite… » enchaînaient des faits de juin et de septembre à l'envers).
        // Retirée en ouverture ; l'ordre, c'est le déroulé daté qui le donne.
        "ensuite, ", "puis, ", "par la suite, ", "dans un premier temps, ", "dans un second temps, ",
        "then, ", "subsequently, ", "afterwards, ", "danach ", "anschließend ", "luego, ",
        "después, ", "poi, ", "successivamente, ",
    ]

    /// **Les marques des extraits recopiées par le modèle** (« [allégation] », « [publié le …] ») sont retirées de la
    /// prose (03/10/2026, essais sur d'autres dossiers : « …à New York. [allégation] selon un message vocal, … » publié
    /// tel quel). La phrase qui commençait par la marque reprend sa majuscule.
    public static func sansMarques(_ texte: String) -> String {
        let motif = "\\s*\\[(?:all[ée]gation|allegation|alegaci[óo]n|accusa|behauptung|publi[ée] le|published|ver[öo]ffentlicht am|publicado el|pubblicato il)[^\\]]*\\]"
        var t = texte.replacingOccurrences(of: motif, with: "", options: [.regularExpression, .caseInsensitive])
            // Un marqueur de titre égaré (« §TITEL§ ») et les crochets vidés de leur date (« [] »).
            .replacingOccurrences(of: "§[^§\\s]{2,12}§\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[\\s*\\]\\s*", with: "", options: .regularExpression)
        // Début de texte ou de phrase suivi d'une minuscule : la majuscule.
        if let re = try? NSRegularExpression(pattern: "(^|[.!?]\\s+)(\\p{Ll})", options: [.anchorsMatchLines]) {
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
                guard let r = Range(m.range(at: 2), in: t) else { continue }
                t.replaceSubrange(r, with: t[r].uppercased())
            }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func sansTics(_ texte: String) -> String {
        var t = texte
        for tic in ouverturesTics {
            // Début de texte ou début de phrase (après « . », « ! », « ? » ou un saut de ligne).
            let motif = "(^|[.!?]\\s+|\\n)" + NSRegularExpression.escapedPattern(for: tic) + "(\\p{L})"
            guard let re = try? NSRegularExpression(pattern: motif, options: [.caseInsensitive]) else { continue }
            while let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let avant = Range(m.range(at: 1), in: t), let lettre = Range(m.range(at: 2), in: t),
                  let tout = Range(m.range, in: t) {
                t.replaceSubrange(tout, with: String(t[avant]) + t[lettre].uppercased())
            }
        }
        return t
    }

    /// **Retire les paragraphes que le modèle a répétés mot pour mot.**
    ///
    /// ⛔ Défaut mesuré le 10/09/2026 sur le rapport « Elon Musk » : la section « intelligence
    /// artificielle » rendait **quatre fois le même paragraphe**, à la virgule près. Le modèle
    /// embarqué boucle quand la matière ne lui donne pas de quoi remplir la longueur demandée, et
    /// rien ne le rattrapait — le rapport paraissait quatre fois plus fourni qu'il ne l'était.
    ///
    /// ⚠️ **Comparaison sur le texte normalisé, pas brut** : la reprise diffère parfois d'une
    /// espace ou d'une majuscule. ⛔ Mais on garde le paragraphe D'ORIGINE, gras et ponctuation
    /// compris : la normalisation sert à RECONNAÎTRE, jamais à réécrire.
    ///
    /// 🔑 C'est la même famille que le défaut des chapitres en double du résumé d'article : un
    /// modèle qui n'a plus rien à dire se répète au lieu de s'arrêter.
    static func sansRedite(_ texte: String) -> String {
        var vus = Set<String>()
        let gardes = texte.components(separatedBy: "\n\n").filter { bloc in
            let cle = bloc.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " ")
            // Un bloc sans texte (ligne de séparation, blanc) n'est pas une redite : on le garde.
            guard cle.contains(where: { $0.isLetter }) else { return true }
            return vus.insert(cle).inserted
        }
        return gardes.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// **Les nombres en lettres**, dans les cinq langues. ⚠️ Sans « un », « deux » et leurs équivalents (articles,
    /// tournures courantes), ni « neuf » (l'adjectif) ni « cent » (« pour cent »).
    static let nombresEnLettres: [String: Int] = {
        let paires: [(String, Int)] = [
            ("trois", 3), ("quatre", 4), ("cinq", 5), ("six", 6), ("sept", 7), ("huit", 8), ("dix", 10), ("onze", 11),
            ("douze", 12), ("treize", 13), ("quatorze", 14), ("quinze", 15), ("seize", 16), ("vingt", 20), ("trente", 30),
            ("quarante", 40), ("cinquante", 50), ("soixante", 60), ("mille", 1000),
            ("three", 3), ("four", 4), ("five", 5), ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10), ("eleven", 11),
            ("twelve", 12), ("fifteen", 15), ("twenty", 20), ("thirty", 30), ("forty", 40), ("fifty", 50), ("hundred", 100),
            ("thousand", 1000),
            ("drei", 3), ("vier", 4), ("funf", 5), ("sechs", 6), ("sieben", 7), ("acht", 8), ("neun", 9), ("zehn", 10),
            ("elf", 11), ("zwolf", 12), ("zwanzig", 20), ("dreissig", 30), ("hundert", 100), ("tausend", 1000),
            ("tres", 3), ("cuatro", 4), ("cinco", 5), ("seis", 6), ("siete", 7), ("ocho", 8), ("nueve", 9), ("diez", 10),
            ("once", 11), ("doce", 12), ("quince", 15), ("veinte", 20), ("treinta", 30), ("cien", 100), ("mil", 1000),
            ("tre", 3), ("quattro", 4), ("cinque", 5), ("sette", 7), ("otto", 8), ("nove", 9), ("dieci", 10), ("undici", 11),
            ("dodici", 12), ("quindici", 15), ("venti", 20), ("trenta", 30), ("cento", 100)]
        return Dictionary(paires, uniquingKeysWith: { a, _ in a })
    }()

    /// **Les nombres d'une phrase absents de la matière**, en chiffres (« 2 000 » vaut « 2000 ») ou en lettres
    /// (« douze » vaut « 12 »). Rend ce qui manque, tel qu'écrit dans la phrase.
    static func nombresAbsents(_ phrase: String, dans matiere: String) -> [String] {
        func chiffres(_ t: String) -> [(brut: String, valeur: String)] {
            let motif = try! NSRegularExpression(pattern: "\\d+(?:[ \u{00A0}\u{202F}.,']\\d+)*")
            return motif.matches(in: t, range: NSRange(t.startIndex..., in: t)).compactMap { m in
                Range(m.range, in: t).map { r in
                    let brut = String(t[r])
                    return (brut, brut.filter(\.isNumber))
                }
            }
        }
        func mots(_ t: String) -> [String] {
            t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .replacingOccurrences(of: "ß", with: "ss")
                .split(whereSeparator: { !$0.isLetter }).map(String.init)
        }
        let motsMatiere = Set(mots(matiere))
        var valeurs = Set(chiffres(matiere).map(\.valeur))
        for m in motsMatiere { if let v = nombresEnLettres[m] { valeurs.insert(String(v)) } }
        var absents: [String] = []
        for c in chiffres(phrase) where !valeurs.contains(c.valeur) { absents.append(c.brut) }
        for m in mots(phrase) {
            guard let v = nombresEnLettres[m], !motsMatiere.contains(m), !valeurs.contains(String(v)) else { continue }
            absents.append(m)
        }
        return absents
    }

    /// **Les années que le texte cite et que la matière ne contient pas.**
    ///
    /// ⛔ Deux générations réelles consécutives ont inventé une date — « 10 octobre 2024 » puis
    /// « du 17 au 22 octobre 2024 » — sur un corpus qui ne porte que 2026. La consigne a été
    /// corrigée, mais ⚠️ **une interdiction énoncée n'est jamais une interdiction tenue** : c'est
    /// le code qui doit trancher.
    ///
    /// 🔑 On vérifie les ANNÉES et non les dates complètes : c'est ce qui rend le contrôle sûr. Une
    /// année est un jeton exact, présent ou absent, là où « 12 mars » se compare mal d'une langue et
    /// d'une tournure à l'autre. Les deux inventions observées portaient sur l'année.
    static func anneesInventees(_ texte: String, dans matiere: String) -> [String] {
        let motif = try! NSRegularExpression(pattern: "\\b(19|20)\\d{2}\\b")
        func annees(_ t: String) -> [String] {
            motif.matches(in: t, range: NSRange(t.startIndex..., in: t))
                 .compactMap { Range($0.range, in: t).map { r in String(t[r]) } }
        }
        let presentes = Set(annees(matiere))
        var vues = Set<String>()
        return annees(texte).filter { !presentes.contains($0) && vues.insert($0).inserted }
    }
}
