// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsAI/FiltreEntitesNER.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation
import NaturalLanguage

/// Post-filtrage léger et **pur** (donc testable headless, contrairement au NER Foundation Models)
/// appliqué aux entités candidates produites par le LLM.
///
/// Deux rôles, en cohérence avec la dédup existante
/// (`TraitementPipeline.cleCanonique` et `WikimediaService.fusionnerSiDoublon`) :
/// 1. Rejeter le bruit observé en démo — noms communs, titres, termes génériques,
///    valeurs tout en minuscules ou trop courtes.
/// 2. Fusionner les variantes orthographiques proches du même nom et type
///    (ex. « Alexander Zverev » / « Alexandr Zverev ») via une distance de Levenshtein faible.
public enum FiltreEntitesNER {

    // MARK: Configuration

    /// Types considérés comme « noms propres » : on y exige au moins une majuscule.
    /// (`date` / `money` ne sont pas des noms propres et ne sont pas soumis à cette règle.)
    ///
    /// ⚠️ `maladie` en est volontairement ABSENT : « grippe aviaire », « variole du singe » ou
    /// « rougeole » sont des noms communs, et exiger une majuscule les jetterait toutes — alors que
    /// ce sont exactement les entités que le type sert à suivre.
    static let typesNomPropre: Set<TypeEntite> = [
        .person, .org, .gpe, .loc, .product, .event, .work,
    ]

    /// Noms communs, demonymes et termes génériques à rejeter — liste PARTAGÉE, déplacée dans
    /// `FornewsModels` ([[TermesGeneriquesNER]]) pour que `NettoyageEntites` (FornewsServices,
    /// qui ne peut pas dépendre de FornewsAI) supprime rétroactivement les entités créées avant
    /// ce filtre. Alias locaux conservés pour les tests et les appels internes.
    static let stopList = TermesGeneriquesNER.stopList

    /// Titres / civilités à rejeter lorsqu'ils apparaissent seuls (cf. [[TermesGeneriquesNER]]).
    static let titres = TermesGeneriquesNER.titres

    // MARK: API publique

    /// Filtre une liste d'entités candidates puis fusionne les variantes proches.
    /// - Parameters:
    ///   - entites: entités candidates (typiquement issues du LLM).
    ///   - longueurMin: longueur minimale (en caractères) de la valeur normalisée.
    ///   - seuilFusion: distance de Levenshtein maximale pour fusionner deux variantes du même type.
    ///   - longueurMinFusion: longueur minimale de la plus longue valeur pour autoriser une fusion
    ///     approximative (évite de fusionner deux noms courts distincts, ex. « Paris » / « Maris »).
    public static func filtrer(
        _ entites: [EntiteDetectee],
        texteSource: String? = nil,
        longueurMin: Int = 2,
        seuilFusion: Int = 2,
        longueurMinFusion: Int = 8
    ) -> [EntiteDetectee] {
        // Ancrage anti-hallucination : le NER est de l'EXTRACTION, pas de la génération. Toute entité
        // produite par le LLM doit réellement figurer dans le texte source ; sinon c'est un nom propre
        // inventé (ex. « Lana Del Rey » dans un article Star Wars) → on l'écarte.
        let texteNorm = texteSource.map(normaliser)
        // Sigles définis par leur développé entre parenthèses (« …de la navigation (SAN) ») :
        // ce sont des organisations, jamais des lieux. Calculé une fois sur le texte brut.
        let siglesOrg = texteSource.map(siglesOrganisations) ?? []
        let retenues = entites.compactMap { e -> EntiteDetectee? in
            guard estValide(e, longueurMin: longueurMin) else { return nil }
            if let t = texteNorm, !apparaitDans(t, e.valeur) { return nil }
            var corrige = e
            // Casse des PATRONYMES : la presse écrit souvent le nom de famille en CAPITALES, surtout
            // dans les signatures (« Marie DASPAS », « ELVIS COSTELLO ») → on remet en casse de nom
            // propre (« Marie Daspas », « Elvis Costello »). Limité au type `person` : les sigles/
            // acronymes (MITRE, USPTO…) sont d'autres types et restent intacts.
            // ⑤/② — un terme TECHNIQUE typé « personne » n'en est jamais une (« API », « CEO »,
            // « QR », « NAND »). Écarté avant même la normalisation de casse.
            if e.type == .person, estVocabulaireTechnique(e.valeur) { return nil }
            // ⑲ — une phrase qui OPPOSE deux noms propres n'est pas une entité.
            if estOppositionDeDeuxNomsPropres(e.valeur) { return nil }
            if e.type == .person {
                corrige.valeur = normaliserCassePersonne(retirerTitrePersonne(e.valeur))
            }
            // Queue de span parasite : articles/prépositions/adjectifs en minuscules qui ont débordé
            // du span (« Downing Street du nouveau » → « Downing Street », le « du nouveau » appartenant
            // à « du nouveau Premier ministre »). Épargne les particules capitalisées (« Nord de l'Europe »
            // garde « l'Europe », qui contient un « E »).
            if typesNomPropre.contains(corrige.type) {
                corrige.valeur = retirerQueueMinuscule(corrige.valeur)
            }
            // Un sigle abusivement classé lieu (« SAN » → rivière San) mais défini comme organisation
            // dans le texte → re-typage en `.org`. On ne touche QUE les `gpe`/`loc` (portée minimale).
            if (e.type == .gpe || e.type == .loc), siglesOrg.contains(normaliser(e.valeur)) {
                corrige.type = .org
            }
            return corrige
        }
        let sansPatronymesLieux = retirerLieuxComposantsDeNoms(retenues, texteNorm: texteNorm)
        let sansNomsDeCode = retirerNomsDeCode(sansPatronymesLieux, texteNorm: texteNorm)
        return fusionnerVariantes(sansNomsDeCode, seuilFusion: seuilFusion, longueurMinFusion: longueurMinFusion)
    }

    // MARK: Lieu = patronyme d'une personne (faux positif géo)

    /// Supprime un **lieu** (`gpe`/`loc`) qui n'est en réalité que le **patronyme (ou prénom) d'une
    /// personne** détectée dans le même article — ex. « Brenna » épinglé sur un village italien alors que
    /// c'est le nom de « Gabriel Brenna ». **Garde-fou anti-faux-positif** : on ne supprime QUE si la valeur
    /// du lieu **n'apparaît nulle part dans le texte en dehors du nom complet de la personne**. Ainsi
    /// « Washington » (ville) est conservé si l'article en parle vraiment, même s'il cite aussi « George
    /// Washington ». Sans texte source, on ne tranche pas (on garde).
    /// ⚠️ La règle elle-même vit dans `PatronymeLieu` (FornewsModels) : elle doit être appliquée
    /// **aux deux bouts** — ici à la création, et rétroactivement par `NettoyageEntites`, qui ne peut
    /// pas dépendre de FornewsAI. Sans le second, les entités créées avant ce filtre restent sur la
    /// carte : c'est exactement ce qui s'est produit avec « Brenna », encore épinglée en Italie le
    /// 22/07 alors que le filtre datait de la veille. Même patron que [[PaireDePays]].
    /// **Noms de code de systèmes pris pour des lieux** — « Golden Gate », nom de code de macOS 27,
    /// géolocalisé dans le détroit de San Francisco (audit du 18/08). La règle vit dans
    /// `NomDeCodeTech` (FornewsModels) et exige DEUX signaux : le nom, et un marqueur technologique
    /// dans le texte — sans quoi un incendie à Big Sur cesserait d'être localisable.
    ///
    /// ⚠️ Appliquée aux DEUX bouts, comme [[PatronymeLieu]] : ici à la création, et rétroactivement
    /// par `NettoyageEntites`. Sans le second, les entités déjà créées restent sur la carte — c'est
    /// exactement ce qui était arrivé à « Brenna », encore épinglée en Italie le lendemain du filtre.
    static func retirerNomsDeCode(_ entites: [EntiteDetectee], texteNorm: String?) -> [EntiteDetectee] {
        entites.filter { e in
            guard e.type == .gpe || e.type == .loc else { return true }
            return !NomDeCodeTech.estNomDeCodeDansContexteTech(e.valeur, texte: texteNorm)
        }
    }

    static func retirerLieuxComposantsDeNoms(_ entites: [EntiteDetectee], texteNorm: String?) -> [EntiteDetectee] {
        let nomsPersonnes = entites.filter { $0.type == .person }.map(\.valeur)
        guard !nomsPersonnes.isEmpty else { return entites }
        return entites.filter { e in
            guard e.type == .gpe || e.type == .loc else { return true }
            return !PatronymeLieu.estComposantDeNom(
                valeurLieu: e.valeur, nomsPersonnes: nomsPersonnes, texte: texteNorm)
        }
    }

    /// Sigles (2 à 6 capitales) **définis par leur développé entre parenthèses** dans le texte —
    /// motif « Nom complet de l'organisation (SIGLE) » (ex. « …de la navigation (SAN) »). Un tel
    /// sigle désigne une organisation, jamais un lieu ; sert à re-typer une entité mal étiquetée.
    /// Travaille sur le texte **brut** (la casse des capitales est le signal), pas sur la forme
    /// normalisée. Renvoie les sigles normalisés.
    /// **Les PAIRES sigle ↔ forme développée** telles que le texte les pose : « Institut national de
    /// géophysique et de volcanologie **(INGV)** ».
    ///
    /// `siglesOrganisations` extrayait déjà ce motif mais **jetait le développé** — or c'est lui qui
    /// permet de RÉUNIR les deux entités (spec Etna §3 : « `Institut` était “Institut national de
    /// géophysique et de volcanologie”, et son rapprochement avec `INGV` était impossible »).
    ///
    /// ⚠️ **La co-occurrence dans le MÊME texte est la preuve.** Rapprocher un sigle d'un développé
    /// à l'échelle du corpus serait la faute du 15/08 sur les patronymes : « CIA » n'a pas le même
    /// développé partout. Ici, c'est l'article lui-même qui l'affirme, entre parenthèses.
    public static func pairesSigleDeveloppe(_ texte: String) -> [(sigle: String, developpe: String)] {
        let motif = "([\\p{L}][\\p{L}'’.\\-]*(?:\\s+[\\p{L}'’.\\-]+){1,6})\\s*\\(([\\p{Lu}]{2,6})\\)"
        guard let re = try? NSRegularExpression(pattern: motif) else { return [] }
        let ns = texte as NSString
        var paires: [(sigle: String, developpe: String)] = []
        var vus = Set<String>()
        for m in re.matches(in: texte, range: NSRange(location: 0, length: ns.length)) {
            let developpe = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let sigle = ns.substring(with: m.range(at: 2))
            guard developpe.split(separator: " ").contains(where: { $0.first?.isUppercase == true }),
                  vus.insert(normaliser(sigle)).inserted else { continue }
            paires.append((sigle: sigle, developpe: developpe))
        }
        return paires
    }

    /// Renvoi vers `FormeDuNom.estOppositionDeDeuxNomsPropres`.
    ///
    /// ⚠️ La règle a **déménagé dans `FornewsModels`** le 21/08 : `FusionService` en a besoin, et
    /// `FornewsServices` ne dépend pas de `FornewsAI`. Une règle utile à deux modules ne doit
    /// exister qu'à un seul endroit — c'est la fusion d'alias, pas le filtre NER, qui a produit
    /// « Suisse contre la Colombie » en absorbant « Colombie » et son QID.
    static func estOppositionDeDeuxNomsPropres(_ valeur: String) -> Bool {
        FormeDuNom.estOppositionDeDeuxNomsPropres(valeur)
    }

    /// **Termes techniques universels que le NER type parfois « personne »** (mesure du 21/08).
    ///
    /// Mesuré sur le corpus : **64 entités typées `person` portent un sigle de 2 à 4 lettres en
    /// capitales**. La tentation était de les écarter toutes — la mesure l'interdit :
    ///
    /// | Vrai bruit | ⛔ Vraies personnes, à ne PAS toucher |
    /// |---|---|
    /// | `API`, `OS`, `CEO`, `QR`, `NAND`, `LGBT` | **RAYE**, **SZA**, **GIMS**, **MGK**, **MJ** — noms de scène en capitales |
    /// | `RVB`, `AGI`, `GB`, `SWE` | `J.K`, `J.J`, `E.J`, `K.K` — **initiales** de personnes réelles |
    ///
    /// Et l'absence de QID ne départage pas : `RAYE` en a un, `SZA` n'en a pas — les deux sont des
    /// artistes. C'est la même leçon que les hapax du 21/08 : **« sans QID » ne veut pas dire
    /// « faux »**.
    ///
    /// ⛔ D'où une liste **fermée et explicite**, et non une règle de forme. Ce sont des termes du
    /// vocabulaire technique et administratif — **universels, pas éditoriaux** : contrairement à une
    /// liste de noms de médias (écartée le 20/08 parce qu'elle dérive), « API » ne changera pas de
    /// sens et aucun artiste ne se fera appeler « CEO ».
    static func estVocabulaireTechnique(_ valeur: String) -> Bool {
        let v = valeur.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return vocabulaireTechnique.contains(v)
    }

    private static let vocabulaireTechnique: Set<String> = [
        // Informatique
        "API", "OS", "CPU", "GPU", "RAM", "ROM", "SDK", "IDE", "URL", "URI", "HTTP", "HTTPS",
        "HTML", "CSS", "JSON", "XML", "SQL", "USB", "HDMI", "NAND", "SSD", "HDD", "IO", "UI", "UX",
        "AGI", "IA", "AI", "LLM", "GPT", "QR", "PDF", "RVB", "RGB", "GB", "MB", "KB", "TB", "DNS",
        "VPN", "CDN", "OTA", "NFC", "GPS", "LED", "OLED", "LCD", "HDR", "FPS", "VR", "AR", "XR",
        // Fonctions et administration
        "CEO", "CFO", "CTO", "COO", "PDG", "RH", "PME", "TVA", "PIB", "ONG", "PIN",
        // Divers récurrents dans la presse
        "LGBT", "LGBTQ", "ADN", "OGM", "FAQ", "DIY", "PS", "NB",
    ]

    static func siglesOrganisations(_ texte: String) -> Set<String> {
        // Développé = 2 à 7 mots (dont au moins un nom propre, commençant par une majuscule),
        // immédiatement suivi du sigle tout-capitales entre parenthèses.
        let motif = "([\\p{L}][\\p{L}'’.\\-]*(?:\\s+[\\p{L}'’.\\-]+){1,6})\\s*\\(([\\p{Lu}]{2,6})\\)"
        guard let re = try? NSRegularExpression(pattern: motif) else { return [] }
        let ns = texte as NSString
        var sigles: Set<String> = []
        for m in re.matches(in: texte, range: NSRange(location: 0, length: ns.length)) {
            let developpe = ns.substring(with: m.range(at: 1))
            let sigle = ns.substring(with: m.range(at: 2))
            let aNomPropre = developpe.split(separator: " ").contains { $0.first?.isUppercase == true }
            if aNomPropre { sigles.insert(normaliser(sigle)) }
        }
        return sigles
    }

    /// Vrai si la valeur (normalisée) apparaît telle quelle dans le texte source (normalisé).
    /// La normalisation compacte les espaces et ignore casse/diacritiques, donc « L'Obi-Wan »,
    /// retours à la ligne et ponctuation environnante n'empêchent pas la correspondance.
    static func apparaitDans(_ texteNormalise: String, _ valeur: String) -> Bool {
        let v = normaliser(valeur)
        guard !v.isEmpty else { return false }
        return texteNormalise.contains(v)
    }

    /// Indique si une entité passe le post-filtrage (hors fusion).
    public static func estValide(_ entite: EntiteDetectee, longueurMin: Int = 2) -> Bool {
        let valeur = entite.valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valeur.isEmpty else { return false }

        let normalisee = normaliser(valeur)
        guard normalisee.count >= longueurMin else { return false }

        // Stop-list (noms communs, demonymes, termes génériques) et titres seuls.
        // Les titres tolèrent un point final (« M. », « Dr. »).
        let sansPoint = normalisee.replacingOccurrences(of: ".", with: "")
        if stopList.contains(normalisee) { return false }
        if titres.contains(normalisee) || titres.contains(sansPoint) { return false }

        // Notation de MATCH « PaysA-PaysB » (« Suisse-Algérie », « Suisse-Canada ») : l'affrontement de
        // deux équipes nationales, pas une entité. Rejeté quand les DEUX moitiés sont des pays (les vrais
        // toponymes composés comme « Bosnie-Herzégovine » gardent une moitié non-pays → conservés).
        if PaireDePays.estPaire(valeur) { return false }

        // Libellé promotionnel / bouton d'affiliation pris à tort pour un nom propre
        // (« CHECK LATEST PRICE ON AMAZON », « Voir le prix »…) → jamais une entité.
        if LibellePromotionnel.detecte(valeur) { return false }

        // ⚠️ **Tête de syntagme employée seule** — « Institut », « Conseil », « Agence », « Banque ».
        // C'est la troncature d'un nom complet que le NER n'a pas su étendre : « Institut national
        // de géophysique et de volcanologie » devient « Institut », méconnaissable et impossible à
        // rapprocher de « INGV ». Signalé par Patrick sur la collection « Etna » (§3) et vérifié
        // sur le store : cinq cas, chacun PORTANT UN QID — donc parfaitement crédibles à l'écran.
        if LibelleTronque.detecte(valeur, typeRaw: entite.type.rawValue) { return false }

        // ⚠️ **Syntagme positionnel** — « nord des Alpes », « sud-ouest de la Crimée », « centre du
        // Var », « Washington au nord-ouest des Etats-Unis ». Des morceaux de phrase, pas des lieux :
        // le NER les capture parce qu'ils CONTIENNENT un toponyme, et le rattachement leur colle
        // ensuite le QID du lieu enchâssé (« nord des Alpes » → un article d'encyclopédie tchèque).
        // Restreint à loc/gpe : une organisation peut légitimement porter un « et des » dans son nom.
        // Mesuré sur les 1 706 noms de lieux du corpus : 6 rejetés, tous justes, zéro faux positif.
        if entite.type == .loc || entite.type == .gpe,
           SyntagmePositionnel.detecte(valeur) { return false }

        // Fragment de phrase / clause administrative pris pour un « événement » (avis municipaux :
        // « Prolongation de l'exploitation d'un café-restaurant pour une durée de 5 ans ») → pas une entité.
        if ressembleClauseAdministrative(valeur, type: entite.type) { return false }

        // ⚠️ TITRE D'ARTICLE pris pour une entité — signalé à l'usage le 28/07 :
        // « Microsoft Confirms Windows Recycle Bin Bug Affects All Supported Versions » figurait
        // dans le répertoire, et l'écran de qualité proposait d'y fusionner « Microsoft » et ses
        // 297 articles. Le rattrapage après coup ne suffit pas : il faut que ça ne naisse pas.
        if ressembleUnTitre(valeur, type: entite.type) { return false }

        // ⚠️ Une CONJONCTION de deux noms n'est pas une entité : « Nintendo and Sony » figurait dans
        // le répertoire (28/07). C'est une énumération que le NER a agrafée, et aucune fusion ne la
        // rend juste — la faire disparaître dans « Sony » perdrait Nintendo.
        if ressembleUneEnumeration(valeur) { return false }

        // ⚠️ Deux personnes en une (« Paul McCartney et Ringo Starr »), une fonction sans nom (« CEO de Sulzer »),
        // une date abrégée (« Tue Jun ») : 04/10/2026, mesurés sur le mini. Règle partagée : [[ControlesEntites]].
        if ControlesEntites.aRejeter(valeur, typeRaw: entite.type.rawValue) { return false }

        // ⚠️ **Un mot-outil n'est jamais une entité** — « le », « mais », « sur », « the ».
        // Signalé le 02/08 : ils étaient SURLIGNÉS dans le corps des articles, et deux d'entre eux
        // ont donné son nom à une histoire détectée (« Le · Mais »). Le rejet porte sur le MOT et
        // non sur la casse : « Le 22 juillet 1956… » présente « Le » exactement comme un nom propre,
        // et la règle de majuscule ci-dessous le laissait passer.
        //
        // Comparé au mot ENTIER, jamais à un préfixe : « Le Monde », « The Verge » et
        // « Los Angeles » commencent par un mot-outil et sont de vraies entités.
        if TermesGeneriquesNER.motsOutils.contains(normalisee) { return false }

        // Un nom propre comporte au moins une majuscule (« frère », « mairie »… rejetés).
        //
        // ⚠️ **Et seulement un nom propre.** J'ai voulu étendre la règle à tous les types en
        // corrigeant les mots-outils du 02/08 : le jeu de tests l'a refusée sur-le-champ — une DATE
        // (« 12 mai 2026 ») n'a pas de majuscule, et une MALADIE non plus (« rougeole »,
        // « grippe aviaire »). Ces types nomment des choses qui s'écrivent en minuscules dans la
        // langue. Le rejet des mots-outils, lui, porte sur le mot et vaut pour tous les types :
        // c'est la garde qui manquait, pas celle-ci qu'il fallait élargir.
        if typesNomPropre.contains(entite.type),
           !valeur.contains(where: { $0.isUppercase }) {
            return false
        }

        return true
    }

    /// **Une entité qu'un document exporté peut nommer** dans sa section « ## Entités » (1.7.4 ⑤,
    /// demande de md Viewer, 27/10/2026) : jamais un nombre (« [[7]] », « [[2026]] »), un mot-outil
    /// (« [[Je]] », « [[Le]] », « [[Mais]] ») ou un nom commun pris pour un nom propre (« [[bureau]] »).
    ///
    /// ⛔ **Pas `estValide` tout entière, et c'est mesuré.** Rejouée le 27/10/2026 sur les 45 854 entités
    /// liées de la base du mini, elle en retirait 150, dont des dizaines de vraies : « X » (50 articles),
    /// « Mouvement international de la Croix-Rouge et du Croissant-Rouge », « Ernst & Young », « Le
    /// diable s'habille en Prada », « Armée de terre des États-Unis ». Ses règles d'énumération, de
    /// titre et de clause sont faites pour trier ce que le modèle VIENT de détecter ; une entité déjà en
    /// base, souvent rattachée à Wikidata, ne doit plus y être soumise. On ne garde ici que les règles
    /// sans faux positif sur la base : lettres, stop-list, titres, mots-outils, majuscule d'un nom
    /// propre, libellé promotionnel.
    ///
    /// ⚠️ Une seule lettre passe pour une organisation ou un produit en capitale (« X », l'ex-Twitter) ;
    /// ailleurs (« O », « À »), elle ne nomme rien.
    public static func estNommable(_ valeur: String, type: TypeEntite) -> Bool {
        let v = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        guard v.contains(where: \.isLetter) else { return false }
        let n = normaliser(v)
        let sansPoint = n.replacingOccurrences(of: ".", with: "")
        if stopList.contains(n) || titres.contains(n) || titres.contains(sansPoint)
            || TermesGeneriquesNER.motsOutils.contains(n) { return false }
        if typesNomPropre.contains(type), !v.contains(where: { $0.isUppercase }) { return false }
        if n.count < 2, !([.org, .product].contains(type) && v.count == 1 && v == v.uppercased()) { return false }
        if LibellePromotionnel.detecte(v) { return false }
        return true
    }

    // MARK: Fusion des variantes proches

    /// Fusionne les entités de même type dont les valeurs normalisées sont identiques
    /// ou proches au sens de Levenshtein. On conserve la variante la plus longue (la plus complète).
    static func fusionnerVariantes(
        _ entites: [EntiteDetectee],
        seuilFusion: Int,
        longueurMinFusion: Int
    ) -> [EntiteDetectee] {
        var resultat: [EntiteDetectee] = []
        for entite in entites {
            let normalisee = normaliser(entite.valeur)
            if let idx = resultat.firstIndex(where: {
                $0.type == entite.type
                    && sontVariantes(
                        normaliser($0.valeur), normalisee,
                        seuilFusion: seuilFusion, longueurMinFusion: longueurMinFusion)
            }) {
                // Variante connue : on garde la forme la plus longue (la plus complète).
                if entite.valeur.count > resultat[idx].valeur.count {
                    resultat[idx] = entite
                }
            } else {
                resultat.append(entite)
            }
        }
        return resultat
    }

    /// Deux valeurs normalisées sont des variantes si elles sont identiques, ou si leur
    /// distance de Levenshtein est faible **et** qu'au moins l'une est assez longue
    /// (pour éviter de fusionner deux noms courts pourtant distincts).
    static func sontVariantes(
        _ a: String, _ b: String,
        seuilFusion: Int, longueurMinFusion: Int
    ) -> Bool {
        if a == b { return true }
        guard max(a.count, b.count) >= longueurMinFusion else { return false }
        return distanceLevenshtein(a, b) <= seuilFusion
    }

    // MARK: Titre/fonction en préfixe d'un nom de personne

    /// Retire un **titre / fonction / gentilé en tête** d'un nom de PERSONNE — le NER capture parfois
    /// le span descriptif complet (« président ukrainien Volodymyr Zelensky ») au lieu du seul nom.
    /// Logique **partagée** dans `TermesGeneriquesNER` (FornewsModels) pour que `NettoyageEntites`
    /// (FornewsServices) applique le même retrait en purge rétroactive. Voir la doc là-bas.
    static func retirerTitrePersonne(_ valeur: String) -> String {
        TermesGeneriquesNER.retirerTitrePersonne(valeur)
    }

    // MARK: Casse des noms de personne

    /// Remet un nom de **personne** en casse de nom propre : chaque jeton ENTIÈREMENT en capitales
    /// (≥ 3 lettres, sans point) devient « Première-lettre + minuscules » — ex. « Marie DASPAS » →
    /// « Marie Daspas », « Jean-Michel ROPARS » → « Jean-Michel Ropars ».
    ///
    /// Garde-fous (évitent d'abîmer de vrais libellés) :
    /// - **N'agit que sur les jetons situés APRÈS le premier prénom** (jeton en casse normale) : le
    ///   patronyme d'une signature vient après le prénom (« Marie DASPAS »), tandis qu'un acronyme en
    ///   préfixe le précède (« ONG Alima », « BNS Hans Meyer », « PLR Pascal Lauber ») → laissé intact.
    ///   Épargne aussi les acronymes isolés mal typés en personne (« ISO », « CEO », « PNG »).
    /// - **Épargne les chiffres romains** (« Léon XIV », « Charles III », « Charli XCX », « GTA VI »).
    /// - Épargne les initiales pointées (« J.K. ») et la casse mixte (« McCartney »).
    static func normaliserCassePersonne(_ valeur: String) -> String {
        let jetons = valeur.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let premierPrenom = jetons.firstIndex(where: estCasseNormale) else { return valeur }
        return jetons.enumerated()
            .map { (i, j) in i > premierPrenom ? titreJeton(j) : j }
            .joined(separator: " ")
    }

    /// Jeton en casse « normale » : initiale majuscule + au moins une minuscule (« Marie », « Léon »).
    private static func estCasseNormale(_ t: String) -> Bool {
        guard let f = t.first, f.isUppercase else { return false }
        return t.dropFirst().contains { $0.isLowercase }
    }

    /// Jeton entièrement composé de lettres de chiffre romain (I, V, X, L, C, D, M).
    private static func estChiffreRomain(_ t: String) -> Bool {
        let romains: Set<Character> = ["I", "V", "X", "L", "C", "D", "M"]
        let lettres = t.filter { $0.isLetter }
        return !lettres.isEmpty && lettres.allSatisfy { romains.contains($0) }
    }

    private static func titreJeton(_ jeton: String) -> String {
        guard !jeton.contains("."), !estChiffreRomain(jeton) else { return jeton }
        return jeton.split(separator: "-", omittingEmptySubsequences: false)
            .map { sub -> String in
                let s = String(sub)
                guard !estChiffreRomain(s) else { return s }
                let lettres = s.filter { $0.isLetter }
                guard s.count >= 3, !lettres.isEmpty,
                      lettres.allSatisfy({ $0.isUppercase }) else { return s }
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: "-")
    }

    // MARK: Queue de span parasite (débordement de mots-outils)

    /// Retire les jetons de **queue** qui sont des **mots en minuscules** (articles, prépositions,
    /// adjectifs) ayant débordé dans le span d'un nom propre — ex. « Downing Street du nouveau » →
    /// « Downing Street ». S'arrête au premier jeton (depuis la fin) contenant une **majuscule** : ainsi
    /// « Nord de l'Europe » (finit par « l'Europe », qui a un « E ») et « Bank of America » restent intacts,
    /// et les nombres / sigles tout-capitales ne sont pas rognés. Conserve toujours au moins un jeton.
    static func retirerQueueMinuscule(_ valeur: String) -> String {
        var jetons = valeur.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while jetons.count > 1, let dernier = jetons.last,
              dernier.contains(where: { $0.isLowercase }),      // c'est bien un mot (pas un nombre)
              !dernier.contains(where: { $0.isUppercase }) {    // sans aucune majuscule → mot-outil parasite
            jetons.removeLast()
        }
        return jetons.joined(separator: " ")
    }

    // MARK: Clause administrative (faux « événement »)

    /// Connecteurs de **clause/phrase** (avis municipaux, ordres du jour) qui n'apparaissent jamais
    /// dans un vrai nom propre. Formes normalisées (minuscules, apostrophe droite).
    static let connecteursClause = [
        // Français
        "d'un ", "d'une ", "pour une ", "par une ", "afin de ", "afin d'", "en vue de ",
        "en vue d'", "visant a ", "destine a ", "destinee a ", "permettant de ", "permettant d'",
        // Le contenu peut être en de/es/it → connecteurs de clause SPÉCIFIQUES (peu probables dans un
        // nom propre, pour éviter les faux positifs sur de vrais noms longs étrangers).
        "fur eine dauer", "im hinblick auf", "zwecks ", "zugunsten ",   // de
        "con el fin de", "a fin de", "con motivo de", "por una duracion",  // es
        "al fine di", "allo scopo di", "in vista di", "per una durata",    // it
    ]

    /// Vrai si la valeur ressemble à une **clause administrative / fragment de phrase** plutôt qu'à un
    /// nom propre. Conservateur : limité aux types « phrasables » (event/org/work/product), aux libellés
    /// longs (> 35 car.), et exige un connecteur de clause (épargne « Festival … d'Annecy », « Office
    /// fédéral de météorologie et de climatologie », « Comité … pour un changement progressiste »).
    static func ressembleClauseAdministrative(_ valeur: String, type: TypeEntite) -> Bool {
        let typesPhrasables: Set<TypeEntite> = [.event, .org, .work, .product]
        guard typesPhrasables.contains(type), valeur.count > 35 else { return false }
        let n = normaliser(valeur)
        return connecteursClause.contains { n.contains($0) }
    }

    /// **Un titre d'article, pas un nom.**
    ///
    /// ⚠️ Le discriminant n'est PAS la longueur. « Organisation des Nations unies pour l'éducation,
    /// la science et la culture » fait onze mots et reste une organisation ; la rejeter sur ce
    /// critère perdrait des entités justes. Ce qui distingue un titre, c'est le **verbe conjugué** :
    /// « Microsoft **confirms** … **affects** … », « Apple **raised** … ». Un nom propre n'en
    /// contient pas.
    ///
    /// Le test n'est tenté que sur les libellés déjà longs et sur les types où les phrases
    /// s'infiltrent — l'analyse grammaticale coûte, et un nom de deux mots n'a jamais besoin d'elle.
    /// ⚠️ **5, et non 6** (abaissé le 20/08). « Keely Hodgkinson défiera Audrey Werro » — une phrase
    /// typée `person`, signalée par Patrick — fait exactement 5 mots et passait juste sous le seuil.
    /// Vérifié avant d'abaisser, sur les 105 libellés de 5 mots des types phrasables du corpus réel :
    /// **aucun ne contient de verbe**, donc aucun vrai nom n'est perdu (« Hamdan bin Mohammed bin
    /// Rashid Al Maktoum », « Jan van Kessel the Elder » restent intacts). C'est bien le VERBE qui
    /// tranche, jamais la longueur seule.
    static let motsMinPourUnTitre = 5
    static func ressembleUnTitre(_ valeur: String, type: TypeEntite) -> Bool {
        let typesPhrasables: Set<TypeEntite> = [.event, .org, .work, .product, .person]
        guard typesPhrasables.contains(type) else { return false }
        let mots = valeur.split(whereSeparator: { $0 == " " })
        guard mots.count >= motsMinPourUnTitre else { return false }
        return contientUnVerbe(valeur)
    }

    /// **Deux noms reliés par une conjonction** — « Nintendo and Sony », « Apple et Google ».
    ///
    /// ⚠️ On exige des majuscules DE PART ET D'AUTRE : sans cela, « Bourse et Vie » ou
    /// « Rock and Roll Hall of Fame » — de vrais noms — tomberaient avec. Ce qu'on vise, c'est la
    /// juxtaposition de deux entités que le NER n'a pas su séparer.
    static let conjonctions = [" and ", " et ", " & ", " und ", " y ", " e "]
    static func ressembleUneEnumeration(_ valeur: String) -> Bool {
        let v = " " + valeur + " "
        for c in conjonctions {
            guard let r = v.range(of: c, options: [.caseInsensitive]) else { continue }
            let avant = v[v.startIndex..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let apres = v[r.upperBound...].trimmingCharacters(in: .whitespaces)
            // Deux côtés d'un seul mot chacun, tous deux capitalisés → une énumération.
            guard avant.split(separator: " ").count == 1, apres.split(separator: " ").count == 1,
                  avant.first?.isUppercase == true, apres.first?.isUppercase == true
            else { continue }
            return true
        }
        return false
    }

    /// Vrai si le texte contient au moins un verbe, d'après l'analyse grammaticale du système.
    ///
    /// ⚠️ La langue est DÉDUITE du texte, pas supposée : le corpus est multilingue, et forcer le
    /// français ferait passer les titres anglais — précisément ceux qui ont posé problème.
    static func contientUnVerbe(_ texte: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = texte
        if let langue = NLLanguageRecognizer.dominantLanguage(for: texte) {
            tagger.setLanguage(langue, range: texte.startIndex..<texte.endIndex)
        }
        var trouve = false
        tagger.enumerateTags(in: texte.startIndex..<texte.endIndex, unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, _ in
            if tag == .verb { trouve = true; return false }
            return true
        }
        return trouve
    }

    // MARK: Outils purs

    /// Normalisation cohérente avec `KeywordMatcher.normalize` (minuscules, sans diacritiques,
    /// espaces compactés, apostrophes unifiées). Dupliquée ici car `FornewsAI` ne dépend pas de
    /// `FornewsServices`.
    static func normaliser(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Distance d'édition de Levenshtein (deux lignes, mémoire O(min)).
    static func distanceLevenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a)
        let t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }

        var precedente = Array(0...t.count)
        var courante = [Int](repeating: 0, count: t.count + 1)
        for i in 0..<s.count {
            courante[0] = i + 1
            for j in 0..<t.count {
                let cout = s[i] == t[j] ? 0 : 1
                courante[j + 1] = Swift.min(
                    precedente[j + 1] + 1,   // suppression
                    courante[j] + 1,         // insertion
                    precedente[j] + cout)    // substitution
            }
            swap(&precedente, &courante)
        }
        return precedente[t.count]
    }
}
