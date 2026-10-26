// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsPipeline/ConsignesAnalyste.swift (commit b2d8c521, 26/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// **Les consignes du rapport d'analyste — une par section, jamais toutes ensemble.**
///
/// Spécification donnée par Patrick le 10/09/2026, adaptée au modèle EMBARQUÉ.
///
/// ## ⛔ Pourquoi le prompt d'origine ne peut pas être envoyé tel quel
///
/// Il fait près de **9 000 caractères**. La fenêtre du modèle on-device vaut 4 096 jetons, soit
/// ~14 000 caractères pour les consignes, les extraits **et** la réponse (cf. `BudgetContexteLLM`).
/// Le prompt seul consommerait les deux tiers de la fenêtre avant le premier article.
///
/// ⭐ Ce n'est pas une limitation à contourner, c'est ce qui dicte la forme : **une section à la
/// fois**, avec la seule consigne dont cette section a besoin. C'est exactement ce pour quoi
/// `RedactionPhasee` existe.
///
/// ## Ce qui n'est PAS demandé au modèle, et pourquoi
///
/// ⛔ Ni sources, ni liens, ni images, ni carte, ni camembert, ni coordonnées, ni typologie
/// d'entités. L'app détient tout cela et l'écrit elle-même — doctrine déjà inscrite dans
/// `ServiceRapports.Matiere` : « posés par le CODE, jamais par le modèle ». Un lien inventé est
/// invérifiable par le lecteur ; un lien composé par le code ne peut pas l'être.
///
/// ⚠️ Le prompt d'origine demande au modèle de reconstruire la typologie NER, de résoudre des
/// coordonnées et de compter des corroborations. Ce sont des données que l'app possède
/// (`TypeEntite`, Wikidata, `Corroboration`) : les redemander, c'est jeter une certitude pour
/// obtenir une approximation.
public enum ConsignesAnalyste {

    /// Les sections du rapport, dans l'ordre. ⭐ **Fixe, contrairement au compte rendu** dont les
    /// aspects se découvrent : ici la structure EST la spécification, elle n'a pas à être inventée.
    public enum Section: String, CaseIterable, Sendable {
        case resumeExecutif
        /// **Le titre interprétatif (H1).** Rédigé APRÈS la synthèse et à partir d'elle : un titre
        /// énonce une thèse, et la thèse est ce que la synthèse vient d'écrire et de faire vérifier.
        /// ⚠️ Pas de prose : il ne passe pas par `retirerDejaDit`, qui le jugerait redit.
        case titre
        case pointsCles
        /// **La dimension humaine ou matérielle** — une exigence du prompt de veille de Patrick
        /// (03/10/2026) : au moins un point clé sur ceux qui portent ou subissent les effets.
        case dimensionHumaine
        /// **L'effet d'entraînement** : ce que le sujet fait aux domaines VOISINS, lu dans les
        /// articles qui le citent au passage (`Matiere.peripheriques`), pas dans ceux qui en parlent.
        case effetEntrainement
        case perspectives
        case resonances
        /// ⛔ **Plus de section « diagramme » depuis le 03/10/2026** : le graphe de la cartographie est
        /// tracé par le CODE, à partir des co-citations (`ServiceRapports.coCiter`).
        /// **Les noms des phases de la chronologie.** Le CODE découpe la période (par les plus grands
        /// silences entre deux jours d'actualité) ; le modèle ne fait que NOMMER chaque morceau.
        /// ⚠️ Ce n'est pas de la prose : la sortie est une liste numérotée, lue
        /// par le code, et un nom invalide retombe sur les dates de la phase.
        case phases
        /// **Révision, phases 1-2 : chaque phrase confrontée au corpus de SA section** (03/10/2026).
        /// Le modèle désigne les extraits qui la soutiennent, ou « NON ». Sortie lue par le code.
        case verification
        /// **Révision, phase 4 : la relecture critique.** Le modèle DÉSIGNE les phrases à retirer
        /// (redites, phrases creuses, formules) ; il n'en écrit aucune.
        case critique
        /// **Revue de presse : nommer les fils d'actualité** (03/10/2026). La sortie est une liste lue par le code.
        case fils
        /// **Révision, phase 5 : la retouche contrôlée** d'un paragraphe qui a perdu des phrases.
        /// ⛔ Retenue seulement si elle n'ajoute rien et repasse la vérification (`RevisionAnalyste`).
        case retouche
        /// La traduction d'une section rédigée dans la mauvaise langue (03/10/2026). ⚠️ Hors de l'ancrage : les noms
        /// translittérés changent (« Kiev » → « Kyiv ») ; la révision vérifie ensuite chaque phrase contre les articles.
        case traduction
        /// **Les titres des points clés en extraits** (04/10/2026) : une phrase-titre par fil, qui dit ce qui se passe.
        case titresPoints
        /// **Le chapeau** (04/10/2026) : la synthèse courte qui résume les citations des points clés.
        case chapeau
    }

    /// ⚠️ **Plafond par consigne.** Une consigne longue est une consigne qui vole sa place aux
    /// extraits — et sans extraits, le modèle n'a rien à analyser. Éprouvé par un test.
    public static let plafondCaracteres = 900

    /// **Le NOM de la langue, en français, pour la consigne** (03/10/2026, essais en cinq langues : l'app passe le
    /// CODE — « en » —, la consigne disait « Tu rédiges, en en, … » et le modèle écrivait en français ; seul le cadre
    /// posé par le code était en anglais). Un nom déjà donné (« français ») passe tel quel.
    static func nomLangue(_ codeOuNom: String) -> String {
        switch codeOuNom.lowercased() {
        case "fr", "fr-fr", "fr-ch": "français"
        case "en", "en-us", "en-gb": "anglais"
        case "de", "de-de", "de-ch": "allemand"
        case "es", "es-es": "espagnol"
        case "it", "it-it", "it-ch": "italien"
        default: codeOuNom
        }
    }

    /// **L'ordre de langue, écrit DANS la langue cible**, en fin de consigne (03/10/2026 : avec « Tu rédiges, en
    /// anglais » seulement, le modèle suivait les extraits français — titre en anglais, synthèse en français).
    static func ordreDeLangue(_ codeOuNom: String) -> String {
        switch nomLangue(codeOuNom) {
        case "anglais": "\nWrite in English only, even when the excerpts are in French."
        case "allemand": "\nSchreibe nur auf Deutsch, auch wenn die Auszüge auf Französisch sind."
        case "espagnol": "\nEscribe solo en español, aunque los extractos estén en francés."
        case "italien": "\nScrivi solo in italiano, anche se gli estratti sono in francese."
        default: ""
        }
    }

    /// Le code de la langue (« en »), depuis un code ou un nom.
    static func codeLangue(_ codeOuNom: String) -> String {
        switch nomLangue(codeOuNom) {
        case "anglais": "en"
        case "allemand": "de"
        case "espagnol": "es"
        case "italien": "it"
        default: "fr"
        }
    }

    /// **La consigne de traduction d'une section rédigée dans la mauvaise langue**, écrite dans la langue cible.
    /// ⚠️ Le marqueur §TITRE§ n'est NOMMÉ que si le texte en porte un (03/10/2026 : nommé toujours, le modèle en ajoutait
    /// un, traduit — « §TITEL§ », « §TÍTULO§ » — en tête de chaque section).
    static func traduction(_ codeOuNom: String, avecTitre: Bool = false) -> String {
        let (base, titre): (String, String) = switch codeLangue(codeOuNom) {
        case "en": ("Translate the text into English. Keep every name, number and date exactly. Add nothing, remove nothing. Return the translation only.",
                    " Keep the marker §TITRE§ unchanged at the start of its line.")
        case "de": ("Übersetze den Text ins Deutsche. Behalte alle Namen, Zahlen und Daten genau bei. Füge nichts hinzu, lass nichts weg. Gib nur die Übersetzung zurück.",
                    " Lass die Markierung §TITRE§ unverändert am Zeilenanfang stehen.")
        case "es": ("Traduce el texto al español. Conserva exactamente todos los nombres, cifras y fechas. No añadas ni quites nada. Devuelve solo la traducción.",
                    " Deja la marca §TITRE§ sin cambios al inicio de su línea.")
        case "it": ("Traduci il testo in italiano. Mantieni esattamente tutti i nomi, i numeri e le date. Non aggiungere né togliere nulla. Restituisci solo la traduzione.",
                    " Lascia il marcatore §TITRE§ invariato all'inizio della sua riga.")
        default: ("Traduis le texte en français. Garde exactement tous les noms, chiffres et dates. N'ajoute rien, ne retire rien. Rends seulement la traduction.",
                  " Laisse le marqueur §TITRE§ tel quel en tête de sa ligne.")
        }
        return base + (avecTitre ? titre : "")
    }

    /// La règle qui vaut pour TOUTES les sections. Répétée à chaque appel, à dessein : le modèle
    /// ne voit qu'une section à la fois et n'a aucune mémoire de la précédente.
    static func socle(_ langue: String) -> String {
        """
        Tu rédiges, en \(langue), une section d'un RAPPORT D'ANALYSE de presse à partir des extraits.
        ⛔ Ni titre de section, ni liste de sources, ni lien, ni image, ni diagramme : ils sont ajoutés après toi.
        ⛔ Tout nom propre, chiffre et date doit figurer dans les extraits : n'en invente ni n'en déduis aucun.
        ⛔ Prose, sans liste à puces.
        ⛔ Un extrait marqué [allégation] reste attribué à sa source (« selon… »), jamais affirmé.
        \(styleSansTics)
        """
    }

    /// **Les tics de langage des IA, interdits** — demandé par Patrick le 03/10/2026 : « éviter les
    /// tics de langages des IA dans le texte des rapports produits ».
    ///
    /// ⚠️ Une ligne, pas un catalogue : chaque caractère de consigne est pris aux extraits (cf.
    /// `plafondCaracteres`). On nomme les tics les plus fréquents du modèle embarqué ; ceux qui se
    /// reconnaissent mécaniquement en ouverture de phrase sont EN PLUS retirés par le code
    /// (`GenerateurRapportAnalyste.sansTics`) — une interdiction énoncée n'est jamais une
    /// interdiction tenue.
    static let styleSansTics = """
    ⛔ Style sobre, sans tics : ni « il est important de noter », ni « en conclusion », ni « témoigne de », ni « crucial », ni question rhétorique, ni triade d'adjectifs.
    """

    /// **La consigne d'une section.** `sujet` nomme l'aspect pour un point clé ou une perspective.
    public static func consigne(_ s: Section, langue codeOuNom: String, sujet: String? = nil) -> String {
        let langue = nomLangue(codeOuNom)
        // ⭐ Hors du français, la consigne est écrite DANS la langue du rapport (04/10/2026) : cf. `ConsignesLocales`.
        if let locale = ConsignesLocales.consigne(s, code: codeLangue(codeOuNom), sujet: sujet) { return locale }
        let propre: String
        switch s {
        case .chapeau:
            propre = """
            Écris UN court paragraphe : UNE phrase par extrait, dans leur ordre, qui dit l'essentiel de ce qu'il rapporte. Ce qui n'est qu'affirmé reste attribué (« selon… »). Ni date, ni chiffre qui ne soit dans l'extrait.
            """
        case .resumeExecutif:
            propre = """
            Écris TROIS courts paragraphes séparés par une ligne vide. 1) Ce qui se passe : les phases du déroulé (en tête), dans l'ordre, nommées ou datées, reformulées. 2) Pourquoi c'est important. 3) Ce qui vient. « Ensuite », « puis », « tandis que » : seulement si les dates l'attestent. Ne dédouble aucun acteur.
            """
        case .titre:
            // ⛔ Pas de socle : il interdit les titres. Ses propres interdits, plus courts.
            return """
            Propose UN titre de rapport, en \(langue), de 5 à 12 mots, qui énonce ce que le texte fourni révèle : une thèse, pas un simple sujet.
            Rends le titre seul, sur une ligne, sans guillemets, sans deux-points, sans point final ; garde les apostrophes et les virgules.
            ⛔ Tout nom propre doit figurer dans le texte fourni. Aucune date.
            \(styleSansTics)
            """ + ordreDeLangue(codeOuNom)
        case .pointsCles:
            propre = """
            Analyse \(sujet ?? "l'aspect dominant du corpus"). Première ligne : un titre de 8 mots au plus, avec un verbe, qui dit ce qui se passe. Puis UN paragraphe : ce qui se joue, pas le récit des faits.
            """
        case .dimensionHumaine:
            propre = """
            Écris UN paragraphe sur la dimension humaine ou matérielle du corpus : qui porte ou subit les effets — personnes, métiers, usagers, coûts, ressources, infrastructures. Si les extraits n'en disent rien, réponds seulement : RIEN.
            """
        case .effetEntrainement:
            propre = """
            Ces extraits citent \(sujet ?? "le sujet") au passage, depuis d'autres domaines. Écris UN paragraphe sur l'effet d'entraînement : où et comment le sujet déborde sur ces domaines voisins. Si les extraits n'en disent rien, réponds seulement : RIEN.
            """
        case .perspectives:
            // ⛔ **« Cite cette date » a été RETIRÉ le 10/09/2026.** La consigne exigeait un fait
            // daté puis ordonnait d'en citer la date ; sur deux générations réelles consécutives,
            // le modèle qui n'en trouvait pas en a FABRIQUÉ une — « 10 octobre 2024 » puis
            // « du 17 au 22 octobre 2024 », alors que le corpus entier ne porte que 2026.
            //
            // 🔑 L'ordre créait l'invention. Une consigne qui exige une donnée absente ne rend pas
            // le modèle rigoureux, elle le rend inventif. On demande donc un fait, pas une date, et
            // on interdit explicitement la date absente — vérifié en plus par le CODE
            // (`GenerateurRapportAnalyste.anneesInventees`), parce qu'une interdiction énoncée
            // n'est jamais une interdiction tenue.
            // ⛔ 03/10/2026, rapport « Intelligence artificielle » : la liste « échéance annoncée,
            // décision prise, signal faible » était RECOPIÉE — les trois perspectives commençaient par
            // « La décision prise par… » et parlaient de « signal faible ». Une consigne qui énumère
            // des mots les met dans la bouche du modèle.
            propre = """
            Première ligne : un titre de 8 mots au plus, au futur ou au conditionnel. Puis UN paragraphe sur \(sujet ?? "la suite probable") : ce que cela ouvre, sans commencer par « La décision ». ⛔ N'écris AUCUNE date qui ne figure pas dans les extraits. Sans fait qui engage la suite, dis que le corpus ne permet pas de se prononcer.
            """
        case .resonances:
            // ⭐ **Les voix critiques** (03/10/2026) remplacent les résonances, jugées creuses à la relecture
            // du sixième rapport. Le cas garde son nom : il occupe la même place dans le rapport.
            propre = """
            Écris UN paragraphe sur les voix critiques ou sceptiques des extraits : qui doute, alerte ou s'oppose, et sur quoi. Attribue chaque position à son auteur (« selon… », « X estime que… »). Sans voix critique dans les extraits, réponds seulement : RIEN.
            """
        case .verification:
            // ⛔ Pas de socle : la sortie est une liste, lue par le code. ⭐ « même dans une autre
            // langue » : les extraits mêlent cinq langues, le rapport n'en parle qu'une.
            return """
            Tu vérifies un rapport contre ses sources. Tu reçois des EXTRAITS numérotés [E1], [E2]… puis des PHRASES numérotées P1, P2…
            Pour chaque phrase, dis si les extraits la soutiennent : son fait, ses noms, ses chiffres et ses dates doivent s'y trouver, même dans une autre langue. Une phrase qui interprète des faits soutenus est soutenue ; une phrase qui ajoute un fait absent ne l'est pas.
            ⛔ Elle n'est PAS soutenue si elle ordonne, ou rend simultanés, des faits que les dates [entre crochets] contredisent ; ni si elle affirme comme un fait ce qu'un extrait marqué [allégation] attribue à quelqu'un.
            Réponds une ligne par phrase et RIEN d'autre : « P3: E2,E5 » si elle est soutenue, avec les extraits qui la soutiennent ; « P4: NON » sinon.
            """
        case .critique:
            return """
            Tu relis un rapport dont les phrases sont numérotées P1, P2… Désigne les phrases à SUPPRIMER : celle qui redit ce qu'une phrase précédente a déjà dit, celle qui est creuse et n'apporte aucun fait, celle qui n'est faite que de formules toutes faites.
            Réponds par leurs numéros séparés par des virgules (exemple : P4, P9, P17), ou AUCUNE, et RIEN d'autre. Ne propose aucune réécriture.
            """
        case .traduction:
            return traduction(codeOuNom, avecTitre: true)
        case .titresPoints:
            // ⛔ Pas de socle : la sortie est une liste, lue par le code.
            let n = sujet ?? "plusieurs"
            return """
            Les titres d'articles fournis sont regroupés en \(n) groupes. Pour chaque groupe, écris en \(langue) un titre de 4 à 9 mots qui dit CE QUI SE PASSE : une phrase avec un verbe au présent, qui nomme qui ou quoi est concerné.
            Si les titres rapportent ce que quelqu'un AFFIRME, attribue-le (« X affirme… »). Ton neutre, sans effet de manchette.
            Réponds par \(n) lignes et RIEN d'autre, une par groupe, sous la forme : 1. Titre
            ⛔ Aucun nom propre qui ne figure dans les titres. Aucune date.
            """
        case .retouche:
            propre = """
            Ce paragraphe a perdu des phrases. Rends-le fluide : relie les phrases restantes et corrige les transitions devenues fausses. ⛔ N'ajoute AUCUN fait, nom, chiffre ni date ; ne change le sens d'aucune phrase ; garde chacune reconnaissable. Rends le paragraphe seul.
            """
        case .fils:
            // ⛔ Pas de socle : la sortie est une liste, lue par le code.
            let n = sujet ?? "plusieurs"
            return """
            Les titres d'articles fournis sont regroupés en \(n) groupes. Donne à chaque groupe un intitulé de 2 à 6 mots, en \(langue), qui dit de quoi il parle, sur un ton neutre et factuel.
            Réponds par \(n) lignes et RIEN d'autre, une par groupe, sous la forme : 1. Intitulé
            ⛔ Aucun nom propre qui ne figure dans les titres.
            """ + ordreDeLangue(codeOuNom)
        case .phases:
            // ⛔ Pas de socle : la sortie est une liste, lue par le code.
            let n = sujet ?? "plusieurs"
            return """
            Les faits fournis sont regroupés en \(n) phases, dans l'ordre du temps. Donne à chaque phase un nom de 2 à 5 mots, en \(langue), qui dit ce qui s'y joue, sur un ton neutre et factuel : ni « secret », ni « complot », ni « choc », aucun effet de manchette.
            Réponds par \(n) lignes et RIEN d'autre, une par phase, sous la forme : 1. Nom
            ⛔ Aucun nom propre ni date qui ne figure dans les faits.
            """ + ordreDeLangue(codeOuNom)
        }
        return socle(langue) + "\n" + propre + ordreDeLangue(codeOuNom)
    }

    /// **Le champ sémantique, RÉDUIT à ce que le corpus active.**
    ///
    /// ⛔ Les 60 termes du prompt d'origine coûteraient ~700 caractères à chaque appel, pour une
    /// liste dont le modèle n'utilisera que quelques entrées. On ne verse que les thèmes dont un mot
    /// apparaît réellement dans les extraits — le reste est du bruit qui prend la place des faits.
    public static func champActive(_ extraits: [String], maximum: Int = 6) -> [String] {
        let corpus = extraits.joined(separator: " ").folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return champSemantique.filter { theme in
            corpus.contains(theme.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
        }.prefix(maximum).map { $0 }
    }

    /// Le champ de référence donné par Patrick. ⚠️ Jamais versé en entier : cf. `champActive`.
    public static let champSemantique = [
        "humain", "vie", "mort", "santé", "environnement", "espace", "liberté", "information",
        "désinformation", "communication", "langage", "intelligence", "ignorance", "recherche",
        "science", "robot", "ordinateur", "code", "nature", "réalité", "société", "droit",
        "pouvoir", "politique", "éthique", "responsable", "innovation", "outil", "danger",
        "maladie", "sécurité", "cinéma", "jeu", "art", "loisir", "simulation", "virtuel",
        "imaginaire", "consommation", "hier", "aujourd'hui", "demain", "futur", "temps",
        "histoire", "mémoire", "culture", "éducation", "apprentissage", "développement",
        "progrès", "créativité", "évolution", "bonheur", "émotion", "conscience", "identité",
    ]
}
