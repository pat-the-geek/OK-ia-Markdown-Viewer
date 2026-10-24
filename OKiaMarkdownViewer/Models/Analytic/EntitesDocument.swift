import Foundation
import NaturalLanguage

// Option Analytic (1.4) — les entités d'un document. Ce fichier ne touche ni au réseau ni à
// l'interface : il lit ce que le document donne (un rapport fornews en donne presque tout), puis
// détecte le reste avec l'algorithme de fornews (`NLTagger` et `FiltreEntitesNER`, copiés dans
// `Fornews/`). La résolution Wikidata, proposée et jamais imposée, vit dans `AnalyseEntites`.

/// Une entité du document, telle que l'option la montre.
struct EntiteDocument: Identifiable, Equatable, Codable, Sendable {
    /// Le nom plié (casse et accents ôtés) : deux mentions du même nom ne font qu'une entité.
    var id: String { EntiteDocument.cle(nom) }
    var nom: String
    var type: TypeEntite
    /// Le titre de genre que le rapport fornews lui donne (« Personnalités »), quand il y en a un.
    var genre: String?
    var origine: Origine
    /// Combien de fois le nom revient dans le texte : l'ordre de la liste, et de la résolution.
    var mentions: Int = 0
    var latitude: Double?
    var longitude: Double?
    /// Ce que Wikidata a appris, quand l'utilisateur l'a accepté.
    var qid: String?
    var description: String?
    var image: String?

    enum Origine: String, Codable, Sendable {
        /// Lue dans la section `## Entités` ou sur la carte d'un rapport fornews.
        case rapport
        /// Trouvée dans le texte par `NLTagger`.
        case detection
    }

    var aDesCoordonnees: Bool { latitude != nil && longitude != nil }

    static func cle(_ nom: String) -> String {
        nom.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Rapport fornews

/// Ce qu'un rapport fornews donne de lui-même : sa section `## Entités` (un `### genre` puis des
/// `- [[Nom]]`) et les marqueurs de ses cartes `leaflet` (`marker: icône,lat,long,[[Nom]]`). On ne
/// demande jamais à Wikidata ce que le document donne déjà.
enum LecteurRapportFornews {

    /// Les entités que le document déclare, avec les coordonnées de ses cartes. Un document qui n'est
    /// pas un rapport fornews rend une liste vide.
    static func lire(_ markdown: String) -> [EntiteDocument] {
        var entites: [EntiteDocument] = []
        var coordonnees: [String: (Double, Double)] = [:]
        var dansSection = false, genre: String?
        var cloture: String?          // la clôture du bloc de code ouvert (``` ou ~~~)
        var dansCarte = false

        for brute in markdown.components(separatedBy: .newlines) {
            let ligne = brute.trimmingCharacters(in: .whitespaces)
            if let c = cloture {
                if ligne.hasPrefix(c) { cloture = nil; dansCarte = false; continue }
                if dansCarte, let (nom, lat, lon) = marqueur(ligne) { coordonnees[EntiteDocument.cle(nom)] = (lat, lon) }
                continue
            }
            if ligne.hasPrefix("```") || ligne.hasPrefix("~~~") {
                cloture = String(ligne.prefix(3))
                dansCarte = ligne.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() == "leaflet"
                continue
            }
            if ligne.hasPrefix("## ") {
                dansSection = estTitreEntites(String(ligne.dropFirst(3)))
                genre = nil
                continue
            }
            guard dansSection else { continue }
            if ligne.hasPrefix("### ") {
                genre = String(ligne.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if let g = genre, let nom = lienWiki(ligne) {
                entites.append(EntiteDocument(nom: nom, type: typeDuGenre(g), genre: g, origine: .rapport))
            }
        }

        // Seul le contrôle de validité de fornews (`estValide`) : il écarte « 7 », un titre seul, un
        // terme générique. ⛔ Pas `filtrer` : il rectifie un extrait de texte brut, et coupait la
        // fin en minuscules d'un nom déjà propre — « Union européenne » devenait « Union », que
        // Wikidata rattachait ensuite à une ville de Caroline du Sud (essai du 25/10/2026).
        var resultat = entites.filter { FiltreEntitesNER.estValide(EntiteDetectee(valeur: $0.nom, type: $0.type)) }
        // Un lieu de la carte absent de la section reste un lieu du document.
        let nomsCarte = nomsDesMarqueurs(markdown)
        for (cle, _) in coordonnees where !resultat.contains(where: { $0.id == cle }) {
            if let nom = nomsCarte[cle] {
                resultat.append(EntiteDocument(nom: nom, type: .gpe, origine: .rapport))
            }
        }
        for i in resultat.indices {
            if let (lat, lon) = coordonnees[resultat[i].id] {
                resultat[i].latitude = lat
                resultat[i].longitude = lon
            }
        }
        return dedoublonner(resultat)
    }

    /// Le titre de la section d'entités, dans les cinq langues d'export de fornews — la même liste
    /// fermée que `isEntityHeading` dans render.js : « Sources » ou « Entités clés » ne comptent pas.
    static func estTitreEntites(_ titre: String) -> Bool {
        let a = plier(titre)
        return a.range(of: #"^(?:entit(?:es?|y|ies|a|at(?:en)?|aet(?:en)?)|entidad(?:es)?)$"#,
                       options: .regularExpression) != nil
    }

    /// Le type d'un genre de la section, d'après les libellés de fornews (`LibellesAnalyste`), dans
    /// ses cinq langues. Un genre inconnu (document écrit à la main) range ses entités en « Autres ».
    static func typeDuGenre(_ genre: String) -> TypeEntite {
        let g = plier(genre)
        func commence(_ prefixes: [String]) -> Bool { prefixes.contains { g.hasPrefix($0) } }
        if commence(["personnalit", "personne", "people", "person", "personalidad"]) { return .person }
        if commence(["organi"]) { return .org }
        if commence(["lieu", "place", "orte", "ort ", "lugar", "luogh", "luogo", "pays", "countr", "ville", "cit"]) { return .gpe }
        if commence(["produ", "oeuvre", "work"]) { return .product }
        if commence(["evenement", "event", "ereignis", "acontecimiento", "evento"]) { return .event }
        if commence(["sante", "health", "gesundheit", "salud", "salute", "maladie", "disease"]) { return .maladie }
        return .autre
    }

    /// `- [[Nom]]` ou `- [[Nom|libellé]]` → « Nom ».
    static func lienWiki(_ ligne: String) -> String? {
        guard let r = ligne.range(of: #"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]"#, options: .regularExpression) else { return nil }
        let interieur = ligne[r].dropFirst(2).dropLast(2)
        let nom = interieur.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
        let propre = nom.trimmingCharacters(in: .whitespaces)
        return propre.isEmpty ? nil : propre
    }

    /// `marker: default,48.59472,38.00083,[[Bakhmut]]` → (« Bakhmut », 48.59, 38.00).
    static func marqueur(_ ligne: String) -> (String, Double, Double)? {
        guard ligne.lowercased().hasPrefix("marker:") else { return nil }
        let champs = ligne.dropFirst(7).split(separator: ",", maxSplits: 3).map { $0.trimmingCharacters(in: .whitespaces) }
        guard champs.count == 4, let lat = Double(champs[1]), let lon = Double(champs[2]),
              CoordonneeTerrestre.estValide(latitude: lat, longitude: lon),
              let nom = lienWiki(champs[3]) ?? Optional(champs[3]).flatMap({ $0.isEmpty ? nil : $0 })
        else { return nil }
        return (nom, lat, lon)
    }

    private static func nomsDesMarqueurs(_ markdown: String) -> [String: String] {
        var noms: [String: String] = [:]
        for ligne in markdown.components(separatedBy: .newlines) {
            if let (nom, _, _) = marqueur(ligne.trimmingCharacters(in: .whitespaces)) { noms[EntiteDocument.cle(nom)] = nom }
        }
        return noms
    }

    static func plier(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "œ", with: "oe")
    }

    static func dedoublonner(_ entites: [EntiteDocument]) -> [EntiteDocument] {
        var vues = Set<String>()
        return entites.filter { vues.insert($0.id).inserted }
    }
}

// MARK: - Détection dans le texte

/// La détection de fornews (`NERNaturalLanguage`) appliquée au texte d'un document : `NLTagger`
/// pour les personnes, lieux et organisations, puis `FiltreEntitesNER`. Ni Apple Intelligence ni
/// réseau : elle marche sur tout appareil, hors ligne.
enum DetecteurEntites {

    /// fornews borne chaque passe de `NLTagger` à 20 000 caractères : l'appel est synchrone et ne
    /// s'interrompt pas. Un document plus long est lu par morceaux de cette taille.
    static let tailleMorceau = 20_000

    static func detecter(_ markdown: String, langue: String?) async -> [EntiteDocument] {
        let texte = TexteAnalysable.depuis(markdown)
        guard !texte.isEmpty else { return [] }
        let brutes: [EntiteDetectee] = await Task.detached(priority: .utility) {
            var vues = Set<String>()
            var resultat: [EntiteDetectee] = []
            for morceau in morceaux(texte) {
                let tagger = NLTagger(tagSchemes: [.nameType])
                tagger.string = morceau
                if let langue { tagger.setLanguage(NLLanguage(langue), range: morceau.startIndex..<morceau.endIndex) }
                tagger.enumerateTags(in: morceau.startIndex..<morceau.endIndex, unit: .word, scheme: .nameType,
                                     options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
                    guard let tag, let type = type(de: tag) else { return true }
                    let valeur = String(morceau[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !valeur.isEmpty else { return true }
                    if vues.insert("\(type.rawValue):\(valeur.lowercased())").inserted {
                        resultat.append(EntiteDetectee(valeur: valeur, type: type))
                    }
                    return true
                }
            }
            return resultat
        }.value
        let filtrees = FiltreEntitesNER.filtrer(brutes, texteSource: texte)
        return filtrees.map { EntiteDocument(nom: $0.valeur, type: $0.type, origine: .detection) }
    }

    /// La correspondance de `NERNaturalLanguage.map` dans fornews : `NLTagger` ne distingue pas un
    /// pays d'une ville, tout lieu devient `gpe`.
    static func type(de tag: NLTag) -> TypeEntite? {
        switch tag {
        case .personalName:     return .person
        case .placeName:        return .gpe
        case .organizationName: return .org
        default:                return nil
        }
    }

    /// Des morceaux d'au plus `tailleMorceau` caractères, coupés entre deux paragraphes.
    static func morceaux(_ texte: String) -> [String] {
        guard texte.count > tailleMorceau else { return [texte] }
        var resultat: [String] = [], courant = ""
        for paragraphe in texte.components(separatedBy: "\n\n") {
            if courant.count + paragraphe.count > tailleMorceau, !courant.isEmpty {
                resultat.append(courant); courant = ""
            }
            courant += (courant.isEmpty ? "" : "\n\n") + String(paragraphe.prefix(tailleMorceau))
        }
        if !courant.isEmpty { resultat.append(courant) }
        return resultat
    }

    /// Une entité détectée qui n'est qu'une partie, en mots entiers, d'un nom plus long du document
    /// (« Poutine » de « Vladimir Poutine », « Union » d'« Union européenne ») n'est pas une entité
    /// de plus : le nom complet la reprend, avec ses mentions. Sans cela, Wikidata cherchait
    /// « Union » seul et rendait une ville de Caroline du Sud.
    static func absorberFormesCourtes(_ entites: [EntiteDocument]) -> [EntiteDocument] {
        var resultat = entites
        var retirees = Set<String>()
        for courte in entites where courte.origine == .detection {
            let mots = courte.id.split(separator: " ")
            let longue = entites.firstIndex { l in
                l.id != courte.id && l.id.count > courte.id.count && !retirees.contains(l.id)
                    && contientMots(l.id.split(separator: " "), mots)
            }
            guard let i = longue else { continue }
            retirees.insert(courte.id)
            if let j = resultat.firstIndex(where: { $0.id == entites[i].id }) {
                resultat[j].mentions = max(resultat[j].mentions, courte.mentions)
            }
        }
        return resultat.filter { !retirees.contains($0.id) }
    }

    private static func contientMots(_ long: [Substring], _ court: [Substring]) -> Bool {
        guard !court.isEmpty, court.count < long.count else { return false }
        return (0...(long.count - court.count)).contains { Array(long[$0..<$0 + court.count]) == court }
    }

    /// Le nombre de mentions de chaque entité dans le texte, en mots entiers, sans casse ni accents.
    static func compterMentions(_ entites: inout [EntiteDocument], dans markdown: String) {
        let texte = EntiteDocument.cle(TexteAnalysable.depuis(markdown))
        for i in entites.indices {
            let motif = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: entites[i].id) + "(?![\\p{L}\\p{N}])"
            guard let re = try? NSRegularExpression(pattern: motif) else { continue }
            entites[i].mentions = re.numberOfMatches(in: texte, range: NSRange(texte.startIndex..., in: texte))
        }
    }
}

// MARK: - Le texte à lire

/// La prose d'un document Markdown, sans ce qui n'en est pas : frontmatter, blocs de code et de
/// carte, balises HTML, adresses des liens, et la section `## Entités` elle-même (une liste de
/// noms, déjà lue par `LecteurRapportFornews`).
enum TexteAnalysable {
    static func depuis(_ markdown: String) -> String {
        var lignes: [String] = []
        var cloture: String?, dansEntites = false
        var texte = markdown
        if let r = texte.range(of: "^---\\r?\\n[\\s\\S]*?\\r?\\n---\\r?\\n?", options: .regularExpression),
           r.lowerBound == texte.startIndex {
            texte.removeSubrange(r)
        }
        for brute in texte.components(separatedBy: .newlines) {
            let ligne = brute.trimmingCharacters(in: .whitespaces)
            if let c = cloture { if ligne.hasPrefix(c) { cloture = nil }; continue }
            if ligne.hasPrefix("```") || ligne.hasPrefix("~~~") { cloture = String(ligne.prefix(3)); continue }
            if ligne.hasPrefix("## ") { dansEntites = LecteurRapportFornews.estTitreEntites(String(ligne.dropFirst(3))) }
            if dansEntites { continue }
            lignes.append(brute)
        }
        var prose = lignes.joined(separator: "\n")
        let remplacements: [(String, String)] = [
            (#"<!--[\s\S]*?-->"#, " "),
            (#"<[^>]+>"#, " "),
            (#"!\[[^\]]*\]\([^)]*\)"#, " "),                // images
            (#"\[([^\]]*)\]\([^)]*\)"#, "$1"),              // liens : le texte, pas l'adresse
            (#"\[\[([^\]|]+)\|([^\]]+)\]\]"#, "$2"),        // [[cible|libellé]]
            (#"\[\[([^\]]+)\]\]"#, "$1"),
            (#"\[\^[^\]]+\]"#, ""),                         // appels de note
            (#"https?://\S+"#, " "),
            (#"[*_`|>#]+"#, " "),
            (#"&nbsp;|&[a-z]+;"#, " "),
        ]
        for (motif, par) in remplacements {
            prose = prose.replacingOccurrences(of: motif, with: par, options: .regularExpression)
        }
        return prose.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// La langue dominante de la prose (« fr », « en »…), si `NLLanguageRecognizer` en est sûr.
    static func langue(_ markdown: String) -> String? {
        let r = NLLanguageRecognizer()
        r.processString(String(depuis(markdown).prefix(4000)))
        guard let l = r.dominantLanguage, l != .undetermined else { return nil }
        return l.rawValue.split(separator: "-").first.map(String.init)
    }
}
