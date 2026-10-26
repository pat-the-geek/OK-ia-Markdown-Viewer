// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsServices/Flux/KeywordMatcher.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Évaluateur des règles de mots-clés ET / OU / NON (§12).
///
/// Pur, instantané, sans LLM. Matching insensible à la casse et aux diacritiques, sur
/// frontière de mot (les phrases multi-mots sont matchées de façon contiguë).
public enum KeywordMatcher {

    /// Normalisation appliquée au haystack ET aux termes (§12.2).
    /// Unifie aussi les apostrophes (typographique U+2019/U+2018, lettre-apostrophe U+02BC → droite) :
    /// `folding` ne les touche pas, et « détroit d'Ormuz » vs « détroit d'Ormuz » créait deux clés
    /// canoniques d'entité distinctes → doublons visibles dans l'app.
    public static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Construit le champ de recherche normalisé à partir du titre + contenu brut (§12.1).
    public static func haystack(titre: String, contenu: String?) -> String {
        normalize(titre + " " + (contenu ?? ""))
    }

    /// Évalue une expression contre un haystack **déjà normalisé** (cf. `haystack(titre:contenu:)`).
    public static func evalue(_ expr: ExpressionMotsCles, contre haystack: String) -> Bool {
        switch expr {
        case .terme(let t): return matchTerme(t, dans: haystack)
        case .et(let xs):   return xs.allSatisfy { evalue($0, contre: haystack) }
        case .ou(let xs):   return xs.contains { evalue($0, contre: haystack) }
        case .non(let x):   return !evalue(x, contre: haystack)
        }
    }

    /// Commodité : évalue une règle contre un titre + contenu bruts (normalisation incluse).
    public static func matche(
        _ expr: ExpressionMotsCles,
        titre: String,
        contenu: String?
    ) -> Bool {
        evalue(expr, contre: haystack(titre: titre, contenu: contenu))
    }

    /// **Suffixes admis après un terme** — flexions et dérivations courantes.
    ///
    /// ## Pourquoi une LISTE et non une longueur
    ///
    /// Demandé par Patrick le 17/08/2026, après la découverte que « Transport » ne relevait pas
    /// « transportent ». La tentation est de tolérer « un suffixe court ». Mesuré sur le corpus,
    /// **aucune borne de longueur ne peut marcher** : « climat**ique** » (+4) est souhaité alors que
    /// « climat**ise** » (+3), plus COURT, ne l'est pas — un climatiseur n'est pas le climat. Trier
    /// par longueur, c'est trier sur ce qui n'est pas le critère.
    ///
    /// D'où une liste nommée. ⛔ Elle exclut délibérément `icle`, `iste`, `ificielle`, `isation`,
    /// `iseurs` — sans quoi « Art » relèverait *article*, *artiste* et *artificielle*, et « Climat »
    /// les climatiseurs. C'est exactement le défaut de sous-chaîne qu'on venait de corriger.
    ///
    /// ⚠️ **Le bare `e` est absent, à dessein.** Il gagnerait « transporte » et perdrait bien plus :
    /// « Art » + `e` = **Arte**, la chaîne de télévision, dans un corpus d'actualité francophone.
    ///
    /// ## Mesure (400 articles, 32 règles réelles)
    ///
    /// 317 → **350** articles retenus (+10 %), et **zéro** faux positif relevé : seuls `arts`,
    /// `modes`, `climatique`, `fribourgeois(e)`, `robots`, `robotique(s)`, `suisses`, `citoyen(ne)s`,
    /// `volcanique(s)`, `volcanisme`, `guerres`, `musiques`, `cinemas` et les six formes verbales de
    /// `transporter` entrent. *article*, *artiste*, *artificielle*, *modèle*, *moderne*,
    /// *climatiseurs*, *climatisation* restent dehors.
    ///
    /// ⚠️ `ale`, `aux` et `isme` sont **raisonnés, pas mesurés** sur ce corpus (ils n'y apportent que
    /// `volcanisme`) : ils couvrent « national → nationaux », « centre → centrale ». Comme toute
    /// règle non mesurée, à revoir si un faux positif apparaît.
    ///
    /// ## ⚠️ La liste est FRANÇAISE, et l'app est livrée en cinq langues
    ///
    /// Le corpus de développement est à 100 % en français : `eois`, `aux`, `ait` n'ont de sens que
    /// là. L'anglais et l'espagnol se contentent de `s`/`es`, déjà présents ; l'italien (`-i`) et
    /// l'allemand (`-en`/`-n`) ont été ajoutés pour eux. Mesuré : ces trois-là ne changent **rien**
    /// sur le corpus français — coût nul, couverture gagnée.
    ///
    /// ⛔ C'est le même angle mort qu'en 486 : un défaut de langue est invisible depuis une machine
    /// française. Ne pas les ajouter aurait livré un élargissement qui ne marche que chez nous, sans
    /// que rien ne le signale. Les formes DÉRIVÉES (et non seulement fléchies) des quatre autres
    /// langues restent, elles, non couvertes — assumé, faute de corpus pour les mesurer.
    ///
    /// ⛔ Ce réglage change la SÉLECTION des articles, pas seulement l'affichage : un terme y gagne
    /// des articles que le pipeline ne retenait pas avant.
    static let suffixesAdmis = [
        "s", "es", "x",                       // pluriels
        "ne", "nes",                          // féminins (citoyen → citoyenne)
        "ique", "iques", "isme",              // adjectifs/noms dérivés (climat, robot, volcan)
        "er", "ent", "ait", "ee", "ees", "eur", "eurs",   // formes verbales (transport → transporter)
        "eois", "eoise", "eoises",            // gentilés (Fribourg → fribourgeois)
        "ale", "aux",                         // ⚠️ raisonnés, non mesurés
        "i", "en", "n",                       // pluriels italien (-i) et allemand (-en/-n)
    ]

    /// **L'alternance des suffixes, construite UNE fois.** Elle ne dépend que de `suffixesAdmis` :
    /// la trier et la joindre à chaque appel refaisait le même travail des dizaines de milliers de
    /// fois par passe (32 règles × la fenêtre 48 h du tableau de bord).
    ///
    /// ⚠️ Les plus longs d'abord : `(?:s|ees)` sur « transportees » essaierait `s` en premier. Le
    /// retour arrière du moteur le rattraperait grâce au `\b` final, mais l'ordre explicite évite
    /// de dépendre d'un détail d'implémentation.
    static let alternanceSuffixes: String = suffixesAdmis
        .sorted { $0.count > $1.count }
        .joined(separator: "|")

    /// **Terme normalisé + expression compilée, mis en cache par terme brut.**
    ///
    /// ## Pourquoi
    ///
    /// `matchTerme` normalisait le terme, rebâtissait le motif et le faisait **recompiler** par ICU
    /// à chaque appel — `range(of:options:.regularExpression)` compile son motif à chaque fois. Sur
    /// le Mac mini, `calculerEtPersisterTableauBord()` occupe un cœur pendant 4 minutes toutes les
    /// 5 minutes (34,8 % d'un cœur en continu, mesuré le 05/09/2026), et c'est là que tout part :
    /// un appel par (article, terme).
    ///
    /// ⚠️ **La clé est le terme BRUT**, pas normalisé : normaliser pour trouver la clé aurait gardé
    /// le coût qu'on cherche à supprimer. Deux graphies d'un même terme occupent donc deux entrées —
    /// elles sont peu nombreuses, et le motif compilé, lui, est identique.
    ///
    /// ⚠️ Les échecs de compilation sont mémorisés eux aussi (valeur `nil`) : un terme vide ou
    /// impossible ne doit pas retenter à chaque article.
    ///
    /// ⛔ **Le cache n'expire pas, il se vide.** Les termes viennent des règles de mots-clés (32 sur
    /// le mini) et des recherches : leur nombre est borné en pratique. Le plafond n'est là que pour
    /// qu'un appelant inattendu — une boucle sur des milliers de libellés — ne le fasse pas enfler
    /// sans fin. Purge en bloc plutôt qu'une LRU : à ce volume, la comptabilité coûterait plus cher
    /// que ce qu'elle économiserait.
    private final class CacheTermes: @unchecked Sendable {
        private let verrou = NSLock()
        private var table: [String: Compile?] = [:]
        private static let plafond = 1024

        struct Compile { let terme: String; let regex: NSRegularExpression }

        func compile(_ terme: String) -> Compile? {
            verrou.lock()
            if let deja = table[terme] { verrou.unlock(); return deja }
            verrou.unlock()

            var valeur: Compile?
            let t = KeywordMatcher.normalize(terme)
            if !t.isEmpty {
                let motif = "\\b" + NSRegularExpression.escapedPattern(for: t)
                    + "(?:" + KeywordMatcher.alternanceSuffixes + ")?\\b"
                if let regex = try? NSRegularExpression(pattern: motif) {
                    valeur = Compile(terme: t, regex: regex)
                }
            }

            verrou.lock()
            if table.count >= Self.plafond { table.removeAll(keepingCapacity: true) }
            table[terme] = valeur
            verrou.unlock()
            return valeur
        }
    }

    private static let cacheTermes = CacheTermes()

    /// ⛔ **Un pré-filtre littéral a été essayé, et la mesure l'a REFUSÉ.** L'idée paraissait sûre :
    /// le motif étant `\b<terme>(?:suffixe)?\b`, tout appariement contient le terme tel quel, donc
    /// `haystack.range(of: terme) == nil` permettait de sauter le moteur ICU sans changer un seul
    /// résultat. Le raisonnement est juste ; le gain est négatif. Banc du 07/09 (1 500 articles ×
    /// 32 règles = 48 000 appels) : **8,3 µs/appel avec le pré-filtre contre 2,0 µs sans lui**.
    /// `String.range(of:)` compare par équivalence canonique Unicode — sur un champ de ~700
    /// caractères, il coûte quatre fois l'expression compilée qu'il prétendait éviter.
    static func matchTerme(_ terme: String, dans haystack: String) -> Bool {
        guard let c = cacheTermes.compile(terme) else { return false }
        return c.regex.firstMatch(
            in: haystack, options: [],
            range: NSRange(haystack.startIndex..., in: haystack)) != nil
    }
}
