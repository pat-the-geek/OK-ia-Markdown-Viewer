// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/VerificateurAncrage.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Garde **anti-hallucination de sortie** du résumé génératif (déterministe, sans LLM).
///
/// Constat (16/07/2026, 20min « L'Angleterre n'a sauvé ni le Roi, ni la Suisse ») : même alimenté
/// du corps COMPLET et correct de l'article, le petit modèle on-device peut inverser l'issue
/// (élimination → qualification) et inventer des acteurs — « la France », « Kylian Mbappé »,
/// « l'Espagne » — absents du texte. La consigne (« n'invente rien ») ne suffit pas : la polarité
/// vainqueur/perdant est un seul bit, facile à retourner. On vérifie donc la SORTIE : tout nom
/// propre du résumé doit exister dans le texte source, sinon le résumé est rejeté et le pipeline
/// retombe sur l'extractif (fidèle par construction, via `SummarizerAvecRepli`).
///
/// Deux modes, car le résumé peut être dans une autre langue que la source (FM résume + traduit
/// en une étape) et les exonymes divergent (England → Angleterre, London → Londres…) :
/// - **strict** (résumé dans la langue de la source, hors allemand — qui capitalise tous les noms
///   communs) : rejet dès UN nom absent, simple ou multi-mots.
/// - **tolérant** (langues différentes, ou sortie allemande) : les noms multi-mots comptent comme
///   avant (rejet à partir de deux) ; un nom simple absent ne compte que s'il ne ressemble PAS à
///   une traduction — cf. `ressembleAUnExonyme`.
///
/// ⚠️ **Les seuils viennent d'une mesure, pas d'une intuition** (15/08/2026, 332 paires
/// (résumé, source) du store réel). Les deux modes toléraient un nom SIMPLE absent : c'est par là
/// qu'une entité inventée d'un seul mot est entrée dans le corpus. Le relevé a montré que la
/// tolérance ne servait à rien en mode strict (zéro cas) mais portait un vrai travail en mode
/// tolérant (« Inde », « États-Unis », « Belgique », « Venise » — des exonymes). D'où deux
/// traitements distincts, au lieu d'un seuil resserré partout qui aurait cassé les résumés traduits.
public enum VerificateurAncrage {

    /// Verdict d'ancrage d'un résumé généré par rapport à son texte source.
    /// - Returns: `ancre` = le résumé est fidèle aux noms du texte ; `absents` = les noms propres
    ///   du résumé introuvables dans la source (pour journalisation/diagnostic).
    public static func verdict(resume: String, source: String, modeStrict: Bool) -> (ancre: Bool, absents: [String]) {
        let noms = candidats(dans: resume)
        guard !noms.isEmpty else { return (true, []) }
        let meule = plier(source)
        let absents = noms.filter { !contientMot(meule, $0) }
        let multiMots = absents.filter { $0.contains(" ") }
        let ancre: Bool
        if modeStrict {
            // Plus AUCUNE tolérance : le résumé est dans la langue de la source, un nom propre
            // absent est absent. Mesuré sur 332 paires du store réel (15/08) : **zéro** résumé
            // accepté portait un nom simple absent — fermer ce trou ne coûte donc rien.
            ancre = absents.isEmpty
        } else {
            // Mode tolérant : le résumé est dans une AUTRE langue que la source. Un nom simple
            // absent y est le plus souvent un exonyme légitime (India → Inde, Belgium → Belgique)
            // — la mesure le confirme. Mais « le plus souvent » n'est pas « toujours » : c'est
            // par ce trou qu'une entité inventée d'un seul mot est entrée dans le corpus.
            // On ne pardonne donc que ce qui RESSEMBLE à un exonyme.
            ancre = multiMots.count < 2
                && !absents.contains { !$0.contains(" ") && !ressembleAUnExonyme($0, meule) }
        }
        return (ancre, absents)
    }

    /// Un nom simple absent de la source est-il **plausiblement une traduction** plutôt qu'une
    /// invention ?
    ///
    /// Trois portes, toutes établies par la mesure du 15/08 sur 332 paires réelles :
    /// 1. **un nom de pays connu** — `DrapeauPays` porte déjà les noms des pays dans les cinq
    ///    langues de l'app ; « États-Unis » n'a aucun cognat dans « U.S. » et ne passerait pas
    ///    autrement ;
    /// 2. **un cognat** — « Inde »/India, « Venise »/Venice, « Belgique »/Belgium partagent leurs
    ///    premières lettres ; un mot inventé n'en partage avec rien ;
    /// 3. **un mot trop court** (< 4 lettres) — « IA »/AI, « ONU »/UN : trop peu de matière pour
    ///    juger, et les sigles se traduisent.
    ///
    /// ⚠️ Ce n'est PAS un détecteur d'exonymes : c'est un filtre de prudence, volontairement
    /// permissif. Il ne cherche pas à prouver qu'un nom est une traduction, seulement à écarter
    /// ceux qui ne ressemblent à rien de ce que contient la source.
    ///
    /// Relevé sur le corpus : 18 pardonnés, 6 comptés. Les 6 sont des faux candidats de
    /// l'extracteur (« Quand », « Maintenant », « Évidemment »…), traités par `motsOutils`.
    static func ressembleAUnExonyme(_ nom: String, _ meule: String) -> Bool {
        if motsOutils.contains(plier(nom)) { return true }
        if DrapeauPays.emoji(pourNom: nom) != nil { return true }
        let n = plier(nom)
        guard n.count >= 4 else { return true }
        let prefixe = NSRegularExpression.escapedPattern(for: String(n.prefix(4)))
        return meule.range(of: "(?<![\\p{L}])" + prefixe, options: .regularExpression) != nil
    }

    /// Mots capitalisés que l'extracteur prend pour des noms propres alors qu'ils n'en sont pas —
    /// adverbes, conjonctions, verbes ouvrant une proposition après une virgule ou dans une liste.
    ///
    /// ⚠️ Relevés **sur le corpus**, pas imaginés : ce sont exactement les faux candidats qui
    /// ressortaient du relevé du 15/08. Les laisser compter aurait fait rejeter des résumés
    /// parfaitement fidèles — le remède aurait coûté plus que le mal, faute qu'on a déjà commise
    /// deux fois dans ce projet.
    private static let motsOutils: Set<String> = [
        "ce", "cet", "cette", "ces", "quand", "maintenant", "evidemment", "renforcer",
        "lecture", "details", "aujourd hui", "ainsi", "cependant", "toutefois", "enfin",
        "pourtant", "desormais", "egalement", "notamment", "selon", "malgre", "depuis",
        "the", "this", "that", "these", "those", "now", "however", "meanwhile", "finally",
    ]

    // MARK: Extraction des noms propres candidats

    /// Noms propres candidats du résumé : séquences de mots capitalisés **hors début de phrase**
    /// (en français, la majuscule initiale de phrase n'est pas un signal). Une séquence qui ouvre
    /// la phrase perd son premier mot mais garde la suite (« La France a gagné » → « France »).
    /// Le Markdown est neutralisé (gras retiré, lignes de titres « ## » ignorées), les élisions
    /// détachées (« L'Angleterre » → « Angleterre »). Dédupliqué (clé pliée), ordre d'apparition.
    public static func candidats(dans resume: String) -> [String] {
        var vus = Set<String>()
        var resultat: [String] = []
        for segment in segmentsDePhrase(resume) {
            for (sequence, debutDePhrase) in sequencesCapitalisees(segment) {
                var mots = sequence
                if debutDePhrase { mots.removeFirst() }   // la majuscule de tête est structurelle
                guard !mots.isEmpty else { continue }
                let nom = mots.joined(separator: " ")
                guard nom.count >= 2 else { continue }
                if vus.insert(plier(nom)).inserted { resultat.append(nom) }
            }
        }
        return resultat
    }

    /// Découpe en segments « phrase » : ponctuation forte, deux-points, **barres de tableau** et
    /// sauts de ligne. Les lignes de titre Markdown (« ## … ») et les puces sont écartées/neutralisées
    /// — leurs majuscules sont éditoriales, pas des entités (une vraie entité de titre réapparaît
    /// dans le corps).
    ///
    /// ## ⛔ La barre `|` manquait — et elle a gelé l'éditorial pendant deux jours
    ///
    /// La garde d'ancrage posée le 15/08 a rejeté **tous** les éditoriaux suivants. Patrick l'a vu à
    /// l'œil le 17/08 : « l'éditorial du jour est toujours le même ». Mesuré sur le texte figé, sept
    /// des dix-neuf noms propres candidats étaient du mobilier de tableau : `Thème`, `Nombre`,
    /// `Économie`, `Sport`, `Politique`, `Accidents`, `Événements`.
    ///
    /// La cause est mécanique : sans `|` parmi les séparateurs, la ligne `| Thème | Nombre |` forme
    /// UN segment dont le mot d'indice 0 est la barre. « Thème » n'est donc plus « en début de
    /// phrase », sa majuscule structurelle n'est plus retirée, et il devient un nom propre à
    /// vérifier — introuvable dans la matière, forcément.
    ///
    /// ⚠️ Or le prompt **exige** ce tableau récapitulatif. La garde condamnait donc exactement ce
    /// qu'on demandait de produire. Découper aux barres rend à chaque cellule son mot initial : les
    /// libellés retombent, tandis qu'un vrai nom dans une cellule (« George Sand » → « Sand ») reste
    /// vérifié. On neutralise le mobilier sans desserrer le contrôle.
    ///
    /// ⚠️ **La leçon dépasse ce défaut** : une garde qui refuse tout ne se distingue d'une garde qui
    /// marche que si son refus se voit. Deux jours de silence, et c'est l'œil de Patrick qui a servi
    /// de test.
    private static func segmentsDePhrase(_ texte: String) -> [String] {
        let sansGras = texte.replacingOccurrences(of: "*", with: "")
        let lignes = sansGras.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        return lignes.flatMap { ligne -> [String] in
            var l = ligne.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("- ") { l = String(l.dropFirst(2)) }
            return l.components(separatedBy: CharacterSet(charactersIn: ".!?…:;|"))
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }

    /// Séquences de mots consécutifs capitalisés d'un segment, avec l'indication « la séquence
    /// ouvre le segment ». Un mot = majuscule initiale puis lettres/apostrophes/traits d'union ;
    /// l'élision à lettre unique (« L' », « D' »…) est détachée si le reste est lui-même capitalisé.
    private static func sequencesCapitalisees(_ segment: String) -> [(mots: [String], debutDePhrase: Bool)] {
        var resultat: [(mots: [String], debutDePhrase: Bool)] = []
        var courante: [String] = []
        var couranteOuvre = false
        var indexMot = 0
        for brut in segment.split(whereSeparator: { $0.isWhitespace }) {
            let mot = String(brut).trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’-")))
            // ⚠️ **La ponctuation FINALE coupe la séquence.** Elle était retirée en silence : « Kiev,
            // Vitali Klitschko » donnait donc UN nom, « Kiev Vitali Klitschko », introuvable dans la
            // source — et le résumé était déclaré non ancré alors qu'il citait deux noms bien
            // présents. Mesuré le 22/08 : **5 résumés EXTRACTIFS sur 20** jugés non ancrés, alors
            // qu'ils copient l'article MOT POUR MOT. C'était donc le vérificateur qui se trompait.
            //
            // 🔑 Même famille que « Suisse contre la Colombie » : deux noms propres voisins soudés
            // en une entité qui n'existe pas. La virgule, le point-virgule ou la parenthèse qui les
            // sépare est une information, pas du bruit à nettoyer.
            let coupe = brut.last.map { CharacterSet.punctuationCharacters.contains($0.unicodeScalars.first!)
                                        && !"'’-".contains($0) } ?? false
            defer { indexMot += 1 }
            // ⛔ **La parenthèse OUVRANTE coupe aussi** (banc du 02/10/2026) : seule la fermante
            // coupait, et « Model Context Protocol (MCP) » devenait « Model Context Protocol MCP »,
            // introuvable dans l'article qui l'écrit pourtant mot pour mot.
            if let premier = brut.first, "([{«“\"".contains(premier), !courante.isEmpty {
                resultat.append((courante, couranteOuvre)); courante = []
            }
            if let nettoye = motCapitalise(mot, enTeteDeNom: courante.isEmpty) {
                if courante.isEmpty { couranteOuvre = (indexMot == 0) }
                courante.append(nettoye)
                if coupe { resultat.append((courante, couranteOuvre)); courante = [] }
            } else if !courante.isEmpty {
                resultat.append((courante, couranteOuvre))
                courante = []
            }
        }
        if !courante.isEmpty { resultat.append((courante, couranteOuvre)) }
        return resultat
    }

    /// Le mot s'il est un candidat « nom propre » (majuscule initiale), débarrassé d'une élision
    /// à lettre unique EN TÊTE de nom (« L'Angleterre » → « Angleterre ») ; `nil` sinon.
    ///
    /// ⛔ **Au milieu d'un nom, l'élision est GARDÉE** (banc du 02/10/2026) : la retirer faisait de
    /// « Côte d'Ivoire » un « Côte Ivoire » introuvable, et le résumé qui recopiait l'article était
    /// déclaré non ancré. Le mot reste un candidat si ce qui suit l'élision est capitalisé.
    private static func motCapitalise(_ mot: String, enTeteDeNom: Bool = true) -> String? {
        var m = mot
        // Élision « X' » : le reste doit être capitalisé par lui-même.
        if m.count > 2, let deuxieme = m.dropFirst().first, deuxieme == "'" || deuxieme == "’" {
            let reste = String(m.dropFirst(2))
            guard let initiale = reste.first, initiale.isUppercase else { return nil }
            return enTeteDeNom ? reste : mot
        }
        guard let premier = m.first, premier.isUppercase, m.dropFirst().contains(where: \.isLetter) || m.count >= 2 else { return nil }
        return m
    }

    // MARK: Recherche pliée à frontières de mot

    /// Pliage commun (casse + diacritiques) pour comparer résumé et source (« Mbappe » ≈ « Mbappé »).
    /// L'apostrophe typographique (’) vaut l'apostrophe droite (') : le modèle et les éditeurs
    /// n'emploient pas la même, et « Côte d’Ivoire » doit retrouver « Côte d'Ivoire ».
    private static func plier(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr"))
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }

    /// **Présence d'UN nom dans un texte**, à frontières de mot et sans accent ni casse.
    ///
    /// ⛔ **Ne PAS employer `verdict` pour cela.** Piège coûté le 10/09/2026 :
    /// `verdict(resume: "SpaceX", source: extrait)` rendait `ancre = true` sur un extrait qui ne
    /// contient pas ce mot. La raison est légitime — `candidats` ignore un mot capitalisé en TÊTE
    /// de phrase, parce que « Les », « Cette », « Selon » y sont capitalisés sans être des noms
    /// propres — mais quand le « résumé » est le nom seul, il est forcément en tête : la liste des
    /// candidats sort vide, et un verdict sans candidat est trivialement ancré.
    ///
    /// ⚠️ Le contrôle avait donc l'air de fonctionner et ne rejetait rien. C'est la variante la
    /// plus coûteuse d'un défaut : silencieuse, et rassurante.
    public static func contient(_ nom: String, dans texte: String) -> Bool {
        let n = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        return contientMot(plier(texte), n)
    }

    /// Présence de `nom` (déjà en clair) dans `meule` (déjà pliée), à **frontières de mot** — un
    /// simple `contains` validerait « France » dans « françaises ». Les espaces internes du nom
    /// acceptent tout blanc.
    private static func contientMot(_ meule: String, _ nom: String) -> Bool {
        let motif = "(?<![\\p{L}])"
            + nom.split(separator: " ").map { NSRegularExpression.escapedPattern(for: plier(String($0))) }.joined(separator: "\\s+")
            + "(?![\\p{L}])"
        return meule.range(of: motif, options: .regularExpression) != nil
    }
}

/// Levée quand le résumé génératif contient des noms propres absents du texte source
/// (hallucination) : `SummarizerAvecRepli` retombe alors sur le résumé extractif, fidèle.
public struct ResumeNonAncreErreur: LocalizedError {
    public let nomsAbsents: [String]
    public init(nomsAbsents: [String]) { self.nomsAbsents = nomsAbsents }
    public var errorDescription: String? {
        "Résumé rejeté : noms absents du texte source (\(nomsAbsents.joined(separator: ", ")))."
    }
}
