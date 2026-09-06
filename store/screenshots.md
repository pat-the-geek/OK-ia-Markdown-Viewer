# Captures d'écran — App Store

## Jeu courant (4 septembre 2026)

`scripts/screenshots.sh <langue> [iphone|ipad|mac]` régénère tout, sans un clic. Deux langues
sont tenues à jour, `fr` et `en` ; les scènes vivent dans `store/scenes/<langue>/`.

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
