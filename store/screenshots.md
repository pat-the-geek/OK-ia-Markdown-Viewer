# Captures d'écran — App Store

## Jeu courant (4 septembre 2026)

`scripts/screenshots.sh <langue> [iphone|ipad|mac]` régénère tout, sans un clic. Deux langues
sont tenues à jour, `fr` et `en` ; les scènes vivent dans `store/scenes/<langue>/`.

| Dossier | Taille | Scènes |
|---|---|---|
| `screenshots/iphone-6.9/` | **1320×2868** | lecteur · Mermaid · carte |
| `screenshots/ipad-13/`    | **2064×2752** | lecteur · Mermaid · carte |
| `screenshots/mac/`        | **2880×1800** | lecteur · Mermaid · carte · diaporama · résumé IA · discussion IA |

Trois scènes sont réservées au Mac. Les deux d'IA parce que le simulateur n'a pas de modèle
Apple Intelligence — on n'y capturerait qu'un écran d'indisponibilité. Le diaporama parce
que ses glyphes de commande (⚙ ▦ ✕) y sortent en « ? », comme les emoji de callout ; sur
Mac et sur appareil réel ils sont nets.

⚠️ Les fichiers restés **à plat** dans `screenshots/<appareil>/` (sans sous-dossier de
langue) sont le jeu de juillet, livré avec 1.1.0 : fonds de carte CARTO, scènes « accueil »,
« mode sombre » et « callouts » que le script ne produit plus. À ne pas téléverser tels
quels — ils sont conservés le temps de décider si ces trois scènes reviennent.

- **Headless** : iPhone/iPad via `simctl` (framebuffer natif), Mac Catalyst via
  `screencapture` de la fenêtre puis normalisation `sips` (fond crème #FAFAF8).
- Le script **rend la machine dans l'état où il l'a trouvée** : taille de texte et cadre de
  fenêtre sont relus avant, réécrits après.

### Hooks de capture (`#if DEBUG`, absents du build de production)

| Variable | Effet |
|---|---|
| `OKIA_RENDER_CONTENT` / `OKIA_RENDER_NAME` | rend ce Markdown directement dans le lecteur |
| `OKIA_UI_LANG` | fixe la langue de l'interface (`fr`, `en`, `de`, `es`, `it`) |
| `OKIA_SHOT_SIZE` | taille de fenêtre Mac |
| `OKIA_PRESENT` | ouvre le diaporama au lancement |
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

- le WebView du simulateur rend en « ? » les **emoji de callout** et les **glyphes de
  commande du diaporama** (nets sur appareil réel et sur Mac) : les scènes iOS n'en
  contiennent pas, et `scene_reservee_au_mac()` écarte le diaporama ;
- une capture prise trop tôt attrape une carte vide ou un diagramme non rendu — le script
  attend la fenêtre, puis laisse le contenu se dessiner (30 s pour une réponse du modèle).

## Optionnel mais recommandé

- **Texte promotionnel sur les captures** (overlay) : 1 phrase courte par image (« Cartes OpenFreeMap »,
  « Résumé par Apple Intelligence »…). Sinon, captures brutes acceptées.
- **App Preview** (vidéo 15–30 s) : facultatif ; un court écran du zoom diagramme + carte plein écran
  rend très bien.
