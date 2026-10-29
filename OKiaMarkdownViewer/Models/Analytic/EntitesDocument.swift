import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

// Option Analytic (1.4) — les entités d'un document. Ce fichier ne touche ni au réseau ni à
// l'interface : il lit ce que le document donne (un rapport fornews en donne presque tout), puis
// détecte le reste avec l'algorithme de fornews (`NLTagger` et `FiltreEntitesNER`, copiés dans
// `Fornews/`). La résolution Wikidata, proposée et jamais imposée, vit dans `AnalyseEntites`.

/// Une entité du document, telle que l'option la montre.
struct EntiteDocument: Identifiable, Hashable, Codable, Sendable {
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

    /// Un journal, un site, une agence que le document CITE comme source (« — La Liberté,
    /// 6 octobre 2026 », un lien vers laliberte.ch) : montré à part, jamais envoyé à Wikidata.
    var source = false

    var aDesCoordonnees: Bool { latitude != nil && longitude != nil }

    /// Un article devant le nom (« la CIA », « l'ONU ») fait échouer la recherche Wikidata, qui
    /// connaît « CIA », et sépare deux noms d'une même chose : un rapport fornews rangeait « l'ONU »
    /// parmi les organisations et « Onu » parmi les lieux. Le nom affiché reste celui du document.
    static func sansArticle(_ nom: String) -> String {
        // Un article EN MINUSCULES suivi d'une espace, ou l'élision « l' » : sans l'espace exigée,
        // « Le » de « Leroy Merlin » passait pour un article (essai du 25/10/2026) ; avec la
        // majuscule, « Le Monde » serait devenu « Monde ». Un titre porte son article en capitale.
        let motif = #"^(?:(?:la|le|les|the|der|die|das|el|los|las|il|lo|gli)\s+|l['’]\s*)(?=\p{Lu})"#
        let r = nom.replacingOccurrences(of: motif, with: "", options: .regularExpression)
        return r.isEmpty ? nom : r
    }

    static func cle(_ nom: String) -> String {
        sansArticle(nom).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
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
        var resultat = entites.filter { DetecteurEntites.valide(EntiteDetectee(valeur: $0.nom, type: $0.type)) }
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
        if titresEntitesAutres.contains(a) { return true }
        return a.range(of: #"^(?:entit(?:es?|y|ies|a|at(?:en)?|aet(?:en)?)|entidad(?:es)?)$"#,
                       options: .regularExpression) != nil
    }

    /// Les titres des dix autres langues de fornews (`RapportObsidian.labels`), comme
    /// `ENTITY_HEADINGS_LANG` dans render.js ; pliés comme le titre qu'on leur compare.
    static let titresEntitesAutres: Set<String> = Set(["エンティティ", "개체", "实体", "Сущности", "Сутності",
                                                        "इकाइयाँ", "Thực thể", "Varlıklar", "Entiteiten"].map(plier))

    /// Le type d'un genre de la section, d'après les libellés de fornews (`LibellesAnalyste`), dans
    /// ses cinq langues, et ceux des dix autres langues de l'app (fornews écrit encore ses genres en
    /// français pour celles-ci ; un rapport écrit ou traduit à la main les a dans sa langue). Un
    /// genre inconnu range ses entités en « Autres ».
    static func typeDuGenre(_ genre: String) -> TypeEntite {
        let g = plier(genre)
        func commence(_ prefixes: [String]) -> Bool { prefixes.contains { g.hasPrefix(plier($0)) } }
        if commence(["personnalit", "personne", "people", "person", "personalidad", "pessoa", "人物", "인물",
                     "персон", "люди", "особ", "kişi", "nhân vật", "người", "व्यक्ति"]) { return .person }
        if commence(["organi", "組織", "组织", "机构", "조직", "организ", "організ", "kuruluş", "tổ chức", "संगठन"]) { return .org }
        if commence(["lieu", "place", "orte", "ort ", "lugar", "luogh", "luogo", "pays", "countr", "ville", "cit",
                     "plaats", "local", "場所", "地名", "地点", "장소", "мест", "місц", "yer", "địa điểm", "स्थान"]) { return .gpe }
        if commence(["produ", "oeuvre", "work", "製品", "产品", "제품", "продукт", "ürün", "sản phẩm", "उत्पाद"]) { return .product }
        if commence(["evenement", "event", "ereignis", "acontecimiento", "evento", "gebeurtenis", "出来事", "イベント",
                     "事件", "사건", "이벤트", "событи", "поді", "olay", "sự kiện", "घटना"]) { return .event }
        if commence(["sante", "health", "gesundheit", "salud", "salute", "maladie", "disease", "gezondheid", "saúde",
                     "健康", "건강", "здоров", "sağlık", "sức khỏe", "स्वास्थ्य"]) { return .maladie }
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

    /// Le moyen qui a servi, pour le diagnostic des builds de test.
    enum Methode: String, Sendable {
        case nlTagger = "NLTagger"
        case appleIntelligence = "Apple Intelligence"
        case majuscules = "repli majuscules"
    }

    /// Trois étages, du meilleur au plus sûr.
    /// ⚠️ **Sur iOS, le modèle de noms de `NLTagger` peut manquer** : il ne propose alors que la
    /// langue, l'écriture et le découpage, ne trouve AUCUN nom, et ne le dit pas. Signalé par
    /// Patrick le 25/10/2026 (« Donald Trump, Elon Musk ne sont pas détectés ») ; le simulateur le
    /// montre (`availableTagSchemes` sans `NameType`), alors que le Mac l'a toujours.
    /// 1. `NLTagger`, après avoir demandé son modèle au système — huit secondes au plus : au
    ///    simulateur, la demande ne revient jamais.
    /// 2. À défaut, Apple Intelligence, avec l'extraction de fornews (`NERFoundationModels`).
    /// 3. En dernier recours, les suites de mots à majuscule, passées au même filtre ; Wikidata,
    ///    s'il est accepté, leur donne ensuite leur genre.
    /// `replis` : faute de noms par NLTagger, redemander le modèle puis essayer Apple Intelligence —
    /// des secondes, parfois des dizaines. Pas pour un rapport qui nomme déjà ses entités : la
    /// détection n'y ajoute que ce qu'il ne nommait pas (Patrick, B125 : « l'affichage des entités
    /// d'un document est trop lent »).
    static func detecter(_ markdown: String, langue: String?, replis: Bool = true) async -> (entites: [EntiteDocument], methode: Methode) {
        let texte = TexteAnalysable.depuis(markdown)
        guard !texte.isEmpty else { return ([], .nlTagger) }
        // `NLTagger` d'abord, même quand il ne déclare pas son modèle de noms : au simulateur
        // (iOS 26.5 et 27.1), `availableTagSchemes` ne le liste pas, et pourtant il trouve les noms
        // (29/10/2026). Sans ce premier essai, on passait au repli par majuscules, dont l'allemand
        // fait des personnes de « Juni » ou « Sie ».
        var brutes = await parNLTagger(texte, langue: langue)
        var methode = Methode.nlTagger
        if brutes.isEmpty, replis {
            // Rien trouvé : le modèle de noms est redemandé — même déclaré, il peut manquer sur
            // l'appareil (Duo, B122 : « Aucune entité », NLTagger, langue fr) —, puis réessayé ;
            // ensuite Apple Intelligence. Les majuscules seulement sans modèle déclaré : avec un
            // modèle qui ne trouve rien, mieux vaut aucune entité que des mots courants.
            let declare = NLTagger.availableTagSchemes(for: .word, language: NLLanguage(langue ?? "en")).contains(.nameType)
            if await modeleDeNomsPret(langue, redemander: true) {
                brutes = await parNLTagger(texte, langue: langue)
            }
            if brutes.isEmpty, let parIA = await parAppleIntelligence(texte, langue: langue) {
                brutes = parIA
                methode = .appleIntelligence
            } else if brutes.isEmpty, !declare {
                brutes = parMajuscules(texte)
                methode = .majuscules
            }
        }
        // « IA », « AI » : l'intelligence artificielle, un nom commun — que le repli par majuscules
        // comptait quatorze fois dans un briefing, et que Wikidata prenait pour Internet Archive.
        // Les noms d'une écriture sans casse passent à côté du filtre de fornews (voir `valide`).
        let sansCasse = brutes.filter { Self.ecritureSansCasse($0.valeur) && Self.valide($0) }
        let filtrees = (FiltreEntitesNER.filtrer(brutes.filter { !Self.ecritureSansCasse($0.valeur) }, texteSource: texte) + sansCasse)
            .filter { !Self.nomsCommunsEnSigle.contains($0.valeur) }
        return (filtrees.map { EntiteDocument(nom: $0.valeur, type: $0.type, origine: .detection) }, methode)
    }

    static let nomsCommunsEnSigle: Set<String> = ["IA", "AI", "KI"]

    /// Un nom écrit sans majuscule possible : japonais, chinois, coréen, devanagari… Le filtre de
    /// fornews exige une majuscule dans le nom d'une personne, d'une organisation ou d'un lieu : dans
    /// ces écritures, il les rejetait tous — « Aucune entité » pour tout document japonais (29/10/2026,
    /// captures des quinze langues). Signalé à fornews ; ici, ces noms gardent les seuls contrôles
    /// qui valent pour toutes les écritures.
    static func ecritureSansCasse(_ nom: String) -> Bool {
        nom.contains(where: \.isLetter) && !nom.contains(where: { $0.isUppercase || $0.isLowercase })
    }

    /// Le contrôle de validité de fornews, sauf pour une écriture sans casse : au moins deux
    /// caractères, au moins une lettre, pas un nombre.
    static func valide(_ e: EntiteDetectee) -> Bool {
        guard ecritureSansCasse(e.valeur) else { return FiltreEntitesNER.estValide(e) }
        let v = e.valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.count >= 2 && v.contains(where: \.isLetter)
    }

    /// Le modèle de noms de `NLTagger` est-il là, pour cette langue ? Sinon, on le demande.
    /// `redemander` : même déclaré, le modèle est demandé à nouveau (il peut manquer quand même).
    static func modeleDeNomsPret(_ langue: String?, redemander: Bool = false) async -> Bool {
        let l = NLLanguage(langue ?? "en")
        func present() -> Bool { NLTagger.availableTagSchemes(for: .word, language: l).contains(.nameType) }
        if present(), !redemander { return true }
        // Une demande par langue et par lancement : sans réponse, la suivante attendrait encore huit
        // secondes pour rien.
        guard await DemandesDeModele.partage.premiere(l) else { return false }
        // Une vraie course : la demande ignore l'annulation (au simulateur, elle ne revient jamais),
        // attendre sa fin bloquait l'analyse — « Lecture du document… » sans fin. Le premier qui
        // répond, du téléchargement ou du délai, reprend ; l'autre est abandonné.
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            let reprise = UneSeuleFois(suite)
            Task.detached { _ = try? await NLTagger.requestAssets(for: l, tagScheme: .nameType); reprise.reprendre() }
            Task.detached { try? await Task.sleep(for: .seconds(8)); reprise.reprendre() }
        }
        return present()
    }

    /// Reprend une attente une seule fois, quel que soit le nombre de concurrents qui finissent.
    final class UneSeuleFois: @unchecked Sendable {
        private var suite: CheckedContinuation<Void, Never>?
        private let verrou = NSLock()
        init(_ suite: CheckedContinuation<Void, Never>) { self.suite = suite }
        func reprendre() {
            verrou.lock(); let s = suite; suite = nil; verrou.unlock()
            s?.resume()
        }
    }

    /// Les langues dont le modèle de noms a déjà été demandé depuis le lancement.
    actor DemandesDeModele {
        static let partage = DemandesDeModele()
        private var faites = Set<String>()
        func premiere(_ l: NLLanguage) -> Bool { faites.insert(l.rawValue).inserted }
    }

    static func parNLTagger(_ texte: String, langue: String?) async -> [EntiteDetectee] {
        await Task.detached(priority: .utility) {
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
    }

    /// Apple Intelligence lit le document par morceaux (sa fenêtre est petite) : six au plus, soit
    /// les ~36 000 premiers caractères — au-delà, l'attente ne vaut plus ce qu'elle rapporte. nil
    /// quand le modèle de l'appareil n'est pas disponible.
    static func parAppleIntelligence(_ texte: String, langue: String?) async -> [EntiteDetectee]? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let ner = NERFoundationModels()
        var resultat: [EntiteDetectee] = []
        for morceau in morceaux(texte, taille: 6_000).prefix(6) {
            if let trouvees = try? await ner.detecter(morceau, langue: langue) { resultat += trouvees }
        }
        // Rien de rendu (refus, délai, fenêtre dépassée) : l'étage suivant prend la main, plutôt
        // qu'une liste vide — c'est ce qu'on voyait au simulateur, qui emprunte le modèle du Mac.
        return resultat.isEmpty ? nil : resultat
        #else
        return nil
        #endif
    }

    /// Le dernier recours : les noms qui REVIENNENT. Dans chaque ligne, les suites de mots à
    /// majuscule (« Donald Trump », « Banque centrale européenne ») ; on en compte les groupes de
    /// un à trois mots. Restent les groupes de deux ou trois mots vus au moins deux fois, et les mots
    /// seuls vus trois fois hors du début d'une phrase, où tout mot prend la majuscule ; une forme
    /// qui n'apparaît que dans une forme plus longue est retirée. Les titres anglais, où chaque mot
    /// a sa majuscule (« Musk Says SpaceXAI Will Rebrand »), ne reviennent pas : ils tombent.
    /// Genre inconnu (`autre`) : Wikidata, s'il est accepté, le donne ensuite.
    static func parMajuscules(_ texte: String) -> [EntiteDetectee] {
        let liens: Set<String> = ["de", "du", "des", "la", "le", "d’", "d'", "von", "van", "der", "di", "da", "del", "of", "the"]
        func majuscule(_ m: Substring) -> Bool { m.first.map { $0.isUppercase } ?? false }
        var comptes: [String: Int] = [:], ordre: [String] = []
        func compter(_ g: String) { if comptes[g] == nil { ordre.append(g) }; comptes[g, default: 0] += 1 }
        for ligne in texte.split(whereSeparator: \.isNewline) {
            // Des mots, sans la ponctuation qui les colle ; une fin de phrase coupe la suite.
            let mots = ligne.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" })
            var suite: [Substring] = [], debutPhrase = true
            func fermer() {
                // Les mots de liaison ne commencent ni ne terminent un groupe.
                while let d = suite.last, liens.contains(d.lowercased()) { suite.removeLast() }
                let n = suite.count
                for i in 0..<n {
                    for l in 1...3 where i + l <= n {
                        let groupe = suite[i..<i + l]
                        guard majuscule(groupe.first!), majuscule(groupe.last!) else { continue }
                        if l == 1 && i == 0 && debutPhraseSuite { continue }
                        compter(groupe.joined(separator: " "))
                    }
                }
                suite = []
            }
            var debutPhraseSuite = false
            for brut in mots {
                let fin = brut.last.map { ".!?:;".contains($0) } ?? false
                var mot = brut.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()[]«»\"“”*_"))[...]
                // Le possessif anglais : « Elon Musk's » est Elon Musk.
                if mot.hasSuffix("'s") || mot.hasSuffix("’s") { mot = mot.dropLast(2) }
                if !mot.isEmpty, majuscule(mot) || (!suite.isEmpty && liens.contains(mot.lowercased())) {
                    if suite.isEmpty { debutPhraseSuite = debutPhrase }
                    suite.append(mot)
                } else {
                    fermer()
                }
                if fin || brut.hasSuffix(",") { fermer() }
                debutPhrase = fin
            }
            fermer()
        }
        let gardes = ordre.filter { g in
            let n = comptes[g] ?? 0
            return g.contains(" ") ? n >= 2 : n >= 3
        }
        // Une forme qui n'apparaît que dans une plus longue (« Donald » dans « Donald Trump ») part.
        let utiles = gardes.filter { g in
            !gardes.contains { l in l != g && l.count > g.count && " \(l) ".contains(" \(g) ") && comptes[l] == comptes[g] }
        }
        return utiles.map { EntiteDetectee(valeur: $0, type: .autre) }
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

    /// Des morceaux d'au plus `taille` caractères, coupés entre deux paragraphes.
    static func morceaux(_ texte: String, taille tailleMorceau: Int = tailleMorceau) -> [String] {
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

    /// Une entité détectée qui n'est qu'une partie, en mots entiers, d'un nom plus long du même genre
    /// (« Union » d'« Union européenne »), ou la fin du nom complet d'une personne (« Poutine » de
    /// « Vladimir Poutine », même typé organisation par `NLTagger`, comme « Musk »), n'est pas une
    /// entité de plus : le nom complet la reprend, avec ses mentions.
    /// ⛔ Jamais une personne dans un nom d'un autre genre : `NLTagger` repère parfois « Maison
    /// Blanche de Donald Trump » comme organisation, et Donald Trump disparaissait de la liste
    /// (signalé par Patrick, 25/10/2026, avec Elon Musk).
    static func absorberFormesCourtes(_ entites: [EntiteDocument]) -> [EntiteDocument] {
        var resultat = entites
        var retirees = Set<String>()
        // Un genre inconnu (le repli par majuscules) ne dit pas qui contient qui : « Trump » se
        // fondait dans « After Trump Pushes », titre répété d'un briefing anglais.
        for courte in entites where courte.origine == .detection && courte.type != .autre {
            let mots = courte.id.split(separator: " ")
            let longue = entites.firstIndex { l in
                guard l.id != courte.id, l.id.count > courte.id.count, !retirees.contains(l.id), l.type != .autre else { return false }
                let motsLongs = l.id.split(separator: " ")
                if l.type == courte.type, contientMots(motsLongs, mots) { return true }
                // La fin du nom d'une personne : son patronyme, quel que soit le genre donné à la forme courte.
                return l.type == .person && motsLongs.count > mots.count && Array(motsLongs.suffix(mots.count)) == mots
            }
            guard let i = longue else { continue }
            retirees.insert(courte.id)
            if let j = resultat.firstIndex(where: { $0.id == entites[i].id }) {
                resultat[j].mentions = max(resultat[j].mentions, courte.mentions)
            }
        }
        // Une personne détectée dont le nom FINIT par celui d'une autre personne n'est que ce nom
        // précédé d'un titre : « Le président ukrainien Volodymyr Zelensky » est Volodymyr Zelensky.
        for longue in entites where longue.origine == .detection && longue.type == .person && !retirees.contains(longue.id) {
            let mots = longue.id.split(separator: " ")
            guard let j = resultat.firstIndex(where: { p in
                p.type == .person && p.id != longue.id && !retirees.contains(p.id)
                    && p.id.split(separator: " ").count >= 2
                    && mots.count > p.id.split(separator: " ").count
                    && Array(mots.suffix(p.id.split(separator: " ").count)) == p.id.split(separator: " ")
            }) else { continue }
            retirees.insert(longue.id)
            resultat[j].mentions = max(resultat[j].mentions, longue.mentions)
        }
        // Genre inconnu : un mot seul (« Trump », « Donald ») rejoint le nom de deux ou trois mots
        // qui finit ou commence par lui et revient le plus souvent (« Donald Trump », pas
        // « President Donald Trump »).
        for courte in entites where courte.origine == .detection && courte.type == .autre && !courte.id.contains(" ") {
            let candidats = resultat.filter { l in
                l.type == .autre && !retirees.contains(l.id) && l.id != courte.id
                    && (2...3).contains(l.id.split(separator: " ").count)
                    && [l.id.split(separator: " ").last, l.id.split(separator: " ").first]
                        .contains { $0.map(String.init) == courte.id }
            }
            guard let meilleur = candidats.max(by: { $0.mentions < $1.mentions }),
                  let j = resultat.firstIndex(where: { $0.id == meilleur.id }) else { continue }
            retirees.insert(courte.id)
            resultat[j].mentions = max(resultat[j].mentions, courte.mentions)
        }
        return resultat.filter { !retirees.contains($0.id) }
    }

    /// La distance d'édition entre deux noms pliés (« ryad », « riyad » : 1).
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        var prec = Array(0...y.count)
        for i in 1...x.count {
            var cour = [i] + Array(repeating: 0, count: y.count)
            for j in 1...max(1, y.count) where !y.isEmpty {
                cour[j] = min(prec[j] + 1, cour[j - 1] + 1, prec[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prec = cour
        }
        return prec[y.count]
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

// MARK: - Les sources du document

/// Les sources qu'un document cite, pour les tenir à l'écart des entités de son texte (Patrick,
/// B90 : « La Liberté est un journal, il doit être dans les sources ») : les sites des liens
/// (`laliberte.ch` → « laliberte ») et les attributions des légendes (« — La Liberté, 6 octobre »,
/// « … · France 24 »).
enum SourcesDocument {
    struct Sources {
        var noms = Set<String>()
        var domaines = Set<String>()

        /// L'entité est-elle une de ces sources ?
        func contient(_ e: EntiteDocument) -> Bool {
            if noms.contains(e.id) { return true }
            let serre = e.id.filter { $0.isLetter || $0.isNumber }
            return serre.count >= 4 && domaines.contains(serre)
        }
    }

    static func lire(_ markdown: String) -> Sources {
        var r = Sources()
        let ns = markdown as NSString
        let tout = NSRange(location: 0, length: ns.length)
        if let re = try? NSRegularExpression(pattern: #"https?://(?:www\.|m\.|fr\.|de\.|en\.)?([a-z0-9\-]+)\.[a-z]{2,}"#,
                                             options: [.caseInsensitive]) {
            for m in re.matches(in: markdown, range: tout) {
                r.domaines.insert(ns.substring(with: m.range(at: 1)).lowercased().replacingOccurrences(of: "-", with: ""))
            }
        }
        // Les attributions, sur le texte débarrassé de ses balises.
        let texte = markdown.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let tns = texte as NSString
        // « — La Liberté, 6 octobre 2026 » : un nom suivi d'une VRAIE date, jour et mois — « — États-
        // Unis, 2 articles » passait pour une source.
        let mois = "janv|févr|fevr|mars|avr|mai|juin|juil|août|aout|sept|oct|nov|déc|dec|jan|feb|mar|apr|may|jun|jul|aug|sep"
            + "|märz|maerz|okt|dez|ene|abr|ago|dic|genn|febb|magg|giug|lugl|sett|ott"
        let attribution = #"[—–]\s+(\p{Lu}[\p{L}\p{N}’'&.\- ]{1,40}?),\s+\d{1,2}\.?\s+(?:"# + mois + ")"
        if let re = try? NSRegularExpression(pattern: attribution, options: [.anchorsMatchLines, .caseInsensitive]) {
            for m in re.matches(in: texte, range: NSRange(location: 0, length: tns.length)) {
                r.noms.insert(EntiteDocument.cle(tns.substring(with: m.range(at: 1))))
            }
        }
        // « … · France 24 » en fin de ligne : seulement si le nom est aussi le site d'un lien.
        if let re = try? NSRegularExpression(pattern: #"·\s+(\p{Lu}[\p{L}\p{N}’'&.\- ]{1,40}?)\s*$"#, options: [.anchorsMatchLines]) {
            for m in re.matches(in: texte, range: NSRange(location: 0, length: tns.length)) {
                let nom = EntiteDocument.cle(tns.substring(with: m.range(at: 1)))
                if r.domaines.contains(nom.filter { $0.isLetter || $0.isNumber }) { r.noms.insert(nom) }
            }
        }
        return r
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
