# 1.4 — « L'option Analytic »

Ouverte le **08/10/2026**, à la demande de Patrick. La 1.3 n'est pas encore sortie (elle attend le
Duo) : rien de la 1.4 n'entre dans la 1.3. Le détail et les raisons sont dans le README, section
« 1.4 — l'option Analytic ».

**Slogan** : « md Viewer — vos documents prennent vie. » / « md Viewer — your documents come
alive. »

**Principe** : on valorise au maximum le document. Un rapport fornews donne déjà presque tout ;
Wikidata ne comble que ce qui manque.

**Calendrier (Patrick, 25/10/2026)** : la 1.4 sortira **après fornews 1.7.4**, celle
qui doit lui donner le cache d'entités partagé et l'ouverture par QID (« Demandes à fornews »).
B89 et B90 envoyés le 25/10, B91 à B96 le 26/10 (iOS + Mac) ; poussé jusqu'à B95. **D'ici là, md
Viewer 1.4 reste en bêta (TestFlight)** : aucune soumission à Apple.

**Décisions prises en route** (le détail dans chaque section) : signaler une erreur, six types
(②, 25/10) ; import ouvert à l'iPhone et à l'iPad (④, 26/10) ; PDF scannés lus par Vision (④,
26/10) ; commentaires comme consignes et rapport d'analyse, jamais cochés d'avance (④, 25/10) ; la
fiche de lecture d'une page envoyée depuis Safari, réservée à l'option (④ ter, 26/10), traduite
dans la langue de l'interface (④ ter, 26/10). Site à jour le 27/10 (feuille de route FR et EN).

## ⓪ Décisions de Patrick — prises le 25/10/2026 (« Ok commence »)

- [x] **Private Cloud Compute : non.** Uniquement `SystemLanguageModel.default`. Les deux engagements
      publiés restent vrais, sans réécriture. La section ⑤ sort de la 1.4. Conséquence : « Analytic
      pour Mac » demande Apple Intelligence (l'import rédige avec le modèle embarqué) ; entités,
      galerie, carte et annotations n'en ont pas besoin.
- [x] **Wikidata : proposée, jamais imposée.** Coupée tant que l'utilisateur ne l'a pas acceptée à la
      première analyse ; réglage pour revenir sur le choix. Une requête par nom, sans contexte.
      Texte de la politique de confidentialité : dans la réponse du 25/10, à reprendre en ⑥.
- [x] **Prix : deux produits non consommables, 5 francs sur Mac, 3 francs sur iPhone et iPad**
      (recommandation retenue après la question de Patrick sur 5 francs ; l'option gagne
      l'annotation). Paliers vérifiés le 25/10 (produit net au taux standard) : 2.00 → 1.30,
      3.00 → 1.94, 4.00 → 2.59, 5.00 → 3.24. Pays de référence : Suisse. Identifiants :
      `ch.okia.markdownviewer.analytic` et `ch.okia.markdownviewer.analytic.mac`. Pas d'essai de
      7 jours, un aperçu ; partage familial activé. La feuille de route publiée (2 + 2) est à
      corriger, FR et EN. ⚠️ Mac Catalyst : `targetEnvironment(macCatalyst)`, pas `os(macOS)`.
- [x] **Slogan** : « md Viewer — vos documents prennent vie. » / « md Viewer — your documents come
      alive. » ; DE « Ihre Dokumente werden lebendig. », ES « Tus documentos cobran vida. », IT « I
      tuoi documenti prendono vita. » Variante « Lisez plus loin que le texte » / « Read beyond the
      text » pour le titre de l'écran de l'option.
- [x] **Code de fornews : copie mot pour mot** dans `OKiaMarkdownViewer/Fornews/`, source et commit
      en tête de chaque fichier (comme `BoiteAuxLettres.swift`), plutôt qu'une dépendance au dépôt.

**Lots TestFlight, dans l'ordre** : ① entités → ② galerie et carte → ③ achat → ④ bis annotations →
④ import Mac.

## ① Achat de l'option — troisième lot, 25/10/2026

- [x] **Deux produits non consommables créés dans App Store Connect** par l'API le 25/10/2026
      (feu vert de Patrick : 3 et 5 francs), partage familial, 175 pays, Suisse en référence :
      « Analytic » `ch.okia.markdownviewer.analytic` (6826757296, CHF 3.00 → 1.94 net,
      **READY_TO_SUBMIT**) et « Analytic pour Mac » `ch.okia.markdownviewer.analytic.mac`
      (6826757297, CHF 5.00 → 3.24 net). ⚠️ **Sans tiret** : App Store Connect refuse `ok-ia` dans
      un identifiant de produit. Noms et descriptions en cinq langues, note d'examen en anglais.
- [x] **Capture d'examen du produit Mac** envoyée le 25/10 (`store/analytic/revue-achat-mac.png`,
      fenêtre 2880×1800, briefing anglais, `OKIA_ACHAT=vitrine`) : **les deux produits sont
      READY_TO_SUBMIT**, servis dans le bac à sable. Celle de l'iPhone est envoyée
      (`store/analytic/revue-achat-iphone.png`, hook `OKIA_ACHAT=vitrine` : bouton actif au prix
      suisse, sans « indisponible »).
- [ ] Les deux achats intégrés partent en revue **avec la version 1.4** (premiers achats de l'app).
- [x] StoreKit 2 (`AchatAnalytic`) : droits relus au lancement, achat, « Demander à acheter »,
      restauration avec un message pour chaque issue, et **écoute de `Transaction.updates`** (achat
      approuvé plus tard ou fait sur un autre appareil, remboursement) — fornews ne l'écoutait pas.
      Repris de `AchatModele` sans l'essai ni l'accès libre en bêta : en TestFlight, l'achat passe
      par le bac à sable, gratuit pour les testeurs.
- [x] Le Mac ne regarde que son produit, par `targetEnvironment(macCatalyst)` (`os(macOS)` est faux
      sous Catalyst) ; iPhone et iPad le leur.
- [x] Écran de l'option (`OptionAnalyticView`) : ce qu'elle apporte, le prix de l'App Store, achat
      distinct sur l'autre plateforme, confidentialité ; jamais d'impasse (« indisponible » +
      « Réessayer »). Dans les Réglages et, à la place des entités, l'**aperçu** (`ApercuAnalyticView`)
      : ce que l'analyse locale trouve, compté par genre. Avant l'achat, Wikidata n'est jamais
      consulté, quel que soit le choix déjà fait. Les annotations et l'import Mac s'ajouteront à la
      liste des apports avec leurs lots.
- [x] `Analytic.storekit` (deux produits, CHF, partage familial) branché à l'action Run du schéma :
      l'achat s'essaie dans Xcode sans App Store Connect. ⚠️ `simctl launch` ne le lit pas.
- [x] Hook Debug `OKIA_ACHAT=achete|bloque`, ajouté aux canaris.

**Vérifié au simulateur le 25/10** : aperçu (option fermée, produits introuvables → bouton grisé et
« Réessayer »), option ouverte (liste complète). **Pas vérifié** : un achat réel (ni Xcode, Mac
verrouillé, ni bac à sable, produits absents), la restauration, le Mac, le partage familial.

## ② Détection d'entités — premier lot, commencé le 25/10/2026

- [x] Reprendre l'algorithme de fornews — **copie mot pour mot** dans `OKiaMarkdownViewer/Fornews/`
      (19 fichiers, commit fornews 1eb3b3d8) par `scripts/copier-fornews.sh`, qui la refait à
      l'identique. Trois extraits seulement (`TypeEntite`, `EntiteDetectee`, `WikimediaService` sans
      SwiftData, `QualiteEntites.motifFicheSansContenu`). La détection : `DetecteurEntites`
      (`NLTagger` par morceaux de 20 000 caractères, puis `FiltreEntitesNER.filtrer`).
- [x] **Rapport fornews d'abord** (`LecteurRapportFornews`) : section `## Entités` et ses genres
      dans les cinq langues de fornews, marqueurs des cartes `leaflet` pour les coordonnées. Un nom
      du rapport n'est contrôlé que par `estValide` — `filtrer` coupait « Union européenne » en
      « Union ». Les dates et montants balisés ne sont pas des fiches : pas montrés.
- [x] Les formes courtes détectées (« Poutine ») sont absorbées par le nom complet du document.
- [ ] **fornews d'abord, Wikidata ensuite** quand fornews est installé — ⚠️ attend fornews (voir
      « Demandes à fornews » plus bas).
- [x] Résolution Wikidata (`ResolveurWikidata`), **proposée** : question à la première ouverture,
      réglage dans le menu « … » des entités. Les règles de choix de fornews, plus deux du 25/10 :
      un article en minuscules retiré pour chercher (« la CIA » → « CIA », jamais « Le Monde ») ;
      un genre de rapport fiable écarte un candidat de nature contraire (« CIA » → aéroport de
      Ciampino). Trois noms à la fois, arrêt net si Wikidata reste muet.
- [ ] **Cache** : fait **sur l'appareil** (`CacheEntites`, Application Support, 30 jours, réponses
      négatives comprises). Reste **le partage par iCloud** : il faut une capacité iCloud que l'app
      n'a pas (clé-valeur, 1 Mo, ou CloudKit) — à décider avec Patrick.
- [x] Liste des entités par genre (`EntitesView`) : seconde partie quand l'écran le permet
      (`PanneauDuo.entites`), feuille ailleurs ; bouton `person.2` dans la barre, entrée dans le menu
      « … » de l'iPhone. Toucher une entité la cherche dans le document.
- [x] Hooks Debug : `OKIA_ANALYTIC=entites` (ouvre), `OKIA_WIKIDATA=oui|non|demander|vider`,
      ajoutés aux canaris de `deploy-testflight.sh`.

- [x] **Corrigé le 25/10 — « Donald Trump, Elon Musk ne sont pas détectés » (Patrick, sur B88).**
      Trois causes, toutes dans le code de md Viewer : (1) **sur iOS, `NLTagger` peut n'avoir pas son
      modèle de noms** — il ne trouve alors rien, sans rien dire (simulateur : `availableTagSchemes`
      sans `NameType` ; le Mac l'a toujours, d'où un banc trompeur) ; (2) l'absorption des formes
      courtes fondait une personne dans un nom plus long d'un autre genre (« Maison Blanche de Donald
      Trump ») ; (3) des doublons au même identifiant (« Iran » / « l'Iran », « United States » lieu
      et organisation) que SwiftUI affichait mal. La détection a maintenant **trois étages** :
      `NLTagger` après avoir demandé son modèle (8 s au plus, une fois par langue, vraie course — la
      demande ne revient jamais au simulateur) ; Apple Intelligence (`NERFoundationModels` de fornews,
      copié) ; enfin un repli par majuscules fondé sur la fréquence. **Ligne de diagnostic** dans les
      builds de test (Xcode, TestFlight iPhone/iPad) : l'étage utilisé, la langue, le nombre.
      Banc gardé : `tools/BancEntites/banc.sh` (FORCE=majuscules, CHERCHE=…, TOUT=1).
      À voir sur l'appareil : quel étage sert (le diagnostic le dit).

**Vérifié au simulateur le 25/10** (rapport de veille réel « Ukraine · Kiev », 56 entités) : iPhone
17 Pro Max en feuille, iPad 13″ en paysage dans la partie de droite, interface en anglais, Wikidata
accepté puis refusé, toucher → mention surlignée. **Pas vérifié** : le Mac (écran verrouillé, le
build Catalyst compile), le Duo, un vrai appareil.

**Limites connues de la résolution par le nom seul** (même algorithme que fornews) : « Elysée »
rattaché à une salle des fêtes d'Ostende ou à un aérodrome australien selon les jours, « Andrei
Vorobyov » à un footballeur homonyme. Le remède est le cache de fornews, qui connaît le bon QID.

**Constaté en passant** : fornews exporte `[[7]]` parmi ses organisations ; md Viewer l'écarte de la
liste, mais `render.js` surligne encore chaque « 7 » de la prose.

- [x] **Retours sur B90 (Patrick, 25/10)** : « La Liberté est un journal, il doit être dans les
      sources » → `SourcesDocument` lit les sources du document (domaines des liens, attributions
      « — Nom, 6 octobre », « · Nom » soutenu par un domaine) ; elles forment une section « Sources »
      à part, ne vont ni sur la carte ni à Wikidata. « Mercedes est une marque » → une organisation
      ou un produit n'est jamais un lieu (classe ou description), et un nom composé est admis
      (Mercedes → Mercedes-Benz, Q36008). « Ryad toujours en doublon » → une variante sans fiche
      rejoint, après Wikidata, le nom à une ou deux lettres près qui en a une, du même genre. Logos
      transparents sur fond blanc dans la galerie. Régression trouvée en vérifiant et corrigée : la
      règle des lieux touchait aussi le genre « autre » (« États-Unis » → un pays de Star Trek).
      Reste faux par le nom seul : « Maison Blanche » → Casablanca (alias) — à corriger par
      l'utilisateur, ou par le cache de fornews.

- [x] **« Signaler une erreur » (Patrick, 25/10 : « on doit pouvoir signaler une erreur et en tenir
      compte dans les traitements suivants » ; « 5 ou 6 types d'erreur dans un menu »).** Un menu
      sur la fiche (bouton en haut à droite) et dans le menu contextuel de la liste et de la galerie,
      avec six types : **ce n'est pas la bonne fiche** (toutes les fiches Wikidata du nom, les plus
      anciennes d'abord, recherche d'un autre nom possible, « aucune ne convient ») ; **mauvais
      genre** ; **c'est une source / ce n'en est pas une** ; **c'est la même que…** ; **mauvaise
      photo** ; **ce n'est pas une entité**. Plus « annuler mes corrections » sur l'entité, et
      « oublier mes N corrections » dans le menu « … ».
      Les corrections (`CorrectionsEntites`, `Analytic/corrections.json`) portent sur le NOM plié
      et valent pour tous les documents ; elles priment sur la détection, le cache et Wikidata. Une
      correction se rejoue sans relire le texte (les entités brutes sont gardées). Une fiche refusée
      n'est plus jamais reprise ; une fiche choisie est gardée complète, hors du cache qui vieillit.
      Vérifié au simulateur (iPhone 17 Pro Max, briefing-fr) : Asha Sharma → la bonne fiche
      (Q138483458) par la fiche puis par la liste ; Hacker News → source ; corrections relues après
      relance. **À faire** : partager les corrections par iCloud avec le cache (même capacité).

- [x] **Image d'en-tête des fiches d'article fornews vide (Patrick, sur B91, 25/10)**, visible
      seulement au zoom. La photo de l'en-tête est en `position:absolute` (100 % × 100 %) dans un
      cadre 16/9 ; la pastille « plein écran » (render.js, depuis le 09/10, donc déjà dans la 1.3)
      l'enveloppe dans un `span.okia-agrandissable` positionné, sur lequel elle se mesurait :
      0 × 0. Corrigé dans `annotations.css` (pas dans style.css, que fornews copie) : l'enveloppe
      prend la place du cadre. Vérifié au simulateur (image 684 × 385 = le cadre, pastilles
      par-dessus). **À signaler à fornews** : même règle à reporter s'il pose la même enveloppe.

- [x] **Le livre ne s'enclenchait plus sur le Duo (Patrick, sur B91, 26/10)** — régression de la
      1.4 (B89 à B91). Le détecteur de charnière (`DetecteurCharniere`) était posé en arrière-plan
      de la palette des annotations, intercalée par le lot 4 bis : cette palette n'existe qu'en mode
      Annoter, si bien que le détecteur n'existait plus. md Viewer ne se savait plus sur un
      appareil pliable, le Duo prenait la mise en page d'un iPad (barre en haut), et la posture
      mi-repliée n'était jamais vue. Le détecteur est revenu sur le calque plein écran. Vérifié au
      simulateur Duo déplié (commandes de nouveau dans la colonne du système) ; **le livre
      mi-replié reste à confirmer sur le vrai Duo.**

- [x] **Fermer des entités ne répondait pas sur le Duo (Patrick, sur B93, 26/10).** La colonne du
      système borde la seconde partie à droite et prend les touchers au-delà de ce qu'elle dessine.
      La correction de B88 (rangée à nous) n'avait jamais été éprouvée sur le vrai Duo : de B89 à
      B91, il n'était plus reconnu comme pliable. Désormais, dans la seconde partie, les boutons
      vont À GAUCHE : Fermer, titre et « … » des entités ; Fermer du sommaire ; OK et le bouton
      voisin du résumé et de la discussion (la conversion l'avait déjà). Les feuilles de l'iPhone
      ne changent pas. Une marge de 44 points sur toute la partie a été essayée et écartée : elle
      se cumulait à la zone sûre et prenait un tiers de la largeur. Vérifié au simulateur Duo
      (entités, sommaire) ; **à confirmer sur le vrai Duo**, résumé et discussion compris.

### Demandes à fornews (à faire dans fornews.ai, pas d'ici) — prévues pour **fornews 1.7.4** (Patrick, 25/10)

Charge estimée le 25/10, d'après le code de fornews : route QID ~30 lignes (`DeepLinkModele.depuis`,
plus l'aiguillage de `FornewsVisionApp`), `[[7]]` quelques lignes (`FiltreEntitesNER.estValide` à la
composition de `## Entités`), cache ~100 lignes sur le patron de `CacheBulletinMontre` ; une
demi-journée tests compris. La lecture du cache côté md Viewer (~60 lignes) se fera ensuite.

1. **Publier un cache d'entités** dans `group.ai.fornews.native` — proposition de format : un JSON
   `Entites/cache.json`, liste de `{ nom, alias[], type, qid, description, image, latitude,
   longitude, langue }` des entités résolues, réécrit après chaque enrichissement.
2. **Route `fornews://entite?qid=Q…`** pour ouvrir une entité par son QID.
3. Ne plus exporter d'entité réduite à un nombre (`[[7]]`) dans la section `## Entités`.

## ③ Galerie et carte — deuxième lot, 25/10/2026

- [x] Trois affichages dans le panneau des entités, au choix retenu (`okia.analytic.vue`) : **Liste**,
      **Galerie** par genre (photo, nom, description, mentions), **Carte**.
- [x] **Fiche d'une entité** (`FicheEntiteView`) : photo, genre, mentions, description, mini-carte,
      « Voir dans le document », lien vers sa fiche Wikidata, provenance (« Nommée par le rapport
      fornews » ou « Trouvée dans le texte », « Photo : Wikimedia Commons »). Toucher une entité, une
      carte de la galerie ou un marqueur ouvre sa fiche ; un appui long mène droit au document.
- [x] Carte des entités situées, **plein écran sur demande** : la pile du lecteur (Leaflet +
      MapLibre, OpenFreeMap) par `CarteWebView` — sortie de `DiagramZoomView` pour servir aux deux,
      redessinée quand Wikidata situe un lieu de plus, marqueur → fiche (`wikiTapped`).
- [x] Dans **la partie de droite** quand l'écran le permet (`PanneauDuo.entites`, lot ①) ; ailleurs,
      une feuille.
- [x] Une entité ne compte plus son article : « l'ONU » (organisations) et « Onu » (lieux, rattaché
      par Wikidata à un village de Sulawesi) ne font qu'une, sous le premier genre lu.
- [x] **Fermer ne répondait pas sur le Duo** (Patrick, B88, 25/10) : le système range les commandes de
      la barre dans sa colonne de droite, et « Fermer » y touchait. Dans la seconde partie, le panneau
      a désormais sa propre rangée (menu, titre, Fermer) dans la zone sûre ; le bouton des entités de
      la barre referme aussi le panneau ouvert. Vérifié sur iPad en paysage ; **à revoir sur le vrai
      Duo**, comme Fermer / OK du sommaire, du résumé et de la discussion (même placement).
- [x] **Mac vérifié le 25/10** (build Debug, écran déverrouillé) : panneau à côté du document,
      détection NLTagger (82 entités sur le rapport Ukraine, 20 personnes sur le briefing anglais),
      galerie, photos Wikidata, nouvelle rangée « Fermer », écran de l'option à CHF 5.00 avec sa
      phrase propre au Mac (souris, trackpad). Corrigé en passant : « Le président ukrainien
      Volodymyr Zelensky » est fondu dans Volodymyr Zelensky (personne précédée d'un titre).
      **Pas essayé** : les annotations à la souris (accès à l'app refusé, à faire à la main).
- [x] **Retours de Patrick sur B89 (25/10)**, corrigés le jour même :
      images qui débordaient de leur carte (une image en remplissage prenait sa taille naturelle :
      cadre fixe, image en surimpression, rognée) ; **choix de fiche refait pour le nom seul**
      (`ChoixWikidata`) — parmi les correspondances exactes de nature possible, la fiche la plus
      ancienne (plus petit Q) ; une personne doit être un être humain (Q5), un lieu porter une classe
      de lieu connue, sinon abstention. Au banc (24 noms) : NASA → l'agence (avant : filiale de
      Saxe-Anhalt), CIA → l'agence, Andrei Vorobyov → le politicien, Ryad → plus d'école marocaine ;
      Paris, Kiev, Trump, Musk, Zelensky inchangés et justes. Restent faux : Elysée, Washington,
      Mercedes, Asha Sharma. **Doublons** : deux entités rattachées à la même fiche n'en font qu'une
      (mentions additionnées). « IA », « AI » écartés, noms de deux lettres jamais envoyés à Wikidata.
      Cache renommé `entites-v2.json` pour oublier les réponses de l'ancien choix.
- [ ] **Ouvrir une entité dans fornews par son QID** — attend la route `fornews://entite?qid=Q…`
      (« Demandes à fornews »).

**Vérifié au simulateur le 25/10** : iPhone (feuille, galerie, carte, marqueur → fiche), iPad 13″ en
paysage (galerie à trois colonnes, carte et fiche dans la partie de droite, plein écran). Hook
`OKIA_ANALYTIC=liste|galerie|carte`. **Pas vu** : Mac (verrouillé), Duo, appareil réel.
Limite relevée : « Washington » d'un rapport épinglé sur l'État de Washington, pas sur la capitale.

## ④ Import Word, PDF et PowerPoint — Mac, puis iPhone et iPad

**Ouvert à l'iPhone et à l'iPad le 26/10** (Patrick : « Oui ouvre ») : même option, même code.
Entrées : « Importer Word, PDF ou PowerPoint… » dans le menu « … » de l'iPhone, à l'appui long du
bouton dossier, sur l'écran d'accueil ; « Ouvrir avec » et la feuille de partage (les trois formats
déclarés dans Info.plist, rang « Alternate ») ; dépôt sur la fenêtre. Sans l'option, la vitrine
s'ouvre. Vérifié au simulateur iPhone (Word confié à l'app). **À reporter** : la page de l'option
sur le site et la feuille de route disaient « import sur Mac ».

Fait le 25/10 (`Models/Import/`, `Views/ImportView.swift`) : **Fichier ▸ Importer Word, PDF ou
PowerPoint… (⇧⌘I)**, réservé à l'option (sans elle, la vitrine s'ouvre) ; un fichier déposé sur la
fenêtre ou confié à md Viewer (« Ouvrir avec », `open -a`) s'importe aussi. Le Markdown est écrit dans
« Importés » (documents de l'app) puis ouvert : il entre dans les récents. Aucune bibliothèque : le
zip est lu par `LecteurZip` (répertoire central + `COMPRESSION_ZLIB`), le XML par `NoeudXML`.

- [x] **Word** (`ImportWord`) : titres par style ou niveau de plan (« Titre » → `#`, les autres
      descendent d'un cran), listes à puces et numérotées d'après `numbering.xml`, gras, italique,
      barré, liens (`w:hyperlink` et champs `HYPERLINK`), tableaux, images, notes de bas de page et
      de fin, révisions suivies lues acceptées. **Sans styles** (textutil, Pages, modèles faits à la
      main) : titres reconnus à la taille de police, puces et numéros tapés repris en listes.
- [x] **PDF** (`ImportPDF`, PDFKit) : titres d'après les signets, sinon la taille de police ;
      paragraphes recousus d'après l'écart entre les lignes, mots coupés ressoudés ; en-têtes, pieds
      et numéros de page écartés ; puces. Les images d'un PDF ne sont pas reprises. Un PDF protégé
      ou numérisé (sans texte) le dit.
- [x] **PowerPoint → présentation** (`ImportPowerPoint`) : diapositives dans l'ordre de
      `presentation.xml`, titres, puces avec niveau, tableaux, images, notes de l'orateur et
      commentaires dans un commentaire HTML sous la diapositive. La transition la plus employée va
      dans l'en-tête (`transition:`), et **le diaporama la reprend** pour ce document (le choix de
      l'utilisateur reprend la main s'il en change).
- [x] **PDF scannés** (Patrick, 26/10 : « J'ai eu le cas 1 mais sans message »). Une page sans couche
      de texte (moins de 20 caractères) est lue par la reconnaissance de texte de l'appareil (Vision,
      mode précis, correction linguistique fr/en/de/es/it), puis suit le même traitement que les autres
      (titres par paliers de hauteur, paragraphes, en-têtes écartés) ; elle porte la mention « Page N :
      texte reconnu sur l'image, à vérifier ». Une page dont on ne tire presque rien (moins de
      40 caractères : photo, schéma, manuscrit) est gardée en image. Le résumé dit « dont N pages
      scannées ». Banc (briefing fornews rendu en images) : tout scanné, 10 pages ; mixte, pages 2–3 ;
      page de dessin gardée en image. Le PDF à texte ne change pas. Limites : tableaux en lignes,
      colonnes parfois mêlées, « OpenAl » pour « OpenAI ». **Le message perdu** : l'erreur d'import
      s'affichait pendant que la fenêtre d'avancement se refermait, et SwiftUI l'abandonnait ; elle
      attend désormais la fermeture. Pas vu dans l'app (Mac verrouillé, le simulateur confie un PDF
      à Fichiers) : à essayer sur B94.
- [x] **Compte à rebours** (`ImportView`) : l'étape, le compte, le dernier titre repéré, le temps
      restant estimé, Annuler.
- [x] **Images** : chacune écrite une fois en référence (`![…][img3]`, définition en fin de
      document ; le diaporama reporte les définitions sur chaque diapositive), réduite selon la place
      qu'elle occupe (un logo de coin n'a pas besoin de 1600 px), JPEG à 0,72, PNG gardé seulement
      s'il a de la vraie transparence. PowerPoint réel de 70 diapositives et 41 images : 11 → 7 Mo,
      en 0,7 s. TextPack pas nécessaire à ce stade.
- [x] **Commentaires** repris par défaut : Word en notes `[^c1]` « 💬 Auteur : texte » à l'endroit
      commenté ; PowerPoint avec les notes de l'orateur.
- [x] **Option « Utiliser les commentaires comme consignes »** (idée de Patrick, 25/10) : après la
      lecture, la fenêtre d'import pose la question (rien de coché d'avance ; seulement si Apple
      Intelligence est là). Pour chaque commentaire, le modèle de l'appareil rédige ce qu'il
      demande, à partir du passage commenté et du titre de sa partie ; le texte s'insère sous le
      passage dans un encadré « Rédigé par Apple Intelligence, d'après le commentaire de X », qui
      cite le commentaire. Le texte de l'auteur n'est jamais remplacé ; un commentaire qui ne
      demande rien (« RIEN ») n'ajoute rien. Word et PowerPoint.
- [x] **Rapport d'analyse à la manière de fornews**, proposé à la même question : un second document
      « <nom> — analyse.md », ouvert à la fin (le document importé entre dans les récents). Les
      consignes de fornews copiées mot pour mot par `scripts/copier-fornews.sh`
      (`ConsignesAnalyste`, `ConsignesLocales`) et un extrait de `GenerateurRapportAnalyste`
      (`NettoyageRapport` : tics, marques, redites, nombres et années inventés). Une section par
      appel, session jetable : résumé exécutif, titre (une énumération est refusée), un point clé
      par grande partie du document (cinq au plus), dimension humaine, perspective, voix
      critiques ; une section qui échoue ou répond « RIEN » est absente. ⛔ Une phrase qui avance
      un nombre ou une année absents de la matière est retirée (essai : « entre 2005 et 2020 »
      inventé). Briefing fornews en PDF : 8 000 caractères en 53 s sur le Mac. Ce qui n'est pas
      repris de fornews : la vérification phrase à phrase et la relecture critique (un corpus
      d'articles numérotés, pas un document).
      `OKIA_IMPORT_IA=consignes,rapport|aucun` (Debug) répond à la question, ajouté aux canaris.

**Vérifié sur le Mac le 25/10** (build Debug, `open -a` avec `OKIA_ACHAT=achete`) : le PowerPoint
réel (« Anatomie d'un SI »), un Word d'essai complet (styles, listes, tableau, lien en champ, note,
commentaire, révision, image), le PDF public du briefing fornews. Bancs : Word sans styles (textutil).
**Pas vérifié** : la commande ⇧⌘I et son sélecteur, la feuille d'avancement (l'import est trop rapide
pour la voir), la vitrine sans achat, le diaporama d'un PowerPoint importé — l'app ne se pilote pas
d'ici ; à essayer sur B91.

## ④ ter Une page web, de Safari à md Viewer — demandé par Patrick le 26/10 (option payante)

« Depuis Safari, on peut envoyer la page vers md Viewer qui prépare un rapport analytique de la page
avec entités et tout ce qui est préparé par fornews. » Réservé à l'option ; sans elle, le texte de la
page s'ouvre, puis l'option se présente.

- [x] **La fiche de lecture de fornews, copiée mot pour mot** par `scripts/copier-fornews.sh` :
      `FicheArticle` entière et ses gardes (`VerificateurAncrage`, `AncrageLitteral`, `DrapeauPays`,
      `MoteurFM`, `LangueHelper`, `CarteLeaflet`, `ImageMarkdown`, `CleImage`, `AvertissementIA`),
      plus des extraits de `RapportObsidian` (la composition `generer(donnees:)`, son schéma
      déterministe, sa carte, ses libellés), de `RevuePresse` (pastille, signatures) et d'`Article`
      (`Mesure`). Le script sait maintenant extraire des déclarations par nom.
- [x] **L'extraction** (`PageWeb/ExtrairePage.js`) : titre, média, auteur, date, image, logo, langue
      (métadonnées, données structurées) et le corps de l'article, bloc par bloc ; décor écarté
      (navigation, partage, rubriques). Un seul script : Safari l'exécute dans la page au partage ;
      l'app l'exécute dans une vue web hors écran pour une adresse seule (`LecteurPageWeb`). Éprouvé
      sur The Verge et la RTS.
- [x] **La fiche** (`PageWeb/FichePageWeb`) : entités de md Viewer et vos corrections, lieux situés
      par Wikidata si accepté (carte), résumé « En bref » et chiffres par Apple Intelligence sous les
      gardes de fornews (sinon le chapeau de la page et les chiffres relevés par le code), schéma
      déterministe, signature md Viewer. Écrite dans « Importés » et ouverte ; même compte à rebours
      que l'import.
- [x] **L'extension de partage** (cible `Partage`, `ch.ok-ia.markdownviewer.partage`) : dépose la page
      dans la boîte `BoitePages` (groupe `group.ai.fornews.native`, déjà enregistré), tente d'ouvrir
      md Viewer (`mdviewer://pages`, accepté sur Mac), sinon « Ouvrez md Viewer ». L'app relève la
      boîte à chaque passage au premier plan. `mdviewer://page?url=…` et `OKIA_PAGE` (Debug, canari).
- [x] **Profils de l'extension** : il manquait un compte Apple dans Xcode (« No Accounts ») ; Patrick
      l'a ajouté le 26/10, Xcode a créé l'identifiant et les profils au build 95 (iOS et Mac, groupe
      d'apps compris).
- [x] **Le texte traduit dans la langue de l'interface** (Patrick, 26/10 : « le texte doit être traduit
      dans la langue choisie ») : titre, chapeau et chaque bloc, par le framework Translation sur
      l'appareil (`TraducteurPonctuel`) — session sans vue quand les deux langues sont installées,
      sinon par la fenêtre d'avancement, qui laisse le système proposer leur téléchargement ; deux
      minutes sans session (simulateur), et la fiche garde l'original. La fiche prend alors les
      mentions de fornews : « Traduit de l'anglais », le titre original, la note de fidélité. Les
      entités sont détectées sur le texte d'origine ; le résumé et les chiffres, sur le texte traduit.
      Banc sur le Mac : en→fr, 3 blocs en 2,1 s. **Pas vu dans l'app** (Mac verrouillé, simulateur sans
      traduction).
- [x] **Le schéma écrit par le modèle** (27/10), comme fornews : `genererDiagramme` (extrait de
      `PartageArticleIAView`, `DiagrammeArticle.swift`), validé par `validerDiagrammeIA` et
      `schemaAncre` (un nombre absent du texte l'écarte) ; sinon le schéma des noms cités. Le script de
      copie compte désormais les accolades hors des chaînes et des commentaires (les expressions
      régulières de fornews en sont pleines). **Pas vu** : Apple Intelligence est absente du simulateur.

Vérifié au simulateur iPhone (`OKIA_PAGE`, article de The Verge) : grande image et pastilles, en-tête,
en bref, en chiffres, qui est cité, schéma. Pas vu : le partage depuis Safari (extension), le Mac,
Apple Intelligence (absente du simulateur).

## ④ bis Annotations à l'Apple Pencil — quatrième lot, 25/10/2026

- [x] Banc d'essai fait dans le navigateur, puis dans l'app : PencilKit (`PKCanvasView`) posé dans
      la vue de défilement de WebKit, à la taille de la partie visible (`CalqueAnnotation`).
- [x] Mode « Annoter » (bouton `pencil.tip.crop.circle`, entrée du menu « … » sur iPhone) et sa
      palette : Surligner, Souligner, Écrire, Gomme, quatre couleurs, Terminé. Le calque suit le
      réglage du système « Dessiner uniquement avec l'Apple Pencil » : crayon seul → le doigt fait
      défiler ; sinon (iPhone, Mac, simulateur) on dessine d'un doigt et l'on défile à deux.
      Avant l'achat, le bouton présente l'option. Indisponible dans le livre.
- [x] **Ancrage au texte** (`Web/annotations.js`, à part de render.js que fornews copie) :
      surligner et souligner → plage de texte retrouvée par citation + contexte, dessinée par les
      surlignages natifs de WebKit (`CSS.highlights`), rien d'inséré dans le texte ; écrire → l'image
      du tracé, accrochée au bloc, en largeurs de bloc. Éprouvé : taille du texte, largeur, recherche
      par-dessus, nouveau rendu — tout se repose (observateur de la page).
- [x] Le `.md` n'est jamais modifié : `AnnotationsStore`, un fichier par document (chemin, sinon
      nom) dans Application Support. Gomme : ce que le trait touche disparaît.
- [x] **Partage par CloudKit** (Patrick, 27/10 : « le partage se fera par CloudKit ») —
      `SynchroICloud` : base PRIVÉE, zone `Analytic`, un enregistrement par fichier (`nom`, `modifie`,
      `contenu` en pièce jointe) pour les annotations de chaque document, les corrections et le cache
      d'entités. Envoi par salve (3 s) après chaque écriture ; relève des autres appareils au lancement
      et à chaque retour au premier plan. Conflit : la version la plus récente l'emporte, fichier par
      fichier ; le cache se fusionne (fiche la plus récente), et ne repart que s'il a gagné des fiches.
      Sans compte iCloud, rien ne se passe. Conteneur `iCloud.ch.ok-ia.markdownviewer` créé par Xcode
      le 27/10 (compte de Patrick), entitlements iOS et Mac.
- [ ] **Schéma en Production** : seed comme fornews (`-OKIASeedSchema YES`, build Debug du Mac) —
      **fait le 27/10 à 07 h 23** (« seed RÉUSSI (3 types) », Development). Reste à Patrick :
      CloudKit Console → Deploy Schema Changes — procédure : `docs/cloudkit/deploiement-synchro.md`.
      ⛔ Sans ce déploiement, TestFlight ne synchronise rien (la Production refuse les types inconnus).
- [x] **Une annotation, un seul document** (Patrick, 27/10 : « les annotations doivent être liées à
      un seul document ; il faudra identifier clairement : date, taille, nom de fichier, contenu ») —
      `IdentiteDocument` : nom, taille, date de modification, empreinte SHA-256 du contenu, chemin
      (indicatif), gardés dans le fichier d'annotations. Clé = empreinte du nom ET du contenu : un
      autre texte sous le même nom, ou le même texte sous un autre nom, n'hérite de rien ; la clé est
      la même sur tous les appareils (le chemin et la date n'y entrent pas). Un document modifié est
      un autre document. Les annotations rangées jusqu'à B96 sous le chemin passent sous la nouvelle
      clé à l'ouverture. Vérifié au simulateur (reprise, puis autre texte sous le même nom : rien).
- [x] **Le livre** (27/10) : la page de droite reçoit les annotations (`LivreController.poserAnnotations`)
      et les repose à chaque nouvelle copie ; le mode Annoter s'ouvre dans le livre, un calque sur
      chaque page (`PontAnnotations` interroge la page annotée, quelle qu'elle soit). Le doigt qui
      dessine ne tourne plus les pages ; si le crayon seul dessine (réglage du système), le doigt les
      tourne encore. Vérifié au simulateur iPad 13″ en paysage : annotations sur les deux pages,
      surlignage tracé sur la page de droite, pages qui tournent de nouveau après Terminé.
- [x] **Export PDF** (27/10) : vérifié, il **perdait les surlignages** — le moteur d'impression ne
      peint pas `CSS.highlights`. Le temps de l'export, `OKIA_ANNOT.figer()` les change en vrais
      `<mark class="okia-fige">` (mêmes couleurs, annotations.css), `defiger()` les retire. Les notes
      manuscrites sont désormais placées en pourcentages de leur bloc (la marge du haut, dont le %
      se prend sur la largeur) : elles restent à leur place sur la feuille, plus étroite que l'écran,
      comme dans le livre. Vérifié au simulateur (`OKIA_EXPORT_PDF`, Debug, canari) : surlignage et
      note dans le PDF, annotations reposées à l'écran ensuite.
- [x] **Document traduit** (27/10) : le bandeau de traduction le dit — « Traduit sur l'appareil ·
      anglais · 3 annotations sur l'original » (pluriel dans les cinq langues), « Voir l'original »
      juste à côté. **Pas vu** : le simulateur ne traduit pas.
- [ ] **iPhone Duo** : le crayon y fonctionnera **dès iOS 27.2** (Patrick, 25/10) — rien à changer,
      le calque suit le réglage du système ; d'ici là, au doigt. À vérifier sur l'appareil, postures
      comprises.
- [x] **Annoter une diapositive pendant le diaporama** (Patrick, 27/10 : « les annotations sont possibles
      sur le diaporama »). Les mêmes annotations que le lecteur : une diapositive reprend le texte du
      document, `annotations.js` les pose sur `#deck` (le bloc d'une note se cherche dans la diapositive
      affichée). Bouton crayon à droite de la vue d'ensemble, montré avec l'option ; la palette y gagne
      deux flèches (le calque prend le doigt, la diapositive ne se balaie plus ; le clavier marche
      toujours). Le lecteur relit les annotations au retour. Vérifié au simulateur iPad 13″
      (`OKIA_OPEN_SLIDES`) : annotation du document sur la diapositive 2, surlignage tracé dans le
      diaporama, retrouvé dans le lecteur. **Pas vu** : le Mac (souris), un vrai crayon.

**Vérifié au simulateur le 25/10** : iPad 13″ (surligner, souligner en couleur, écrire, gomme,
relance → annotations retrouvées), iPhone 17 Pro Max (défilement à deux doigts, palette au-dessus de
la recherche). Hook `OKIA_ANNOTER=surligner|souligner|ecrire|gomme`. **Pas vu** : un vrai crayon,
le Mac (souris), le Duo.

## ⑤ Modèles plus poussés — sortis de la 1.4 (⓪ a dit non, 25/10)

- [ ] ~~Private Cloud Compute~~, au choix explicite de l'utilisateur, document par document, jamais par
      défaut ; libellés clairs sur ce qui quitte l'appareil.

## ⑥ Publication

- [x] Feuille de route publique (FR et EN) : en test, 3 et 5 francs, annotations (OK-ia#524) ;
      import partout, PDF scannés, options d'Apple Intelligence, signaler une erreur (OK-ia#526) ;
      la page web depuis Safari, traduite, et le calendrier « après fornews 1.7.4 » (OK-ia#527, 27/10).
- [ ] Politique de confidentialité mise à jour (Wikidata, iCloud ; pas de PCC). Texte proposé le
      25/10, section « Accès à Internet » — FR : « **Wikidata (option Analytic).** Pour compléter
      une entité que le document ne décrit pas (sa nature, sa position, sa photo), md Viewer peut
      interroger Wikidata, la base de connaissances libre de la Fondation Wikimedia. Seul le **nom
      de l'entité** est envoyé, jamais le document ni son titre, et seulement si vous l'avez
      autorisé ; vous pouvez couper cette recherche à tout moment dans les réglages. Les réponses
      sont gardées dans un petit cache, sur l'appareil et dans votre iCloud privé. Les photos
      viennent de Wikimedia Commons. Comme pour toute requête web, Wikimedia peut recevoir votre
      adresse IP. » — à compléter : la description vient aussi de **Wikipédia** (résumé de
      l'article), et « dans votre iCloud privé » n'est vrai qu'une fois le partage fait.
      **À ajouter depuis le 26/10** (page web, ④ ter) : une page partagée depuis Safari est lue
      dans Safari même ; pour une adresse seule, md Viewer charge la page comme un navigateur. Les
      images de la fiche s'affichent depuis le site de la page ; ses lieux passent par Wikidata si
      l'utilisateur l'a accepté. La
      fiche est composée sur l'appareil, et sa traduction aussi (le système peut demander de
      télécharger une langue, comme pour un document). À publier à la sortie, pas avant : la
      politique décrit ce que l'on télécharge sur l'App Store.
      **À ajouter depuis le 27/10** (CloudKit) : les annotations, les corrections et le cache des fiches
      passent par la base **privée** iCloud de l'utilisateur (CloudKit), pour ses autres appareils ;
      nous n'y avons pas accès. Les fichiers Markdown n'y vont pas. Une annotation garde le passage
      qu'elle marque (quelques dizaines de caractères) et l'empreinte du document, pas le document.
- [ ] Fiche App Store, captures, notes de version, post Mastodon.
