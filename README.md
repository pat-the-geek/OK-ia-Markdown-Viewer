# OK-ia Markdown Viewer (iOS)

> Ce que les algorithmes ignorent encore. — [ok-ia.ch](https://ok-ia.ch)

Application iOS native (SwiftUI) qui ouvre des fichiers **Markdown contenant des diagrammes
Mermaid** et les affiche **exactement selon le principe du viewer de ok-ia.ch** : même charte,
même pipeline (frontmatter, callouts Obsidian, wiki-links, coloration NER), même thème Mermaid
normalisé. Les documents peuvent aussi être **présentés en diaporama plein écran** (mode Keynote/
PowerPoint). Tout fonctionne **100 % hors-ligne** — `marked`, `mermaid` et `leaflet` sont embarqués
dans l'app.

Distribution : **App Store** (la 1.0.0 est publiée) ; les préversions passent par **TestFlight**
(`scripts/deploy-testflight.sh`).

---

## Fonctionnalités

- **Ouverture d'un `.md` de 3 façons** : depuis une autre app / un navigateur (« Ouvrir dans… »),
  depuis Fichiers.app (« Partager → Envoyer vers… »), et via un bouton **Ouvrir un fichier** intégré.
- **Rendu fidèle ok-ia.ch** : charte noir/gris/blanc/orange, titre Nunito 900, barre de méta
  (source · date fr-CH · temps de lecture · « Lire l'article ↗ »).
- **Pipeline Markdown** (ordre identique à ok-ia.ch) : frontmatter YAML → blocs Mermaid → callouts
  Obsidian → wiki-links → coloration NER → `marked.parse` → normalisation/recoloration du thème
  Mermaid.
- **Les images ne bloquent jamais l'affichage** : elles portent `loading="lazy"` et se chargent
  quand on scrolle jusqu'à elles ; une image morte se retire elle-même (avec sa légende) sur son
  événement `error`. Le pipeline sondait auparavant **chaque** image distante avant de peindre le
  moindre pixel, en la téléchargeant entièrement — mesuré sur un briefing de 858 articles et
  815 images : **2 427 ms → 336 ms**, et l'écran restait blanc bien plus longtemps sur réseau réel.
- **Document volumineux** : au-delà de 2 M de caractères, un message « rendu en cours » est peint
  avant le parsing, qui monopolise ensuite le thread. La cession se fait par `setTimeout`, jamais
  par `requestAnimationFrame` — celui-ci ne se déclenche pas quand la vue est masquée, et le
  document ne se rendrait alors jamais.
- **Zoom diagramme plein écran** : tap → overlay ; pincer (0.5×–6×), glisser, double-tap
  (ajuster ↔ zoom), bouton « ajuster à l'écran », fermer ✕ + swipe-down. SVG **vectoriel**, net à fort zoom.
- **Image en plein écran** : un tap sur une image du document l'ouvre en plein écran — même
  visionneuse zoomable que les diagrammes (pincer, glisser, double-tap, swipe-down pour fermer).
- **Mode Diaporama (présentation)** : affiche le document en plein écran, une diapositive par bloc
  séparé par `---`, façon Keynote/PowerPoint (mise à l'échelle adaptative, 5 transitions, navigateur
  de vignettes). Voir la section dédiée plus bas.
- **Cartes géographiques Leaflet** (à la façon du plugin Obsidian Leaflet) : bloc <code>```leaflet</code>
  avec `marker: lat, long, [[Lien]]`, fonds de carte OpenFreeMap clair/sombre + OpenStreetMap, popups,
  cadrage auto sur les points. Bouton **plein écran ⛶** pour panner/zoomer en portrait ou paysage.
  Leaflet et MapLibre sont **bundlés offline** (`Web/vendor/leaflet.{js,css}`, `images/`,
  `maplibre-gl.{js,css}`, `leaflet-maplibre-gl.js`) ; seules les tuiles nécessitent le réseau.
  Les fonds clair/sombre sont les styles vectoriels `positron` et `dark` d'OpenFreeMap — ni clé,
  ni quota, ni compte — dessinés par MapLibre dans un calque Leaflet. Sans connexion, la carte affiche **« Carte indisponible hors connexion »**
  et la **liste des marqueurs** plutôt qu'un rectangle gris muet — déclenché par `navigator.onLine`
  et, parce que celui-ci ne signale qu'un lien et non une joignabilité (portail captif, CDN mort),
  aussi par les erreurs de tuiles.
- **Apple Intelligence** : quand le modèle on-device est disponible (iOS 26 / macOS 26+), un
  menu ✦ apparaît dans la barre du lecteur, avec **deux entrées**. Gardé par `@available` +
  `#if canImport(FoundationModels)` et par `DocumentSummarizer.isAvailable` → le menu entier
  **disparaît** sur les appareils sans Apple Intelligence, plutôt que d'afficher des options
  qui échoueraient.
  - **Résumé du document** : le framework *Foundation Models* génère un résumé **structuré en
    Markdown** (chapitres, **gras**, listes), rendu avec la charte de l'app.
    Voir `DocumentSummarizer` dans `ReaderView.swift`.
  - **Discuter avec le document** : questions/réponses multi-tours **ancrées sur le document
    seul**. Les réponses suivent la même mise en forme (phrase de réponse en gras, chapitres
    `##`, puces), et toute la conversation est rendue par le **moteur Markdown de l'app** —
    un seul WebView pour le fil, les questions devenant des callouts `question`. Le prompt
    traite le document comme une **donnée, jamais une consigne**, et interdit de répondre
    hors document. La **langue de réponse est celle des Réglages**, pas celle du document :
    la règle est répétée après le document dans les instructions *et* à chaque tour, et
    changer de langue reconstruit la session. Le dépassement de fenêtre de contexte efface
    l'historique et rejoue la question plutôt que de bloquer la conversation.
    L'écran d'accueil propose **cinq amorces**, dont trois **tirées du document** (entités
    wiki-liées, sinon titres de niveau 2, hors sections structurelles) — calculées sur
    l'appareil, sans appel au modèle. Voir `DocumentChatView.swift`.
  - **Document trop long pour la fenêtre de contexte** (6 000 car. pour le chat, 8 000 pour le
    résumé) : le modèle ne reçoit pas un simple préfixe — sur un briefing de 858 articles, ce
    serait les quatre premiers. Il reçoit **le début du document plus un plan tiré des titres**,
    échantillonné à pas régulier pour couvrir tout le document (858 articles → 58 titres au chat,
    couvrant 99 % du texte). Le modèle est prévenu de ce qu'il lit, et le lecteur voit la mention
    « seul son début a été analysé ». Voir `DocumentSummarizer.condensed(from:limit:)`.
- **Siri / Spotlight / Raccourcis (App Intents)** : actions exposées au système — **Ouvrir un
  rapport** (paramètre = rapport du coffre), **Ouvrir le dernier rapport**, **Résumer un rapport**
  (réutilise Apple Intelligence). Phrases FR auto-enregistrées via `AppShortcutsProvider`. Le store
  est partagé avec les intents par `AppDependencyManager`. Dispo iOS 17 / macOS 14+ (le résumé
  nécessite Apple Intelligence). Voir les types `…Intent` dans `OKiaMarkdownViewerApp.swift`.
- **Portrait + paysage** : relayout fluide, colonne de lecture élargie en paysage.
- **Mode sombre iOS** : la page passe en sombre, les diagrammes restent sur un cadre clair pour
  préserver la palette OK-ia.
- **Interface en 5 langues** (français, anglais, allemand, espagnol, italien) : la langue de
  l'appareil si elle est prise en charge, anglais sinon ; choix manuel (Système / Français /
  English / Deutsch / Español / Italiano) dans **Réglages** sur l'écran d'accueil. Couvre les vues
  natives, les messages d'erreur, la couche web (`window.OKIA_LANG` : « Lire l'article », menus du
  diaporama) et la langue du résumé Apple Intelligence. Les App Intents (Siri/Raccourcis) sont
  traduits eux aussi, mais suivent la langue **système** — c'est le système qui les résout, hors
  de portée du réglage in-app. Les chaînes vivent dans `Localizable.xcstrings` (langue source : **français**, la clé *est* le
  texte français) ; `tr("clé")` les résout — voir `Models/Localization.swift`. Comme le choix des
  Réglages doit primer sur la langue de l'appareil, `tr` lit le bundle `.lproj` de la langue
  courante au lieu de `Bundle.main`. Le prompt de résumé Apple Intelligence est écrit nativement
  dans chaque langue (`ReaderView.instructions`), pas traduit mot à mot.
- **Fichiers récents** : les derniers `.md` ouverts sont mémorisés (bookmarks security-scoped) et
  proposés sur l'écran d'accueil.
- **Sommaire (TOC)** : liste des titres du document avec saut direct à une section.
- **Recherche dans le document** : surlignage des occurrences + navigation précédent/suivant.
- **Partage / export** : export du rendu en **PDF** ou partage du fichier `.md` via la share sheet iOS.
- **Export Office (Word / PowerPoint)** : le **Rapport** s'exporte en **`.docx`** (titres, gras/italique,
  citations, listes, **tableaux éditables**, images + diagrammes) ; le **Diaporama** s'exporte en
  **`.pptx` mixte** (texte éditable + **tableaux éditables** + images/diagrammes rasterisés). Générateur
  OOXML **maison, sans dépendance** ; `.docx` ouvre Word **et** Pages, `.pptx` ouvre PowerPoint **et**
  Keynote. Voir la section dédiée.

---

## Mode Diaporama (présentation)

Le bouton **▶︎ Diaporama** (barre du lecteur, visible dès qu'un document contient **≥ 2 diapositives**)
affiche le document en **plein écran**, façon Keynote/PowerPoint.

- **Découpage** : une diapositive par bloc séparé par une ligne `---` (le frontmatter YAML et les
  lignes `---` à l'intérieur des blocs de code <code>```</code> sont ignorés).
- **Mise à l'échelle adaptative** : chaque diapo est composée dans une **toile au ratio de l'écran**,
  puis mise à l'échelle pour **occuper tout l'espace** — sans bandes vides sur iPhone (large), iPad
  (4:3) ou Mac (16:10). Images, diagrammes Mermaid et cartes sont affichés **le plus grand possible** ;
  une image seule est agrandie pour remplir la diapo.
- **Thèmes** : **Clair** (défaut), **Sombre**, **Console** (vert monospace sur noir), **Sépia**
  (papier), **Océan** (bleu nuit). Choisis via le menu **⚙** ; choix mémorisé (`localStorage`).
- **Transitions** (les 5 classiques de Keynote) : **Fondu**, **Poussée**, **Entrée**, **Échelle**,
  **Retournement 3D**. Aussi dans le menu **⚙** (haut-gauche) ; le choix est mémorisé (`localStorage`).
- **Navigateur de diapositives** : le bouton **▦** ouvre une **grille de vignettes** (mini-rendu du
  contenu + numéro + titre) ; cliquer une vignette saute directement à la diapo, la diapo courante est
  surlignée.
- **Navigation** : flèches **←/→** (clavier matériel via `UIKeyCommand`), **balayage** tactile,
  **flèches** semi-transparentes à l'écran, bouton **fin ✕**. **Échap** ferme d'abord la grille / le
  menu, puis quitte le diaporama (retour au lecteur Markdown habituel).
- **Repère de progression** : fine ligne orange (**2 mm**) en bas de l'écran + compteur « n / total ».
- **Cartes** : affichées en **plein cadre** sous le titre, sans recouvrir les contrôles du haut ; les
  diagrammes et images restent **zoomables** par tap pendant le diaporama.
- **Plein écran** : barre d'état masquée ; sur iPhone, passage automatique en **paysage**.

Implémentation : `Web/presentation.{html,js,css}` (moteur autonome qui réutilise le pipeline de rendu
via `window.OKIA.renderFragment`) + `PresentationView` / `PresentationWebView` / `KeyCapturingWebView`
dans `ReaderView.swift`.

> 📝 **Rédiger une présentation** : voir le [guide de rédaction](docs/GUIDE-PRESENTATION.md) (format
> Markdown attendu, découpage des diapos, conseils images inline, modèles, commandes). Il sert aussi
> d'instructions à coller dans une config d'assistant pour générer des présentations exploitables.

---

## Export Word (.docx) & PowerPoint (.pptx)

Deux exports « bureautique », via un **générateur OOXML maison sans dépendance**
([`Models/OOXMLExport.swift`](OKiaMarkdownViewer/Models/OOXMLExport.swift) — écriture ZIP + builders
DOCX/PPTX, Foundation pur donc validable hors-app).

- **Rapport → Word (`.docx`)** : menu **Partager → « Exporter en Word (.docx) »**. Produit un
  document éditable : titres, paragraphes, **gras/italique/code**, citations, listes à puces/numérotées,
  **tableaux éditables** bordurés, images + diagrammes.
- **Diaporama → PowerPoint (`.pptx`, mixte)** : menu **⚙ → Export → « PowerPoint (.pptx) »**. Une
  diapo par bloc, en **texte éditable** (titre + puces) + **tableaux éditables** (`a:tbl`) + **images**
  (diagrammes Mermaid rasterisés, photos intégrées) positionnées.

**Pipeline** : le JS `window.OKIA.exportModel(container)` parcourt le DOM rendu → blocs ordonnés et
**rasterise les diagrammes Mermaid** en PNG ; côté Swift, `OOXMLExportBridge` télécharge les images
distantes (natif, sans souci CORS), les dimensionne, puis appelle `DocxBuilder` / `PptxBuilder` ; le
fichier part dans la share sheet.

> **Couverture des 4 cibles** : `.docx` s'ouvre dans **Word et Pages** ; `.pptx` s'ouvre dans
> **PowerPoint et Keynote** (import OOXML d'Apple). Les formats Apple natifs `.key`/`.pages` (fermés)
> ne sont pas générés directement. Les **cartes** sont exportées en **liste de marqueurs** (texte) ;
> leur rendu image natif reste une amélioration possible. Validé hors-app : `.docx` via `textutil`,
> `.pptx` via QuickLook (moteur Office/iWork de macOS).

---

## Prérequis

- **Xcode 16+** (développé/testé avec Xcode 26.5).
- **iOS 17.0+** (cible de déploiement).
- **XcodeGen** — le `.xcodeproj` est généré à partir de [`project.yml`](project.yml) (non commité).

```bash
brew install xcodegen
```

## Build & exécution

```bash
# 1. Générer le projet Xcode depuis project.yml
xcodegen generate

# 2. Ouvrir dans Xcode
open OKiaMarkdownViewer.xcodeproj
```

Dans Xcode : sélectionnez un simulateur ou un appareil, puis **Run** (⌘R).
Au premier lancement, l'écran d'accueil propose **Ouvrir un fichier** ou **Voir un exemple**
(le fichier [`Samples/Demo.md`](OKiaMarkdownViewer/Samples/Demo.md) couvre flowchart, séquence,
gantt, pie, mindmap, callouts, wiki-links et NER).

### Vérification ligne de commande

```bash
xcodebuild -project OKiaMarkdownViewer.xcodeproj -scheme OKiaMarkdownViewer \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

> **Statut build** : `** BUILD SUCCEEDED **` sur simulateur iOS 26.5 (iPhone 17). L'app a été
> installée et lancée sur simulateur, et le rendu natif (WKWebView) a été vérifié de bout en bout :
> ouverture via `onOpenURL`, titre + barre de méta, légende NER, wiki-links, callouts, et les
> diagrammes Mermaid (flowchart, séquence, gantt, pie, mindmap) à la charte OK-ia.
>
> **Pré-requis plateforme** : il faut la **plateforme iOS installée** (SDK + runtime simulateur
> assorti). Si `xcodebuild` répond *« iOS XX.X is not installed »*, lancez :
> ```bash
> xcodebuild -downloadPlatform iOS
> ```
> (ou *Xcode → Settings → Components*). C'est requis pour tout build iOS, y compris l'archive TestFlight.

---

## Structure du projet

```
OKiaMarkdownViewer/
├── OKiaMarkdownViewerApp.swift     # @main, DocumentStore, .onOpenURL (cold + warm)
├── Info.plist                      # Document Types + UTI + orientations + export compliance
├── Assets.xcassets/                # AppIcon (1024, sans alpha) + AccentColor (#E8972E)
├── Models/
│   ├── MarkdownDocument.swift      # chargement UTF-8 → Latin-1, security-scoped, sans UIKit
│   └── OOXMLExport.swift           # ZIP + builders DOCX/PPTX + bridge (export Word/PowerPoint)
├── Views/
│   ├── RootView.swift              # routage + .fileImporter + alertes
│   ├── EmptyStateView.swift        # accueil (ouvrir / exemple)
│   ├── ReaderView.swift            # barre titre + overlay zoom + Diaporama (PresentationView)
│   ├── MarkdownWebView.swift       # WKWebView + message handlers + injection JSON sûre
│   └── DiagramZoomView.swift       # overlay pinch/pan/double-tap (SVG) + ImageZoomView
├── Web/                            # (référence de dossier — copiée verbatim dans le bundle)
│   ├── renderer.html               # gabarit lecteur ; charge vendor + thème + render.js
│   ├── presentation.html           # gabarit diaporama ; vendor + render.js + presentation.js
│   ├── render.js                   # pipeline complet OK-ia (+ renderFragment, zoom image)
│   ├── presentation.js             # moteur diaporama (découpe ---, fit, transitions, navigateur)
│   ├── presentation.css            # styles diaporama (toile, progression, vignettes)
│   ├── mermaid-okia-theme.js       # thème + normalizeMermaidPalette + applyMermaidTextColors
│   ├── style.css                   # charte, callouts, wiki-links, NER, mermaid, dark mode
│   ├── fonts/Nunito-{Black,Regular}.woff2
│   └── vendor/marked.min.js, mermaid.min.js, leaflet.{js,css}   # bundlés offline (aucun CDN)
└── Samples/Demo.md                 # document de démonstration
```

## Bundling des assets (offline, aucun CDN)

Les bibliothèques sont téléchargées une fois puis **commitées** dans `Web/vendor/` ; l'app ne fait
aucun appel réseau pour le rendu.

| Lib | Version | Fichier | Source |
|-----|---------|---------|--------|
| marked | **18.0.5** | `Web/vendor/marked.min.js` (UMD `lib/marked.umd.js`) | jsDelivr |
| mermaid | **11.15.0** | `Web/vendor/mermaid.min.js` (UMD `dist/mermaid.min.js`, expose `globalThis.mermaid`) | jsDelivr |
| leaflet | **1.9.4** | `Web/vendor/leaflet.{js,css}` + `Web/vendor/images/` (marqueurs) | unpkg |
| Nunito | 5.x | `Web/fonts/Nunito-{Black,Regular}.woff2` | Fontsource |

> Le build **UMD** de Mermaid est requis : le build ESM (`.mjs`) ne se charge pas sous `file://`
> dans une `WKWebView` (CORS de module). Pour mettre à jour :
> ```bash
> curl -fsSL https://cdn.jsdelivr.net/npm/marked@<v>/lib/marked.umd.js  -o OKiaMarkdownViewer/Web/vendor/marked.min.js
> curl -fsSL https://cdn.jsdelivr.net/npm/mermaid@<v>/dist/mermaid.min.js -o OKiaMarkdownViewer/Web/vendor/mermaid.min.js
> ```

## Ouverture de fichiers — détails techniques

- `Info.plist` déclare `CFBundleDocumentTypes` (`net.daringfireball.markdown` + `public.plain-text`,
  `LSHandlerRank = Alternate`) et `UTImportedTypeDeclarations` pour `md`/`markdown`/`mdown`/`mkd`/`markdn`.
- `LSSupportsOpeningDocumentsInPlace` + `UIFileSharingEnabled` → visible dans Fichiers et le partage.
- `OKiaMarkdownViewerApp` gère `.onOpenURL` (lancement à froid **et** à chaud).
- Le bouton **« Ouvrir un fichier »** (et **⌘O** sur Mac) ouvre le sélecteur via **un seul**
  `.fileImporter` dans `RootView`, dont les types autorisés basculent fichier ↔ dossier-coffre
  selon un drapeau `importFolder`. (SwiftUI ne supporte pas deux `.fileImporter` sur la même vue :
  empilés, le sélecteur ne s'affiche pas — d'où ce pilotage unique.)
- `MarkdownLoader` gère `startAccessingSecurityScopedResource`, une copie coordonnée en repli,
  et le décodage UTF-8 → ISO Latin-1.
- Le Markdown est passé à la WKWebView via `evaluateJavaScript` avec une **chaîne JSON encodée**
  (jamais concaténée dans du HTML) → aucune injection possible.

### Ouvrir un fichier depuis un site web — schéma `mdviewer://`

L'app enregistre le schéma d'URL `mdviewer://` (`CFBundleURLTypes` dans `Info.plist`, géré par
`DocumentStore.handleScheme`). Un site web peut donc ouvrir un rapport **directement dans l'app**
(si elle est installée) :

- **Fichier `.md` hébergé** — l'app le télécharge (https) et l'affiche :
  ```
  mdviewer://open?url=<URL https du .md, encodée>
  ```
  ```html
  <a href="mdviewer://open?url=https%3A%2F%2Fok-ia.ch%2Frapports%2Fmon-rapport.md">
    Ouvrir dans md Viewer
  </a>
  ```
  ```js
  location.href = 'mdviewer://open?url=' + encodeURIComponent(urlDuMd);
  ```
- **Contenu inline** (petits documents ; une URL reste limitée à quelques Ko) :
  ```js
  location.href = 'mdviewer://render?name=' + encodeURIComponent('Rapport.md')
               + '&content=' + encodeURIComponent(markdown);
  ```

> Limite : un schéma personnalisé ne fonctionne **que si l'app est installée** (pas de repli web
> automatique). Pour des liens `https` normaux qui retombent sur le site quand l'app est absente,
> il faudrait des **Universal Links** (entitlement *Associated Domains* + fichier
> `apple-app-site-association` hébergé sur le domaine) — non implémenté.

---

## Livraison TestFlight

### En une commande

```bash
scripts/deploy-testflight.sh --bump --both
```

Enchaîne incrément du build → `xcodegen` → archive Release → export App Store → **contrôles** →
envoi via `xcrun altool`, pour chaque plateforme demandée. Sans `--bump`, réutilise le numéro
courant ; avec `--no-upload`, s'arrête après les contrôles et laisse l'artefact.

| Option | Livre |
|---|---|
| *(aucune)* | iOS seul — iPhone et iPad partagent le même binaire universel |
| `--mac` | Mac Catalyst seul (`.pkg`) |
| `--both` | iOS puis Mac, à partir d'un **seul** numéro de build |

`--both` n'est pas un confort. Oublier le Mac ne fait aucun bruit : l'app a livré trois semaines
de builds iOS pendant que le Mac restait sur un plus ancien, filigrane sur les cartes compris.
Un seul drapeau couvre désormais les deux.

Les identifiants viennent de `scripts/deploy.env` (non commité — voir `deploy.env.example`) :
`ASC_KEY_ID` et `ASC_ISSUER_ID`. La clé privée reste dans
`~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`.

Quatre contrôles bloquent l'envoi, chacun pour une panne silencieuse au build et coûteuse plus tard :
signature **Apple Distribution** (une IPA signée en développement est refusée par App Store Connect),
**absence du harnais de debug** dans les binaires, **cinq localisations** présentes, et **version
conforme** à `project.yml`. Le test du harnais est précédé d'un **canari** (`OKIA_LANG`, présent dans
tout build) : si le canari manque, c'est que `strings` ne lit pas les littéraux du binaire et le
contrôle serait vide — le script s'arrête plutôt que d'afficher un feu vert sans valeur.

> L'envoi se fait en distribution **App Store standard**. C'est ce qui distingue ce script d'un
> envoi depuis Xcode Organizer en « TestFlight Internal Only », qui produit des builds
> **inéligibles à l'App Store** — le piège qui a bloqué les builds 9 à 18.

### Métadonnées de la fiche

`altool` envoie le binaire et s'arrête là : il ne sait rien dire de la fiche App Store.
`scripts/asc.py` couvre l'autre moitié — créer une version, écrire les notes de version,
rattacher un build :

```bash
scripts/asc.py GET  "/v1/apps/6781039895/appStoreVersions?filter[platform]=IOS"
scripts/asc.py POST /v1/appStoreVersions '{"data": {…}}'
```

Mêmes identifiants que le script de livraison (`scripts/deploy.env`), même clé privée dans
`~/.appstoreconnect/private_keys/` — lue seulement pour signer le jeton, jamais affichée.
Un rappel qui a coûté un envoi : **une version marketing déjà approuvée ferme son train**.
Réutiliser sa `MARKETING_VERSION` fait rejeter le binaire (erreurs 90062 et 90186) ; il faut
monter la version marketing, pas seulement le numéro de build.

### À la main

1. **Signature** : la **Team** payante (`72NVM63N83`) et le **Bundle Identifier**
   `ch.ok-ia.markdownviewer` sont déjà configurés (signature **automatique**). Vérifiez dans Xcode →
   cible *OKiaMarkdownViewer* → **Signing & Capabilities** que **Automatically manage signing** est
   coché, la Team sélectionnée, et qu'aucune erreur de provisioning ne s'affiche (Xcode crée au besoin
   le certificat *Apple Distribution* et le profil App Store à la première archive).
2. **Versions** : `MARKETING_VERSION` = 1.1.1, `CURRENT_PROJECT_VERSION` incrémenté à chaque archive
   (build **28** au moment de la rédaction ; 1.1.0 est la version publiée sur l'App Store). Un train
   déjà approuvé est fermé : réutiliser sa `MARKETING_VERSION` fait rejeter l'envoi (90062/90186), il
   faut monter la version marketing et pas seulement le build.
   App Store Connect refuse aussi un build dont le numéro existe
   déjà : si l'upload signale « build already exists », **incrémentez `CURRENT_PROJECT_VERSION`** dans
   [`project.yml`](project.yml) (source de vérité ; le `.xcodeproj` est généré et non commité) — ou
   directement via *Xcode → General → Build*.
3. **Archive** : sélectionnez la destination **Any iOS Device (arm64)** →
   **Product → Archive**.
4. **Upload** : dans l'Organizer → **Distribute App → App Store Connect → Upload**.
   `ITSAppUsesNonExemptEncryption = NO` évite le questionnaire d'export.
5. **TestFlight** : dans App Store Connect → onglet **TestFlight** → activez le build →
   invitez les **testeurs internes** (jusqu'à 100, sans revue) ou créez un **groupe externe**
   (revue TestFlight légère requise).
6. **Aucune** soumission à la revue App Store, **aucun** déploiement store.

---

## macOS (Mac Catalyst) — livré ✅

L'app tourne aussi sur **macOS via Mac Catalyst** (même base de code) :

- `SUPPORTS_MACCATALYST: YES` dans `project.yml` (bundle id identique, `MACOSX_DEPLOYMENT_TARGET 14.0`).
- Exécution locale signée « Sign to Run Locally » (compte personnel) — aucune config supplémentaire.
- Menu **Fichier ▸ Ouvrir…** (**⌘O**), **glisser-déposer** d'un `.md` sur la fenêtre, **taille de fenêtre minimale** (480×600), fenêtre redimensionnable.
- Liens externes : ouverts dans le **navigateur par défaut** du Mac (SFSafariViewController étant indisponible sur Catalyst — voir le `#if targetEnvironment(macCatalyst)` dans `ReaderView` / `SafariView`).
- Zoom diagramme, recherche, sommaire, export PDF, fichiers récents : identiques à iOS.

### Builder / lancer sur Mac

```bash
xcodegen generate
xcodebuild -project OKiaMarkdownViewer.xcodeproj -scheme OKiaMarkdownViewer \
  -destination 'platform=macOS,variant=Mac Catalyst' build
# puis : open ~/Library/Developer/Xcode/DerivedData/OKiaMarkdownViewer-*/Build/Products/Debug-maccatalyst/OKiaMarkdownViewer.app
```
ou, dans Xcode, choisir la destination **« Mac (Mac Catalyst) »** puis **Run** (⌘R).

> Distribution macOS : possible via **TestFlight pour Mac** (mêmes étapes Archive → App Store Connect, une fois le compte payant actif) ou un export *Developer ID* notarisé pour diffusion directe.

---

## Critères d'acceptation — état

| # | Critère | État |
|---|---------|------|
| 1 | Ouverture `.md` depuis Safari/Files/autre app | ✅ (UTI + onOpenURL + fileImporter) |
| 2 | Rendu visuellement identique à ok-ia.ch | ✅ (validé en natif : 5 diagrammes, callouts, wiki, NER, palette) |
| 3 | Zoom diagramme (pinch/pan/double-tap, SVG net) | ✅ (DiagramZoomView, SVG vectoriel) |
| 4 | Rotation portrait↔paysage fluide | ✅ (CSS `@media orientation` + WKWebView) |
| 5 | Fonctionne hors-ligne (aucun CDN) | ✅ (marked/mermaid/fonts bundlés) |
| 6 | Archive/upload TestFlight sans erreur de signature | ✅ build OK ; signature à finaliser dans Xcode (Team à définir) |
| 7 | README (build, assets, TestFlight, macOS) | ✅ (ce document) |
| 8 | macOS (Mac Catalyst) | ✅ build + lancement OK ; menu ⌘O, drag&drop, fenêtre redimensionnable |
| 9 | Mode Diaporama (plein écran, transitions, navigateur de vignettes, image plein écran) | ✅ découpe `---`, toile adaptative, 5 transitions Keynote, grille de vignettes, clavier/balayage/Échap |
| 10 | Export Word (.docx) & PowerPoint (.pptx mixte, tableaux éditables) | ✅ OOXML maison ; validé `textutil`/QuickLook ; ouverture Word/Pages & PowerPoint/Keynote (test final sur appareil) |

---

## À faire

### Windows : faire du lecteur en ligne la réponse

**Décidé le 2026-09-03, reporté.** Pas d'application Windows native : on rend le lecteur web
capable de tenir ce rôle.

**Pourquoi ce choix.** Tout le rendu est déjà portable — `Web/render.js` et ses 3 500 lignes
(Markdown, Mermaid, callouts, wiki-links, entités, cartes, diaporama, modèle d'export) tournent
déjà sous Windows dans n'importe quel navigateur, sur `ok-ia.ch/rapport.html`. Ce qui ne se porte
pas, c'est le Swift : Apple Intelligence, Siri, Spotlight, les signets du coffre, et les 731 lignes
de `OOXMLExport.swift`. Or le résumé et le chat **sur l'appareil** sont la promesse qui distingue
md Viewer ; sans eux, il resterait un bon lecteur Markdown sur un terrain déjà occupé par Obsidian,
VS Code et Typora, gratuits. Le marché visé (PME et administrations romandes) est bien sous
Windows, mais son besoin est d'**ouvrir un rapport reçu** — un lien, pas une installation.

**Ce qu'il y a à faire**, dans le dépôt du site (`pat-the-geek/OK-ia`, `public/rapport.html`) :

1. ouvrir un `.md` local depuis le disque — API d'accès aux fichiers, disponible dans Edge et
   Chrome ; garder `?doc=` et `?f=` pour les documents du site ;
2. rendre la page installable comme application (manifeste + service worker), pour un lancement
   depuis le menu Démarrer et une lecture hors connexion ;
3. impression PDF par le navigateur, avec une feuille de style d'impression — les cartes et les
   diagrammes doivent y figurer entiers, comme dans l'app.

Quelques jours de travail. Ni certificat, ni boutique, ni chaîne de mise à jour à construire.

**Escalade, si l'usage montre une vraie demande** : Tauri autour du même `render.js` — bon marché
précisément parce que le moteur est partagé. Il faudra alors rebâtir l'export Word/PowerPoint en
JS, trancher la question de l'IA (modèle local à installer, ou API distante — et la promesse « rien
ne sort de l'appareil » tombe), et affronter la signature de code Windows.

### 1.2 — Traduction automatique des documents

**Décidé le 2026-09-06.** Une option `auto-traduction` (vrai/faux) dans les Réglages, à côté du
choix de langue. Activée, un document ouvert dans une autre langue que celle de l'app est traduit
avant d'être rendu ; désactivée — la valeur par défaut — rien ne change.

**Pourquoi.** L'app parle déjà cinq langues et le résumé comme la discussion répondent dans celle
que le lecteur a choisie, quelle que soit la langue du rapport. Le document, lui, reste dans la
sienne : un lecteur germanophone à qui l'on transmet un rapport français lit l'interface en
allemand et le contenu en français. La traduction ferme cet écart.

**Ce qu'il faut trancher avant d'écrire une ligne :**

1. **Le moteur.** Le framework `Translation` d'Apple est fait pour cela — modèles téléchargeables,
   hors ligne, sans coût par appel — là où `FoundationModels`, déjà en place pour le résumé,
   traduirait au prix d'une génération complète et d'une dérive possible du texte. À vérifier :
   la couverture des cinq langues de l'app et la disponibilité sur Mac Catalyst.
2. **Ce qui ne doit pas être traduit.** C'est le vrai travail, et il n'a rien de linguistique :
   blocs de code, syntaxe Mermaid (les libellés se traduisent, `flowchart TD` non), blocs
   `leaflet` (les coordonnées et les identifiants restent, les libellés de marqueurs suivent),
   cibles des wiki-liens `[[Entité]]` — les traduire casserait le coffre et la coloration
   d'entités — URL, et clés du frontmatter YAML dont seules les valeurs textuelles se traduisent.
   Il faut donc traduire l'**arbre** du document, pas sa chaîne de caractères.
3. **La longueur.** Le résumé travaille sur 8 000 caractères condensés ; un rapport entier en fait
   dix fois plus. Découpage par blocs, traduction paresseuse de ce qui est à l'écran, et cache par
   document — sans quoi l'ouverture d'un long rapport se paierait en secondes.
4. **Ce qui sort de l'app.** Un export PDF, Word ou PowerPoint d'un document traduit doit-il
   porter la traduction ou l'original ? Et le titre affiché dans le coffre et les Récents ?
5. **Le dire.** Une traduction automatique se signale, comme le résumé le fait déjà : une mention
   discrète, et le moyen de revenir à l'original en un geste.

**Ce qui ne change pas** : tout se passe sur l'appareil, rien ne sort. Une traduction par API
distante contredirait la promesse qui distingue l'app, et ne se justifierait pas ici.

#### Traduction par morceaux, et l'effet visuel qui va avec

**Demandé le 2026-09-06.** Traduire bloc par bloc, et montrer le document se traduire au fur et
à mesure plutôt que d'afficher un sablier.

**Le découpage n'est pas un ornement, c'est la bonne architecture.** Un rapport fait dix fois la
taille de ce que le résumé avale ; le traduire d'un bloc serait long et sans retour visible. Le
découper en nœuds de texte — un paragraphe, une puce, une cellule, un titre — permet de traduire
d'abord ce qui est à l'écran, de garder l'original à côté, et d'annuler sans rien recalculer.

**Ce qui est réellement progressif, et ce qui ne l'est pas.** Le framework `Translation` rend une
chaîne entière par requête ; il ne diffuse pas mot à mot. Deux niveaux d'effet, donc, et ils ne se
valent pas :

- **par bloc** — chaque paragraphe bascule quand sa traduction arrive, en fondu court. C'est
  honnête : l'animation *est* l'avancement. Le document se traduit visiblement du haut vers le
  bas, et le lecteur voit où en est le travail ;
- **mot à mot dans un bloc** — révéler les mots traduits avec un décalage de quelques
  millisecondes. C'est une décoration : le texte est déjà là, on le cache pour faire joli. À ne
  faire, si on le fait, que sur le premier bloc visible, et brièvement.

Recommandation : le fondu par bloc, ordonné par position dans le document. L'effet mot à mot ne
s'ajoute qu'après, s'il manque quelque chose.

**Les trois pièges, dans l'ordre où ils feront mal :**

1. **Le texte saute.** Une traduction n'a pas la longueur de l'original — de l'ordre de +20 % vers
   l'allemand. Chaque bloc qui bascule change de hauteur et pousse la suite : le lecteur perd sa
   ligne. Il faut ancrer le défilement sur le premier bloc visible pendant la vague, ou réserver
   la hauteur le temps du remplacement.
2. **Le pont Swift ↔ JS.** La traduction se calcule côté Swift, l'affichage vit dans le WebView.
   Il faut donc numéroter les nœuds de texte au rendu et que Swift réponde « nœud 42 → ce texte ».
   Sans identifiant stable, rien de tout cela ne tient.
3. **Ce qui se rend après coup.** Mermaid et les cartes se dessinent en différé : leurs libellés
   doivent être traduits avant le rendu, sinon il faut les redessiner — et une carte qui se
   redessine, cela se voit.

**À vérifier avant de s'engager** : la diffusion des résultats par le framework (une réponse par
requête, ou une séquence asynchrone qui rend les résultats au fil de l'eau), sa disponibilité sur
Mac Catalyst, et le téléchargement du dictionnaire de langue à la première utilisation — c'est une
invite système, elle doit tomber au bon moment, pas au milieu d'une lecture.

##### La calque de transition : oui, mais par bloc

**Proposé le 2026-09-06.** Faire l'effet sur une copie du texte affichée par-dessus la page, et
n'écrire la traduction dans le document réel qu'à la fin.

L'idée est juste, et elle règle de vrais problèmes : le document réel n'est pas touché pendant
l'animation, donc pas de recalcul de mise en page à chaque mot, pas de sélection perdue, pas de
surlignage de recherche cassé, pas de diagramme redessiné. Un seul remplacement, à la fin.

**Mais pas à l'échelle de la page.** Une copie ne peut montrer qu'une chose : la mise en page de
l'original. Or la traduction n'a pas la même longueur — de l'ordre de +20 % vers l'allemand. Les
mots traduits animés dans la mise en page d'origine ne tiendraient pas dans leurs lignes, et le
calque se remettrait à couler tout seul : on aurait déplacé le problème, pas résolu. S'ajoutent le
coût de cloner un document de plusieurs dizaines de milliers de pixels — SVG Mermaid et toiles
Leaflet comprises — et un calque à faire suivre si le lecteur défile pendant l'effet.

**La bonne échelle est le bloc.** Pour chaque paragraphe dont la traduction arrive :

1. cloner le bloc et poser le clone exactement par-dessus, en position absolue ;
2. écrire la traduction dans le bloc réel, sous le clone — le lecteur ne voit rien, le clone le
   masque ;
3. animer la hauteur du bloc réel vers sa nouvelle hauteur, et faire disparaître le clone en
   fondu.

Le changement de longueur est alors absorbé par une transition de hauteur au lieu d'un saut, et
chaque bloc coûte un clone éphémère au lieu d'une copie de la page. Un `aria-hidden` sur le clone,
sans quoi un lecteur d'écran lirait tout en double.

Reste une question ouverte : pendant la vague, faut-il ancrer le défilement sur le premier bloc
visible ? Tant qu'on traduit ce qui est à l'écran d'abord, les hauteurs changent au-dessus de la
ligne de lecture — c'est précisément là que cela se remarque.

##### La vague : de haut en bas, mais à partir de l'écran

**Précisé le 2026-09-06.** Une passe descendante traduit le document, bloc après bloc.

C'est la bonne mise en scène, et pour une raison qui n'est pas décorative : une direction se lit.
Le lecteur comprend en une seconde ce qui se passe, où en est le travail et qu'il aura une fin.
Un ordre optimisé — les blocs les plus courts d'abord, ou ceux dont la traduction revient le plus
vite — irait plus vite et ressemblerait à du désordre.

**Deux réglages à trancher, et le second est un piège :**

1. **D'où part la vague.** De haut en bas, oui, mais depuis le **premier bloc visible**, pas depuis
   le début du fichier. Un rapport rouvert à la page 7 ne doit pas faire attendre six pages qu'on
   ne regarde pas. Ce qui reste au-dessus se traduit ensuite, en silence et sans animation — le
   lecteur n'y est pas.
2. **La cadence.** Le modèle rendra souvent plus vite que l'œil ne suit : la vague deviendrait un
   éclair, et l'effet ne dirait plus rien. Un intervalle minimal entre blocs — quelques dizaines
   de millisecondes — la rend lisible. Mais il ne freine que l'**animation**, jamais la
   disponibilité du texte : un lecteur qui défile plus vite que la vague doit trouver ses
   paragraphes déjà traduits, pas en attente d'un décompte cosmétique.

##### Le marqueur d'avancement

**Demandé le 2026-09-06.** Un repère visuel disant où en est la traduction.

**Une barre fine en haut du lecteur**, du même trait que celle du diaporama
(`.present-progress-bar`, déjà à la charte), qui se remplit et disparaît à la fin. C'est le
repère qui ne ment pas : il reste visible où que soit le lecteur, alors qu'un trait posé à la
frontière de la vague ne se voit que si l'on regarde précisément cet endroit — et il ne se voit
plus du tout dès qu'on défile ailleurs.

**Le trait de frontière** — une lisière en dégradé entre le traduit et le reste — peut s'ajouter,
mais seulement quand la frontière est à l'écran, et à une condition : qu'il n'y en ait qu'une. Si
la vague part du premier bloc visible et remonte ensuite ce qui est au-dessus, il y a **deux
zones**, et un trait unique raconterait une histoire fausse.

**Mesurer en caractères, pas en blocs.** Un titre et un paragraphe de trente lignes comptent
pareil dans un décompte de blocs : la barre avancerait par à-coups, vite sur les titres et lente
sur les paragraphes, sans rapport avec le temps restant. Le poids en caractères donne une
progression régulière et honnête.

**Prévoir la fin qui n'arrive pas.** Une langue non prise en charge, un dictionnaire interrompu,
un bloc qui échoue : la barre ne doit pas rester bloquée à 98 % pour l'éternité. Il faut un état
terminal — « traduit, sauf trois paragraphes » — et le moyen de voir lesquels.
