# md Viewer 1.5

Le 6 novembre 2026, une fois la 1.4 en vente partout, Patrick a affecté à la 1.5 tous les points
restants : ceux qu'il avait gardés pour plus tard pendant la 1.4, et les défauts vus pendant la 1.4.

Les travaux côté fornews.ai relevés pendant la 1.4 (filtre des entités à majuscule, genres en
cinq langues, reprise des diffs de `render.js`) n'en font pas partie : ils restent pour fornews 2.0,
comme décidé le 29 octobre 2026.

## Notes de l'orateur (demande du 1er novembre 2026)

Patrick : « Je ne trouve pas comment ajouter les notes de l'orateur », puis « Prend note pour une
prochaine version ».

**Aujourd'hui (1.4).** md Viewer n'écrit pas de notes : il lit celles du fichier, les commentaires
HTML d'une diapositive (`<!-- … -->`, avant le `---` suivant). `presentation.js` les extrait
(`notes(index)`), et seul le mode présentateur les montre (`ModePresentateur.swift`, option Analytic
et second écran). L'import PowerPoint les y range (« Notes de l'orateur : »). La syntaxe n'est
documentée nulle part pour l'utilisateur.

**Fait le 6 novembre 2026 (non poussé, à essayer sur appareil) :** bouton « Notes » du diaporama
et crayon de la colonne du présentateur, avec l'option ; la note s'écrit dans le fichier par
`presentation.js` (`ecrireNote`, banc `tools/render-tests/notes.html`, 21 vérifications) et
`NotesOrateur.enregistrer` ; l'empreinte du document ne compte plus les commentaires
(`IdentiteDocument.sansMarques`, reprise des annotations rangées sous l'ancienne clé) ; pages de
notes dans l'export PowerPoint ; guide `docs/GUIDE-PRESENTATION.md`. Vu au simulateur iPad : éditeur,
écriture du fichier, colonne du présentateur, export. Pas vu : l'ouverture du PowerPoint exporté dans
PowerPoint ou Keynote, le Mac, un fichier du coffre dans iCloud.

**À faire :**
- [x] Écrire et modifier les notes de chaque diapositive dans l'app : depuis le mode présentateur,
      la grille des vignettes de la présentation générée, ou les deux. Elles s'écrivent dans le
      `.md` en commentaire HTML sous la diapositive (`--` interdit dans un commentaire : le
      remplacer, comme l'import). ⚠️ Écrire dans le fichier change son empreinte : les annotations
      du document y sont liées (`IdentiteDocument`) — exclure les notes de l'identité, comme les
      marques des diapositives masquées, ou faire suivre les annotations.
- [x] Reprendre les notes dans l'**export PowerPoint** (`OOXMLExport` n'écrit pas de
      `notesSlide`) : aller-retour complet avec l'import.
- [x] La **conversion en présentation** par Apple Intelligence propose des notes tirées du rapport
      (décidé par Patrick le 6 novembre 2026 : « Oui »). Interrupteur « Proposer des notes de
      l'orateur », option Analytic, jamais coché d'avance ; les notes viennent du même appel que les
      puces (propriété `notes` du schéma), chaque phrase est vérifiée contre les nombres de la
      section (`noteVerifiee`). Au banc sur ce Mac, vrai modèle : rapport français (8 diapositives,
      3 notes, 10,6 s) et allemand (9 diapositives, 3 notes, 10,1 s), aucune phrase écartée, langue
      tenue. Le banc ne compilait plus depuis la 1.4 (`DiapositivesMasquees` vivait dans une vue) :
      l'enum est passé dans `PresentationConverter.swift`. Vu au simulateur : le réglage. Pas vu :
      une conversion dans l'app (le simulateur ne génère pas).
- [ ] Documenter la syntaxe : page `mdviewer/import-et-annotations.html` (ou une page du
      diaporama), base du Terminal IA (`public/data/mdviewer-kb.md`), `docs/GUIDE-PRESENTATION.md`.
      `docs/GUIDE-PRESENTATION.md` fait le 6 novembre ; la page du site et la base du Terminal IA
      attendent la sortie de la 1.5.

## Images embarquées perdues à l'export Word et PowerPoint (demande du 1er novembre 2026)

Vu en écrivant `docs/PROMPT-PRESENTATION-SVG.md` ; lu dans le code, pas essayé dans l'app.
`exportModel` (render.js) passe une image comme `{ t: 'image', src }`, mais `OOXMLExport` ne
télécharge que les `src` en `http` (`imageURLs`) : une image en `data:` n'est jamais résolue et
disparaît de l'export. Cela touche les images des documents importés (Word, PDF, PowerPoint, 1.4)
comme les SVG embarqués en base64 du prompt de présentation.

**Fait le 6 novembre 2026 (build 153 à venir) :** `OOXMLExportBridge.imageDeDonnees` décode les
`data:` (PNG et JPEG tels quels, le reste converti en PNG) ; `render.js` dessine en PNG les images
SVG (`imgToPng`) et les `<svg>` écrits en clair (`svgToPng`), à la taille d'affichage × 2. Défaut
trouvé en route : les images paresseuses (`loading="lazy"`) hors de l'écran ne se chargeaient
jamais, et le SVG d'une diapositive manquait au PowerPoint ; `imgToPng` force leur chargement.
Banc `tools/render-tests/export-images.html` (7 vérifications, navigateur et Safari du
simulateur). Vu au simulateur iPad : un PowerPoint avec un PNG en `data:`, un SVG en base64 et un
`<svg>` en clair porte ses trois images.

- [x] Essayer dans l'app : export PowerPoint au simulateur (le Word passe par le même code, pas
      essayé).
- [x] Décoder les `data:image/…;base64` côté Swift (JPEG et PNG tels quels).
- [x] SVG : rastérisé en PNG côté JavaScript avant l'export, comme les diagrammes Mermaid.
- [x] Vérifier l'export PDF avec les mêmes documents. **Fait le 12 novembre 2026 (build 157) :**
      au simulateur iPad, par le harnais `OKIA_RACCOURCI=pdf`, un document de 40 paragraphes suivis
      d'un PNG en `data:`, d'un SVG en base64 et d'un `<svg>` en clair : les trois images sont dans
      le PDF (le chargement forcé des images paresseuses existait déjà). Deux défauts corrigés :
      - une page à moitié vide avant le PNG, puis six passes de rendu pour rien. La recherche des
        titres isolés en bas de page lisait le seul texte ; une image n'en a pas, si bien qu'un
        titre suivi de son image passait pour isolé, et un titre en haut de page suivi d'une image
        était retrouvé à chaque passe. Désormais un titre par passe, jamais celui qui ouvre sa
        page, ni celui sous lequel quelque chose est dessiné (pixels de la page rendue à
        demi-échelle). Résultat : 7 pages au lieu de 8, deux rendus au lieu de sept ;
      - le `<svg>` en clair collé à gauche, les images centrées. Écrit sur une ligne, il arrive
        dans un `<p>` (CommonMark) : `svgSeuls` (render.js) le marque `okia-svg-bloc` quand il
        est seul dans son paragraphe, et il se centre, à l'écran comme dans le PDF.
      Bancs `svg.html` 7/7 et `export-images.html` 7/7.

## Défauts vus pendant la 1.4

- [x] Anglais : « Search the Store », « Search the Store… » et « Neither the Store nor Analyzed
      Documents contain any documents. » disent « Store » ; l'anglais garde « vault » (seuls
      l'allemand, l'espagnol et l'italien disent « Store »).
      Fait le 6 novembre 2026, avec un quatrième trouvé en route (« Search your whole Store… »).
- [x] Un `<svg>` en clair dans le document (réponse d'IA) garde sa largeur : avec
      `width="1600"`, il déborde de la page en lecture et du cadre en diaporama (vu dans le lecteur
      en ligne le 2 novembre 2026 ; même CSS dans l'app, pas essayé dans l'app). Borner
      `svg[width]` hors Mermaid dans `style.css` et `presentation.css` (max-width 100 %, height
      auto), dans l'app et dans le lecteur en ligne. Les prompts contournent déjà avec
      `width="100%"`.
      Fait le 6 novembre 2026 dans l'app (`svg[width][viewBox]`, hors Mermaid, cartes et icônes ;
      banc `tools/render-tests/svg.html`, 7 vérifications). Lecteur en ligne : même règle,
      committée sur la branche `claude/svg-bornes` du site, pas encore envoyée.

## Régression du Duo dans les builds 152 et 153 (signalée par Patrick le 11 novembre 2026)

Patrick : « sur le duo, la charnière n'est plus respectée ». Cause : Xcode est passé en 27.2, et
`DUO_SDK` n'était défini que pour les SDK 27.1 (`project.yml`) ; tout le code du Duo — charnière,
livre, seconde partie, colonne du système — est sorti des builds 152 et 153 sans erreur. Le build 151
en vente (1.4, SDK 27.1) n'est pas touché. Vérifié : aucune trace de `UIHingeInteraction` dans le
binaire du 153.

- [x] `DUO_SDK` défini pour tous les SDK iOS (`[sdk=iphoneos*]`, `[sdk=iphonesimulator*]`).
- [x] `scripts/deploy-testflight.sh` refuse un binaire iOS sans `UIHingeInteraction`.
- [x] Compilé iOS (SDK 27.2) et Mac ; au simulateur Duo plié, les commandes reviennent dans la
      colonne du système.
- [ ] Build 154 à essayer sur le vrai Duo : déplié, mi-replié (livre), « mini-ordinateur ».

## Un dossier partagé d'un iMac comme coffre (demandé par Patrick le 11 novembre 2026)

Patrick : « Je désire utiliser comme coffre un répertoire partagé de mon iMac et cela ne fonctionne
pas », puis « Oui » à la lecture en profondeur. Le coffre ne lisait que les sous-dossiers de premier
niveau nommés `rapports-*` (la forme du coffre de fornews), et deux échecs restaient muets.

- [x] Lecture des `.md` et `.markdown` de la racine et de tous les niveaux des sous-dossiers que
      retient le motif, `*` par défaut (`VaultStore.lire`) ; dossiers cachés (`.obsidian`, `.git`)
      et paquets ignorés ; bornes : 8 niveaux, 3 000 fichiers, 4 secondes, avec une mention à
      l'accueil quand une borne arrête la lecture.
- [x] La relecture périodique du Mac et celle de l'accueil se font hors du fil principal : un
      partage réseau lent ne gèle plus l'app.
- [x] Un dossier que le système refuse de retenir le dit (alerte) ; un coffre injoignable (partage
      déconnecté) le dit à l'accueil, avec le nom du dossier gardé.
- [x] Vu au simulateur iPad : coffre d'essai à trois niveaux (racine, `Projets/2026/Novembre`,
      `.markdown`, `rapports-veille` ; `.obsidian` et `.txt` ignorés), ouverture du fichier le plus
      profond, coffre illisible signalé. Compilé iOS et Mac.
- [ ] À essayer avec le vrai partage de l'iMac : sur Mac (volume monté dans le Finder) et sur
      iPhone ou iPad (serveur ajouté dans Fichiers), y compris après un redémarrage de l'iMac.
- [ ] À la sortie : la base du Terminal IA décrit encore le coffre en `rapports-*`.

## Entités mal détectées dans les documents à carte (signalé par Patrick le 11 novembre 2026)

Captures du Duo : l'analyse du coffre donnait « 12 entités », toutes géopolitiques, nommées
« Berlin · sommet Invest in Germany du 19 octobre · d… », « Santa Clara · Nvidia et AM… » et
« Santa Clara · siège de Nvid… ». Deux causes :

- [x] L'étiquette entière d'une épingle de la carte devenait le nom du lieu : il est maintenant pris
      avant le premier séparateur (`·`, `—`, `–`, `|`, ` - `) — `LecteurRapportFornews.nomDuLieu`.
      Les deux formes de ligne sont lues : `type, lat, lon, étiquette` (fornews) et
      `lat, lon, étiquette` (cartes écrites à la main, que l'analyse ignorait).
- [x] Un document à carte sans section « Entités » passait pour un rapport fornews : la détection
      n'était pas lancée, d'où ni personne ni organisation. Seule la section fait un rapport
      (`aUneSectionEntites`).
- [x] Index du coffre en « v3 » : tout est relu une fois.
- [x] Vu au simulateur iPad : Berlin, Miami Beach, Santa Clara (une seule), Lisa Su, Olaf Scholz,
      Nvidia, AMD, Creative Cloud.
- [x] Le fichier de Patrick (« entité du jour » de fornews, Jensen Huang) : la section est en
      `### Entités`, ses genres en `####`, et toutes les entités d'un genre sur une ligne
      (`[[Microsoft]] (1674) · [[OpenAI]] (1060) · …`) — elle était ignorée, par l'analyse comme
      par le lecteur (`render.js`, `extractEntities`). Désormais : titre à tout niveau, genres au
      niveau suivant, plusieurs liens par ligne ; « Thèmes » écartés, « Modèles » en produits. Les
      épingles sont des liens qui portent leur légende (`[[Santa Clara · siège de Nvidia · …]]`) :
      le lieu en est tiré aussi. Vu au simulateur avec ce fichier : 8 personnes, 6 organisations,
      11 lieux à leur seul nom, 3 produits ; au lecteur, la légende et les couleurs des entités.

## Un coffre à travers Tailscale : la latence (demandé par Patrick le 11 novembre 2026)

Patrick : « Est-ce que tu tiens compte d'une latence pour ouvrir le coffre à travers un
tailscale ? », puis « Oui change et b155 ».

- [x] Les dossiers d'un même niveau se lisent ensemble (8 à la fois) : une structure année / mois
      se lit en trois vagues.
- [x] Volume réseau reconnu (`volumeIsLocal`, serveurs de Fichiers sous `/LiveFiles/`) : lecture
      jamais sur le fil principal, borne de 20 s au lieu de 4, relecture du Mac toutes les 60 s au
      lieu de 5 ; le signet se résout sans monter le volume (un partage absent ne fige plus l'app).
- [x] La dernière liste est gardée (`coffre-liste.json`) et montrée dès le lancement ; « Lecture du
      coffre… » pendant la première lecture ; un partage qui ne répond pas un instant ne vide plus
      l'accueil.
- [x] Harnais `OKIA_LATENCE_COFFRE=<ms>` (Debug, refusé par le script dans un binaire livré). Au
      simulateur, 48 dossiers à 200 ms : liste complète en 1 à 2 s au lieu d'une dizaine ; à 3 s par
      dossier, la liste gardée s'affiche à l'ouverture.
- [ ] À essayer sur le vrai partage de l'iMac à travers Tailscale (build 155).


## Un bouton pour recharger le coffre (demandé par Patrick le 12 novembre 2026)

Patrick : « il faut ajouter un bouton pour forcer le rechargement du coffre. »

- [x] ↻ dans l'en-tête du coffre (une roue pendant la lecture) ; sur Mac, Fichier › Recharger le
      coffre (⌘R). La relecture part tout de suite, hors du fil principal, même pour un dossier
      réseau relu il y a moins de 60 s ; demandée pendant une lecture, elle la suit.
- [x] Un partage déconnecté est remonté par ce bouton seulement (signet résolu sans
      `.withoutMounting`) ; la mention « ne répond pas » dit désormais de recharger le coffre (↻).
- [x] Au simulateur (iPad, 300 ms par dossier) : un fichier ajouté au coffre de test apparaît sous
      « Aujourd'hui » après ↻ ; à 2 s par dossier, la roue remplace ↻ pendant la lecture.
- [ ] À essayer : le remontage d'un partage de l'iMac déconnecté (Mac, puis iPad).

## Un graphique Mermaid en erreur de syntaxe (signalé par Patrick le 12 novembre 2026)

Patrick, avec la fiche fornews `entite-gemini.md` : « Il y a un diagramme mermaid qui fait une
erreur de syntaxe. Je pense le 1er. »

- [x] Cause : un `xychart-beta` dont l'axe x porte des dates sans guillemets
      (`x-axis [29/10, 30/10, …]`). Mermaid 11.15 refuse la barre oblique hors guillemets
      (« Lexical error … Unrecognized text ») ; la ligne `%%{init}%%` n'y est pour rien.
- [x] `reparerXychart` (render.js) met entre guillemets, avant le rendu, les étiquettes de
      `x-axis [ … ]` qui n'en ont pas ; une étiquette déjà entre guillemets reste telle quelle,
      virgule comprise ; un axe numérique (`0 --> 10`) et les autres diagrammes ne sont pas
      touchés. Le fichier n'est pas modifié.
- [x] Vu dans le lecteur (navigateur, six cas) et au simulateur iPad avec la fiche entière : le
      graphique et ses quatorze dates.
- [ ] Les fiches viennent des routines Claude « Rapport de veille fornews — IA quotidien » et
      « Veille hebdomadaire espace et environnement » : leur section Mermaid exige la palette, pas
      les guillemets des étiquettes (prompt à compléter avec l’accord de Patrick). `reparerXychart`
      à reprendre dans `MoteurMdViewer` de fornews (fornews 2.0, voir le sens de copie de render.js).

## L'accueil qui se fige (signalé par Patrick le 12 novembre 2026)

Patrick, capture de l'accueil sur iPhone à l'appui : « À certain moment l'écran principal de md
Viewer colle ». Son coffre est le partage de l'iMac, à travers Tailscale.

- [x] Cause probable, lue dans le code (pas reproduite : le simulateur n'a pas de partage lent) :
      l'accueil résolvait des signets sur le fil principal. Chaque carte du coffre résolvait deux
      fois celui du dossier ; chaque carte des récents le sien, en autorisant le montage du
      volume ; le coffre aussi au lancement, pour son nom. Résoudre un signet touche au disque :
      sur un partage réseau, c'est un aller-retour, et une longue attente si le partage dort.
- [x] Le coffre garde sa racine résolue (`racine`), la résout hors du fil principal pour l'accueil
      (`racineHorsFil`) et pour ses relectures, et montre au lancement le nom gardé.
- [x] Les récents gardent leurs signets résolus et leurs chemins ; l'accueil les résout hors du fil
      principal, sans monter de volume (`resoudreHorsFil`). Les cartes demandent leur document
      de façon asynchrone (`CarteDocument.resoudre`).
- [x] Vu au simulateur iPad (coffre de test, 300 ms par dossier) : cartes et vignettes du coffre et
      des récents, ouverture d'une fiche du coffre, retour à l'accueil.
- [ ] À essayer sur l'iPhone, avec le partage de l'iMac (build 159).

## La liste des entités du coffre qui saute au défilement (signalé par Patrick le 12 novembre 2026)

Patrick, capture du Duo à l'appui : « Lorsque je scrolle dans la liste des entités il me semble que
la liste se rafraîchit et je ne peux pas bien naviguer. »

- [x] Cause : le défaut du lecteur corrigé au build 120. iOS 27 réduit la barre de navigation au
      défilement ; le résumé du haut (« 6 documents · 135 entités ») et la grille suivaient la zone
      sûre, le système y voyait un défilement inverse et rétablissait la barre, sans fin. Sur la
      capture, la barre est réduite (ni titre ni « Fermer »).
- [x] `barreSansReduction()` posé sur l'analyse du coffre (`AnalyseCoffreView`), la seule autre vue
      à bandeau en haut.
- [x] Vu au simulateur du Duo (coffre de test, 42 documents) : après défilement, la barre reste
      entière, le résumé ne bouge plus.
- [ ] À essayer sur le vrai Duo.

## La liste des documents qui colle à l'ouverture (signalé par Patrick le 12 novembre 2026)

Patrick, après le build 160 : « La liste des documents colle encore un peu. Lors du changement d'un
document, peut-on avoir une information qui dise que le chargement est en cours ? »

- [x] Cause : toucher un document de l'accueil (coffre, récents, documents analysés) ou de la fiche
      d'une entité lisait le fichier sur le fil principal, puis en faisait le signet des récents.
      Sur le partage de l'iMac ou un fichier iCloud encore dans le nuage, des secondes d'écran figé.
- [x] `DocumentStore.ouvrirHorsFil` : le fichier est trouvé, lu et son signet fait hors du fil
      principal ; le dernier document choisi l'emporte. Les Raccourcis, Spotlight et les fenêtres
      restaurées gardent `openVaultReport` / `open(url:)`, qui rendent la main avec le document.
- [x] Un bandeau « Ouverture de « … »… » en bas de l'écran (accueil comme lecteur), après 0,15 s
      pour ne pas clignoter sur un fichier local ; traduit dans les 15 langues.
- [x] Vu au simulateur iPad (`OKIA_LATENCE_COFFRE`, qui ralentit aussi la lecture d'un document,
      en Debug) : le bandeau s'affiche, l'écran répond pendant le chargement, un second document
      touché remplace le premier. Compilation Mac réussie.
- [ ] À essayer sur l'iPhone et le Duo, avec le partage de l'iMac.
