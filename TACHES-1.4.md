# 1.4 — « L'option Analytic »

Ouverte le **08/10/2026**, à la demande de Patrick. La 1.3 n'est pas encore sortie (elle attend le
Duo) : rien de la 1.4 n'entre dans la 1.3. Le détail et les raisons sont dans le README, section
« 1.4 — l'option Analytic ».

**Slogan** : « md Viewer — vos documents prennent vie. » / « md Viewer — your documents come
alive. »

**Principe** : on valorise au maximum le document. Un rapport fornews donne déjà presque tout ;
Wikidata ne comble que ce qui manque.

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
- [ ] **Capture d'examen du produit Mac** : à prendre sur le Mac (`OKIA_ACHAT=vitrine`) — il reste
      MISSING_METADATA d'ici là, donc **introuvable dans le bac à sable** : un build Mac avec ce lot
      fermerait les entités aux testeurs Mac. Celle de l'iPhone est envoyée
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

**Vérifié au simulateur le 25/10** (rapport de veille réel « Ukraine · Kiev », 56 entités) : iPhone
17 Pro Max en feuille, iPad 13″ en paysage dans la partie de droite, interface en anglais, Wikidata
accepté puis refusé, toucher → mention surlignée. **Pas vérifié** : le Mac (écran verrouillé, le
build Catalyst compile), le Duo, un vrai appareil.

**Limites connues de la résolution par le nom seul** (même algorithme que fornews) : « Elysée »
rattaché à une salle des fêtes d'Ostende ou à un aérodrome australien selon les jours, « Andrei
Vorobyov » à un footballeur homonyme. Le remède est le cache de fornews, qui connaît le bon QID.

**Constaté en passant** : fornews exporte `[[7]]` parmi ses organisations ; md Viewer l'écarte de la
liste, mais `render.js` surligne encore chaque « 7 » de la prose.

### Demandes à fornews (à faire dans fornews.ai, pas d'ici)

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
- [ ] **Ouvrir une entité dans fornews par son QID** — attend la route `fornews://entite?qid=Q…`
      (« Demandes à fornews »).

**Vérifié au simulateur le 25/10** : iPhone (feuille, galerie, carte, marqueur → fiche), iPad 13″ en
paysage (galerie à trois colonnes, carte et fiche dans la partie de droite, plein écran). Hook
`OKIA_ANALYTIC=liste|galerie|carte`. **Pas vu** : Mac (verrouillé), Duo, appareil réel.
Limite relevée : « Washington » d'un rapport épinglé sur l'État de Washington, pas sur la capitale.

## ④ Import Word, PDF et PowerPoint — Mac seulement

- [ ] Extraction du texte et des images : PDFKit pour le PDF ; pour le `.docx`, éprouver d'abord ce
      que Catalyst sait lire (AppKit le fait, UIKit pas d'office) — sinon extraction du zip XML.
- [ ] **Générer un rapport au format md Viewer**, comme fornews génère un rapport d'article :
      reprendre au maximum son code (`GenerateurRapportAnalyste`).
- [ ] **Compte à rebours** pendant l'import, inspiré de `CompteReboursDemandeView` de fornews, qui
      montre les éléments détectés au fur et à mesure.
- [ ] **PowerPoint → présentation md Viewer** (ajouté par Patrick le 08/10) : lire le `.pptx` (zip
      de XML, le chemin inverse d'`OOXMLExport`) — diapositives dans l'ordre de `presentation.xml`,
      titre en `##`, puces, tableaux, images de `ppt/media/`, notes de l'orateur ; une diapositive
      par bloc séparé par `---`. Les transitions connues reviennent en transition du diaporama.
- [ ] **Images** : `data:image/…;base64` pour quelques petites images (déjà lu par md Viewer) ;
      au-delà, le format **TextBundle / TextPack** (`.md` + `assets/`, zippé en `.textpack`) —
      md Viewer apprend à l'ouvrir.

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
- [ ] **Partage par iCloud** : attend la capacité iCloud (même question que le cache d'entités).
- [ ] **Le livre** : les deux pages ne portent pas encore les annotations ; le mode Annoter y est
      fermé.
- [ ] Export PDF avec les annotations : à vérifier (les surlignages natifs et les images sont dans
      la page, l'export devrait les prendre).
- [ ] Document traduit : les annotations, ancrées dans la langue d'origine, disparaissent le temps
      de la traduction (signalées « orphelines ») — à dire à l'écran.
- [ ] **iPhone Duo** : le crayon y fonctionnera **dès iOS 27.2** (Patrick, 25/10) — rien à changer,
      le calque suit le réglage du système ; d'ici là, au doigt. À vérifier sur l'appareil, postures
      comprises.
- [ ] À décider : annoter une diapositive pendant le diaporama.

**Vérifié au simulateur le 25/10** : iPad 13″ (surligner, souligner en couleur, écrire, gomme,
relance → annotations retrouvées), iPhone 17 Pro Max (défilement à deux doigts, palette au-dessus de
la recherche). Hook `OKIA_ANNOTER=surligner|souligner|ecrire|gomme`. **Pas vu** : un vrai crayon,
le Mac (souris), le Duo.

## ⑤ Modèles plus poussés (si ⓪ dit oui)

- [ ] Private Cloud Compute, au choix explicite de l'utilisateur, document par document, jamais par
      défaut ; libellés clairs sur ce qui quitte l'appareil.

## ⑥ Publication

- [ ] Feuille de route publique (FR et EN) — après les décisions de ⓪.
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
- [ ] Fiche App Store, captures, notes de version, post Mastodon.
