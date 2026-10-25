// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/TermesGeneriquesNER.swift (commit 58fb14e9, 25/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Termes **génériques** que le NER prend parfois pour des entités (« Etat », « gouvernement »,
/// « police »…) : noms communs, demonymes, titres — jamais de vraies entités nommées, jamais
/// enrichissables par Wikidata.
///
/// Dans `FornewsModels` (comme [[PaireDePays]]) car partagé par DEUX consommateurs qui ne peuvent
/// pas dépendre l'un de l'autre :
/// - `FiltreEntitesNER` (FornewsAI) — bloque les **nouvelles** détections ;
/// - `NettoyageEntites` (FornewsServices) — supprime rétroactivement celles créées **avant** le
///   filtre ou synchronisées depuis un autre appareil.
public enum TermesGeneriquesNER {

    /// Retire un **titre / fonction / gentilé en tête** d'un nom de PERSONNE (« président ukrainien
    /// Volodymyr Zelensky » → « Volodymyr Zelensky »). Partagé par les DEUX consommateurs : le filtre
    /// NER (à la création) et `NettoyageEntites` (renommage rétroactif des entités existantes).
    ///
    /// Règle **générale** (pas de liste exhaustive de gentilés) : un nom de personne a ses jetons
    /// capitalisés ; les titres/rôles/gentilés/articles qui le précèdent sont en minuscule (ou un
    /// titre/rôle connu, même capitalisé en début de phrase). On retire la tête tant que le jeton est
    /// en minuscule OU un titre/rôle connu (`stopList`/`titres`), à condition qu'il reste un jeton
    /// capitalisé (le nom réel) — jamais de valeur vidée, et on s'arrête au premier vrai jeton de nom
    /// propre (« Charles de Gaulle » reste intact : « Charles » est capitalisé d'emblée).
    public static func retirerTitrePersonne(_ valeur: String) -> String {
        var jetons = valeur.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while jetons.count > 1, let premier = jetons.first {
            let estMinuscule = premier.first.map { !$0.isUppercase } ?? false
            let n = normaliser(premier)
            // « Dr. Alan Grant » : le titre suivi d'un point ; « CEO Mark Zuckerberg » : une fonction (04/10/2026,
            // cf. `ControlesEntites`). « CEO de Sulzer » est rejeté avant d'arriver ici (`fonctionSansNom`).
            let sansPoint = n.replacingOccurrences(of: ".", with: "")
            let estTitreConnu = stopList.contains(n) || titres.contains(n) || titres.contains(sansPoint)
                || ControlesEntites.fonctions.contains(sansPoint)
            guard estMinuscule || estTitreConnu else { break }
            guard jetons.dropFirst().contains(where: { $0.first?.isUppercase == true }) else { break }
            jetons.removeFirst()
        }
        return jetons.joined(separator: " ")
    }

    /// Vrai si la valeur (brute) est un terme générique ou un titre/civilité seul.
    public static func estGenerique(_ valeur: String) -> Bool {
        let n = normaliser(valeur)
        if stopList.contains(n) { return true }
        let sansPoint = n.replacingOccurrences(of: ".", with: "")
        return titres.contains(n) || titres.contains(sansPoint)
    }

    /// Normalisation cohérente avec `KeywordMatcher.normalize` / `FiltreEntitesNER.normaliser`
    /// (minuscules, sans diacritiques, apostrophes unifiées, espaces compactés).
    private static func normaliser(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Noms communs, demonymes et termes génériques à rejeter.
    /// Formes normalisées (minuscules, sans diacritiques). Couvre le bruit observé en démo
    /// (« frère », « mairie », « organisateurs », « primature », « armateurs », « grecs »)
    /// plus une petite liste générique FR/EN.
    public static let stopList: Set<String> = [
        // Étiquettes posées par l'extraction (Lecture fidèle, 02/10/2026) : jamais des entités.
        "legende", "question", "reponse",
        // Bruit observé en démo
        "frere", "freres", "soeur", "soeurs", "mairie", "mairies",
        "organisateur", "organisateurs", "organisatrice", "organisatrices",
        "primature", "armateur", "armateurs", "grec", "grecs", "grecque", "grecques",
        // Liens de parenté / personnes génériques
        "pere", "mere", "fils", "fille", "enfant", "enfants", "parent", "parents",
        "famille", "epoux", "epouse", "mari", "femme", "ami", "amis", "voisin", "voisins",
        // Rôles / fonctions génériques (sans nom propre attaché)
        "president", "presidente", "ministre", "ministres", "maire", "depute", "deputes",
        "senateur", "senateurs", "directeur", "directrice", "porte-parole", "journaliste",
        "journalistes", "policier", "policiers", "manifestant", "manifestants",
        "habitant", "habitants", "citoyen", "citoyens", "victime", "victimes",
        "responsable", "responsables", "dirigeant", "dirigeants", "membre", "membres",
        "employe", "employes", "salarie", "salaries", "ouvrier", "ouvriers",
        // Institutions génériques (sans nom propre)
        "gouvernement", "etat", "etats", "pays", "ville", "villes", "region", "regions",
        "commune", "communes", "police", "armee", "parlement", "assemblee", "senat",
        "tribunal", "justice", "ecole", "ecoles", "hopital", "hopitaux", "entreprise",
        "entreprises", "societe", "societes", "organisation", "organisations",
        "association", "associations", "club", "equipe", "equipes",
        // Demonymes FR courants
        "francais", "francaise", "francaises", "allemand", "allemands", "allemande",
        "americain", "americains", "americaine", "anglais", "anglaise", "italien",
        "italiens", "italienne", "espagnol", "espagnols", "espagnole", "russe", "russes",
        "chinois", "chinoise", "japonais", "japonaise", "europeen", "europeens",
        "europeenne", "africain", "africains", "africaine", "arabe", "arabes",
        // Demonymes EN courants
        "french", "german", "germans", "american", "americans", "english", "british",
        "italian", "italians", "spanish", "russian", "russians", "chinese", "japanese",
        "european", "europeans", "african", "africans", "greek", "greeks",
        // ⚠️ **Complétés le 15/08 — « swiss » manquait.** Signalé par Patrick (§8) : l'entité
        // « Swiss » existait en `gpe` ET en `person`, jamais en `org`. Vérification sur le store :
        // le `gpe` portait la fiche d'un NOM DE FAMILLE (Q37506260), le `person` celle d'un RAPPEUR
        // ALLEMAND (Q15849757). Deux entités fausses issues d'un simple adjectif de nationalité,
        // dans une liste qui contenait déjà `french`, `german`, `italian` — une omission, pas une
        // règle nouvelle.
        //
        // ⛔ Comparaison à l'ÉGALITÉ sur la valeur normalisée : « suisse » n'est PAS dans la liste
        // et le pays reste donc intact, de même que « Swiss Life » ou « Swiss Re », qui portent un
        // complément. Seul l'adjectif nu tombe.
        "swiss", "dutch", "belgian", "belgians", "portuguese", "polish", "swedish", "norwegian",
        "danish", "finnish", "austrian", "austrians", "canadian", "canadians", "australian",
        "australians", "brazilian", "brazilians", "mexican", "mexicans", "indian", "indians",
        "turkish", "irish", "scottish", "welsh", "ukrainian", "ukrainians", "israeli", "israelis",
        "iranian", "iranians", "syrian", "syrians", "egyptian", "moroccan", "algerian",
        "korean", "koreans", "vietnamese", "thai", "swisses",
    ]

    /// **Mots-outils** — déterminants, conjonctions, prépositions, pronoms.
    ///
    /// ⚠️ Signalé le 02/08, capture à l'appui : « le », « mais », « sur » et « Le » étaient
    /// SURLIGNÉS comme entités dans le corps d'un article, et deux d'entre eux ont fini par donner
    /// son nom à une histoire détectée — « Le · Mais ». La grammaire d'une langue n'est pas du
    /// vocabulaire : ces mots ne peuvent désigner personne ni rien, quel que soit le contexte.
    ///
    /// ⚠️ **Le piège est la MAJUSCULE de début de phrase.** « Le 22 juillet 1956… » présente « Le »
    /// exactement comme un nom propre, et la règle « un nom propre porte au moins une majuscule »
    /// le laissait passer. C'est pour cela que le rejet doit se faire sur le MOT, pas sur la casse.
    ///
    /// ⚠️ **Comparé au mot ENTIER, jamais à un préfixe** : « Le Monde », « La Poste », « The Verge »
    /// et « Los Angeles » commencent tous par un mot-outil et sont de vraies entités.
    public static let motsOutils: Set<String> = [
        // ⚠️ **Formes ÉLIDÉES**, oubliées de ma première liste — signalé le 02/08 par une histoire
        // détectée nommée « Le · L' ». La normalisation unifie les apostrophes courbes en droites
        // mais ne les SUPPRIME pas : « L' » devient « l' », qui n'était dans aucune liste. Les
        // formes pleines ne suffisent donc pas, il faut les élisions telles qu'elles s'écrivent.
        "l'", "d'", "j'", "n'", "s'", "c'", "m'", "t'", "qu'", "jusqu'", "lorsqu'", "puisqu'",
        // Et les mêmes réduites à leur lettre, si une apostrophe se perd en amont.
        "l", "d", "j", "n", "s", "c", "m", "t", "qu",
        // Français — déterminants et articles
        "le", "la", "les", "un", "une", "des", "du", "de", "au", "aux", "ce", "cet", "cette",
        "ces", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos",
        "votre", "vos", "leur", "leurs", "quel", "quelle", "quels", "quelles",
        // Français — conjonctions, prépositions, adverbes de liaison
        "et", "ou", "mais", "donc", "or", "ni", "car", "que", "qui", "quoi", "dont", "ou",
        "sur", "sous", "dans", "par", "pour", "avec", "sans", "vers", "chez", "entre", "contre",
        "depuis", "pendant", "avant", "apres", "selon", "malgre", "hors", "parmi",
        "aussi", "ainsi", "alors", "encore", "toujours", "jamais", "puis", "ensuite", "enfin",
        "tres", "plus", "moins", "bien", "tout", "tous", "toute", "toutes", "meme", "memes",
        // Français — pronoms
        "il", "elle", "ils", "elles", "on", "nous", "vous", "je", "tu", "moi", "toi", "lui",
        "eux", "se", "sy", "en", "y", "ceci", "cela", "celui", "celle", "ceux",
        // Anglais — les articles anglais arrivent par les sources anglophones
        "the", "a", "an", "and", "or", "but", "so", "if", "then", "than", "as", "at", "by",
        "for", "from", "in", "into", "of", "on", "to", "with", "without", "over", "under",
        "this", "that", "these", "those", "it", "its", "he", "she", "they", "we", "you",
        "his", "her", "their", "our", "your", "my", "not", "no", "yes", "all", "some", "any",
    ]

    /// Titres / civilités à rejeter lorsqu'ils apparaissent seuls.
    public static let titres: Set<String> = [
        "m", "mr", "mme", "mlle", "dr", "pr", "me", "sir", "lord", "lady",
        "monsieur", "madame", "mademoiselle", "docteur", "professeur", "maitre",
        "saint", "sainte", "st", "ste",
    ]
}
