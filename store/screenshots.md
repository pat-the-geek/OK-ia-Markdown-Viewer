# Captures d'écran — App Store

## Jeu de la 1.4 (29 octobre 2026)

Dix scènes, quinze langues, numérotées sur deux chiffres (« 10 » ne passe plus avant « 2 ») :

```
scripts/demo-cache.sh <langue>                       cache d'entités de la démonstration (une fois)
scripts/screenshots.sh <langue> [iphone|ipad|mac|duo|deplie|moyen]
scripts/legender.py [langue …]                       habillage → store/captures-legendees-1.4/
python3 scripts/asc/captures.py [emplacement …] --essai   ce qui partirait (lecture seule)
python3 scripts/asc/captures.py [emplacement …]      envoi, avec l'accord de Patrick
```

L'envoi (après `set -a; . scripts/deploy.env; set +a`) prend `store/captures-legendees-1.4/` :
tous les emplacements si aucun n'est nommé, `APP_DESKTOP` vers la fiche macOS, les autres vers
la fiche iOS, et remplace les captures des emplacements visés. Une langue absente de la fiche
est ignorée : les dix langues ajoutées le 29/10 demandent d'abord leur fiche (textes à rédiger).

**État au 30/10/2026** : iPhone 6,9", iPhone 6,3", Duo (déplié et plié) et iPad légendés dans les
quinze langues. **Mac à faire** (MacBook déverrouillé) : `store/screenshots/mac/` ne garde que
les captures de la 1.3 (de, en, es, it), sans légende dans le jeu 1.4 : `legender.py` les ignore.

| Scène | Écran | Légende (fr) |
|---|---|---|
| `01-accueil` | l'accueil en cartes (démonstration) | Vos documents, d'un coup d'œil. |
| `02-lecteur` | le lecteur | Vos fichiers Markdown, enfin lisibles. |
| `03-entites` | les entités du document, en galerie | Les lieux du document, en images. |
| `04-carte-entites` | les mêmes, sur la carte | Chaque lieu, sur la carte. |
| `05-import` | un PDF importé (rapport, photos, tableau) | Un PDF ou un Word devient un rapport. |
| `06-coffre` | l'analyse du coffre, en galerie | Tout votre coffre, analysé. |
| `07-conversion` | la présentation qui se construit | Un rapport devient une présentation. |
| `08-diaporama` | le diaporama | Présentez-la en plein écran. |
| `09-resume` | le résumé (Mac seulement) | L'essentiel du document, en quelques lignes. |
| `10-discussion` | la discussion | Posez vos questions au document. |

Sortis du jeu de la 1.3 (Patrick, 28/10/2026) : thèmes, Mermaid, carte d'une adresse.

**La démonstration** (`store/demo/<langue>/`) : un coffre de quatre rapports touristiques fictifs
sur des lieux réels de Suisse, sans personne ni marque (« Tourisme suisse », traduit), deux
documents analysés, et le cache d'entités. Le harnais `OKIA_DEMO=<dossier>` (Debug) la montre à la
place des vrais récents, coffre, documents analysés et cache, et coupe la synchro iCloud : sur le
Mac, où le build Debug partage le conteneur et l'iCloud de l'utilisateur, rien n'est lu ni écrit.
Les dates du coffre sont rejouées à partir du jour de la capture (« Hier », « 7 derniers jours »).

- **Photos et descriptions** : celles de Wikidata et de Wikimedia Commons (licences libres). Les
  vignettes du coffre sont les photos Commons des lieux.
- **Lieux choisis pour se résoudre juste** : « Lac Léman » partait au Canada, le Château de
  Chillon et le Glacier d'Aletsch ne se résolvaient pas (défauts de la résolution par le nom,
  notés) — écartés. Les noms sont ceux de chaque langue (`Genf`, `Ginebra`, `Ginevra`…).
- **Le cache d'entités** (`store/demo/<langue>/Analytic/entites-v2.json`) vient de
  `scripts/demo-cache.sh`, qui ouvre les entités de chaque rapport au simulateur : l'analyse du
  coffre n'interroge pas Wikidata, elle reprend ce que la lecture a trouvé.
- **L'import est un vrai import** : les sources (`store/demo-sources/<langue>/*.md`) sont
  exportées en PDF par l'app (`OKIA_EXPORT_PDF`), puis relues par l'import PDF
  (`tools/BancPDF`). Le document importé (3 Mo d'images) passe par `OKIA_RENDER_FILE`.
- **Sans document** : `01-accueil` et `06-coffre` ne rendent rien, ils montrent la démonstration.
- `OKIA_CAPTURE` masque la ligne de diagnostic des entités (montrée en Debug et en TestFlight).
- **Duo** : dix captures au plus par emplacement — les neuf scènes dépliées, puis le lecteur plié.

## Jeu de la 1.3 (9 octobre 2026)

Huit scènes, cinq langues, puis un habillage légendé :

```
scripts/screenshots.sh <langue> [iphone|ipad|mac]   captures brutes → store/screenshots/
scripts/legender.py [langue …]                       habillage → store/captures-legendees-1.3/
```

| Scène | Écran | Légende (fr) |
|---|---|---|
| `1-lecteur` | le lecteur, barre en Liquid Glass | Vos fichiers Markdown, enfin lisibles. |
| `2-conversion` | la présentation qui se construit, 7 diapositives sur 10 | Un rapport devient une présentation. |
| `3-diaporama` | le diaporama de cette présentation | Présentez-la en plein écran. |
| `4-themes` | le panneau « Aa », thème Lecture longue | Cinq thèmes de lecture. |
| `5-mermaid` | les diagrammes | Vos diagrammes s'affichent, pas leur code. |
| `6-carte` | la carte | Une adresse devient une carte. |
| `7-resume` | le résumé (Mac seulement) | L'essentiel du document, en quelques lignes. |
| `8-discussion` | la discussion | Posez vos questions au document. |

Les légendes des cinq langues sont dans `store/legendes.json` ; la police est la Nunito Black de
l'app. Sur le Mac, la conversion, le résumé et la discussion s'ouvrent à côté du document ; sur
l'iPhone, dans une feuille ; sur l'iPad, à côté en paysage (`IPAD_PAYSAGE=1`, une fois le
simulateur tourné à la main — l'app ne sait pas le tourner seule), en feuille en portrait.

**Refait le 09/10/2026 au soir, avec le nouveau look** (barre du système en Liquid Glass, mode
livre). Sur l'iPad, le paysage ouvre désormais le livre : lecteur, thèmes, Mermaid et carte se
prennent **en portrait** (page pleine, barre visible), conversion, diaporama et discussion **en
paysage** (Patrick). Par langue : `scripts/screenshots.sh <l> ipad` (portrait — règle la langue et
redémarre), rotation à la main, puis `IPAD_PAYSAGE=1 scripts/screenshots.sh <l> ipad` ; chaque
passe ne remplace que ses scènes. Sur le Mac, l'app se met en clair d'elle-même (`OKIA_CLAIR`,
Debug), sans toucher au réglage de la machine. **Le résumé et la discussion du Mac sont générés en
direct** : relire chaque réponse, et refaire une scène seule avec `SOLO=<scène>` si le modèle se
trompe — il l'a fait en français, en espagnol et en italien (discussion) et en anglais (résumé).
Le résumé espagnol garde, en tête, « alcanza niveles récord », qu'aucun essai n'a évité ; Patrick
a choisi de le garder (le reste du résumé est fidèle).

**L'iPad en paysage, langue par langue** (fait le 09/10/2026 pour les cinq) : régler la langue
(`simctl spawn <iPad> defaults write -g AppleLanguages -array <l>` et `AppleLocale`), redémarrer le
simulateur, le tourner — bouton ↻ du panneau « Simulateur iOS » de l'app Claude, ou Device Hub —,
puis `IPAD_PAYSAGE=1 scripts/screenshots.sh <l> ipad`. Le redémarrage remet l'iPad en portrait ;
redémarrer SpringBoard seul n'y change rien : l'orientation ne lui parvient plus, l'écran reste
droit dans un cadre couché. En paysage, le script refuse donc de changer la langue lui-même.
`scripts/legender.py` reconnaît une capture couchée et lui donne une légende sur une ligne.

**La conversion est rejouée, pas inventée.** Le simulateur ne génère pas : la présentation de
chaque langue a été écrite par le vrai modèle, sur le Mac, avec le banc
(`build/conversion-bench store/scenes/<l>/2-conversion.md 10 …`), et sert aussi la scène du
diaporama (`3-diaporama.md`). L'app la rejoue diapositive après diapositive
(`OKIA_CONVERSION_REJEU`, figée à 7 sur 10 par `OKIA_CONVERSION_ARRET`) : le contenu est celui du
modèle, seul le rythme est simulé. Le rapport source est une commune fictive, aux photos libres
(picsum.photos) — pas de photo de presse ni de marque tierce sur une capture App Store.

## Jeu précédent (4 septembre 2026)

`scripts/screenshots.sh <langue> [iphone|ipad|mac]` régénère tout, sans un clic. **Cinq langues**
sont tenues à jour depuis le 19/09/2026 (1.2.1) : `fr`, `en`, `de`, `es`, `it` ; les scènes vivent dans
`store/scenes/<langue>/`. Simulateurs : iPhone 17 Pro Max et iPad Pro 13" (M5) **sous iOS 26.5**, comme le
jeu fr/en — recréés le 19/09 après l'arrivée d'iOS 27 (le script prend le premier du nom).

⚠️ Passage Mac : macOS protège le conteneur de l'app (« données d'autres apps »). Un terminal sans
cette autorisation ne peut plus y écrire le cadre de fenêtre ni la taille de texte ; le script le dit
(« conteneur protégé ») et continue, la taille passant par `OKIA_SHOT_SIZE`. Vérifier alors la taille
du texte sur les captures.

| Dossier | Taille | Scènes |
|---|---|---|
| `screenshots/iphone-6.9/` | **1320×2868** | lecteur · Mermaid · carte · diaporama · discussion IA |
| `screenshots/ipad-13/`    | **2064×2752** | lecteur · Mermaid · carte · diaporama · discussion IA |
| `screenshots/mac/`        | **2560×1600** | les mêmes, plus le résumé IA et une question posée |

Une seule scène reste réservée au Mac : le **résumé**. Le simulateur annonce Apple
Intelligence disponible — il emprunte le modèle du Mac hôte — mais la génération y échoue
(`GenerationError -1`). La **discussion** s'y capture quand même, à son premier écran :
les questions proposées sortent du document, aucune génération n'est nécessaire.

Le jeu de juillet, livré avec 1.1.0, a été supprimé du dépôt une fois 1.1.1 en vente sur les
deux plateformes : ses fonds de carte CARTO n'avaient plus lieu d'être, et il ne servait plus
qu'à risquer un téléversement par mégarde. Il portait trois scènes que le script ne produit
pas — **accueil**, **mode sombre**, **callouts**. Pour les reprendre, elles sont entières
dans l'historique : `git show 05e17dc --stat`.

- **Headless** : iPhone/iPad via `simctl` (framebuffer natif), Mac Catalyst via
  `screencapture` de la fenêtre, recadrée au format 16:10 puis ramenée à 2560×1600.
- ⚠️ **Un point ne vaut pas partout deux pixels.** Sur un écran en résolution ajustée il en
  vaut 1,54 : viser « 1440 × 900 points = 2880 × 1800 pixels » donnait une fenêtre de
  2094 × 1326 que `sips` complétait en crème — la moitié de l'image était du fond. Le script
  déduit maintenant la plus grande fenêtre 16:10 qui tient sous la barre des menus, la passe
  à l'app par `OKIA_SHOT_SIZE=<largeur>x<hauteur>` (en points, 1657x1036 sur cet écran), et descend vers une taille
  acceptée par Apple plutôt que d'agrandir — un agrandissement rendrait la capture floue.
- Le script **rend la machine dans l'état où il l'a trouvée** : taille de texte et cadre de
  fenêtre sont relus avant, réécrits après.

### Hooks de capture (`#if DEBUG`, absents du build de production)

| Variable | Effet |
|---|---|
| `OKIA_RENDER_CONTENT` / `OKIA_RENDER_NAME` | rend ce Markdown directement dans le lecteur |
| `OKIA_UI_LANG` | fixe la langue de l'interface (`fr`, `en`, `de`, `es`, `it`) |
| `OKIA_SHOT_SIZE` | taille de la fenêtre Mac, en points : `1657x1036` ici |
| `OKIA_OPEN_SLIDES` | ouvre le diaporama au lancement |
| `OKIA_AI=summary\|chat` | ouvre la feuille de résumé ou de discussion |
| `OKIA_AI_QUESTION` | pose cette question dans la discussion |
| `OKIA_FAKE_AI` | **doublure** : force la disponibilité et sert une réponse pré-écrite |
| `OKIA_AI=convert` | ouvre la conversion en présentation (à côté du document sur grand écran) |
| `OKIA_AI_DELAY` | retarde l'ouverture de `OKIA_AI` (secondes) |
| `OKIA_CONVERSION_REJEU` / `OKIA_CONVERSION_ARRET` | rejoue une présentation écrite par le modèle ; la fige après n diapositives |
| `OKIA_THEME` / `OKIA_APPARENCE` | fixe le thème de lecture ; ouvre le panneau « Aa » |
| `OKIA_ORIENTATION` | `portrait` ou `paysage` (l'iPhone obéit, l'iPad non) |

`scripts/deploy-testflight.sh` refuse de livrer un binaire où l'une de ces chaînes apparaît.

⚠️ La langue **doit** passer par `OKIA_UI_LANG` : une app sandboxée ne voit pas les
préférences écrites de l'extérieur par `defaults write`, et les captures sortaient en
français quelle que soit la langue demandée.

⚠️ `OKIA_FAKE_AI` produit du **contenu fabriqué** : utile pour vérifier une mise en page,
jamais à téléverser. Les captures d'IA du jeu courant viennent du vrai modèle sur ce Mac.

---

## Références de tailles

App **universelle** → captures requises pour **iPhone**, **iPad** et **Mac**. Format **PNG ou JPEG**,
sans transparence, sans coins arrondis ajoutés (capture brute). ⚠️ Vérifie les tailles exactes
demandées le jour J dans App Store Connect (Apple les ajuste).

## Tailles requises (références actuelles)

| Plateforme | Taille (px, portrait sauf Mac) | Obligatoire |
|---|---|---|
| **iPhone 6.9"** (16 Pro Max…) | **1320 × 2868** (ou 1290 × 2796) | ✅ oui |
| iPhone 6.5" (anciens) | 1242 × 2688 | optionnel (repli) |
| **iPad 13"** (M4…) | **2064 × 2752** (ou 2048 × 2732) | ✅ oui (app iPad) |
| **Mac** | **2880 × 1800** (ou 2560×1600 / 1440×900 / 1280×800) | ✅ oui (Mac App Store) |

- 1 à 10 captures par plateforme. Vise **5–6** qui racontent les fonctionnalités.
- Tu peux capturer sur **simulateur** (iPhone/iPad) et sur **Mac Catalyst** directement.

## Ajouter ou changer une scène

Une scène est un fichier Markdown dans `store/scenes/<langue>/<n>-<nom>.md` ; la capture
prend le même nom. Le premier titre `#` devient le nom de document affiché dans la barre.
Une scène qui a besoin d'un écran particulier se déclare dans `harnais_de()`, en tête de
`scripts/screenshots.sh` — c'est le seul endroit à toucher.

Deux pièges rencontrés, à ne pas réintroduire :

- le WebView du simulateur rend en « ? » les caractères absents de sa police : les **emoji
  de callout** (les scènes iOS n'en contiennent pas) et, jusqu'ici, les **commandes du
  diaporama** — ✕ ⚙ ▦ sont devenus des SVG inline, qui se dessinent partout pareil ;
- une capture prise trop tôt attrape une carte vide ou un diagramme non rendu — le script
  attend la fenêtre, puis laisse le contenu se dessiner (30 s pour une réponse du modèle).

## Optionnel mais recommandé

- **Texte promotionnel sur les captures** (overlay) : 1 phrase courte par image (« Cartes OpenFreeMap »,
  « Résumé par Apple Intelligence »…). Sinon, captures brutes acceptées.
- **App Preview** (vidéo 15–30 s) : facultatif ; un court écran du zoom diagramme + carte plein écran
  rend très bien.
