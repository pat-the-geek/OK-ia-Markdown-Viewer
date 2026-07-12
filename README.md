# OK-ia Markdown Viewer (iOS)

> Ce que les algorithmes ignorent encore. — [ok-ia.ch](https://ok-ia.ch)

Application iOS native (SwiftUI) qui ouvre des fichiers **Markdown contenant des diagrammes
Mermaid** et les affiche **exactement selon le principe du viewer de ok-ia.ch** : même charte,
même pipeline (frontmatter, callouts Obsidian, wiki-links, coloration NER), même thème Mermaid
normalisé. Les documents peuvent aussi être **présentés en diaporama plein écran** (mode Keynote/
PowerPoint). Tout fonctionne **100 % hors-ligne** — `marked`, `mermaid` et `leaflet` sont embarqués
dans l'app.

Distribution : **TestFlight uniquement** (diffusion interne), pas d'App Store.

---

## Fonctionnalités

- **Ouverture d'un `.md` de 3 façons** : depuis une autre app / un navigateur (« Ouvrir dans… »),
  depuis Fichiers.app (« Partager → Envoyer vers… »), et via un bouton **Ouvrir un fichier** intégré.
- **Rendu fidèle ok-ia.ch** : charte noir/gris/blanc/orange, titre Nunito 900, barre de méta
  (source · date fr-CH · temps de lecture · « Lire l'article ↗ »).
- **Pipeline Markdown** (ordre identique à ok-ia.ch) : frontmatter YAML → blocs Mermaid → callouts
  Obsidian → wiki-links → nettoyage des images cassées (tolérant hors-ligne) → coloration NER →
  `marked.parse` → normalisation/recoloration du thème Mermaid.
- **Zoom diagramme plein écran** : tap → overlay ; pincer (0.5×–6×), glisser, double-tap
  (ajuster ↔ zoom), bouton « ajuster à l'écran », fermer ✕ + swipe-down. SVG **vectoriel**, net à fort zoom.
- **Image en plein écran** : un tap sur une image du document l'ouvre en plein écran — même
  visionneuse zoomable que les diagrammes (pincer, glisser, double-tap, swipe-down pour fermer).
- **Mode Diaporama (présentation)** : affiche le document en plein écran, une diapositive par bloc
  séparé par `---`, façon Keynote/PowerPoint (mise à l'échelle adaptative, 5 transitions, navigateur
  de vignettes). Voir la section dédiée plus bas.
- **Cartes géographiques Leaflet** (à la façon du plugin Obsidian Leaflet) : bloc <code>```leaflet</code>
  avec `marker: lat, long, [[Lien]]`, fonds de carte CARTO clair/sombre + OpenStreetMap, popups,
  cadrage auto sur les points. Bouton **plein écran ⛶** pour panner/zoomer en portrait ou paysage.
  Leaflet est **bundlé offline** (`Web/vendor/leaflet.{js,css}` + `images/`) ; seules les tuiles
  nécessitent le réseau.
- **Résumé du document par Apple Intelligence** : quand Apple Intelligence est disponible
  (iOS 26 / macOS 26+), un bouton ✦ apparaît dans la barre du lecteur. Le **modèle on-device**
  (framework *Foundation Models*) génère un résumé **structuré en Markdown** (chapitres, **gras**,
  listes), rendu avec la charte de l'app. Gardé par `@available` + `#if canImport(FoundationModels)`
  → invisible sur les appareils sans Apple Intelligence. Voir `DocumentSummarizer` dans `ReaderView.swift`.
- **Siri / Spotlight / Raccourcis (App Intents)** : actions exposées au système — **Ouvrir un
  rapport** (paramètre = rapport du coffre), **Ouvrir le dernier rapport**, **Résumer un rapport**
  (réutilise Apple Intelligence). Phrases FR auto-enregistrées via `AppShortcutsProvider`. Le store
  est partagé avec les intents par `AppDependencyManager`. Dispo iOS 17 / macOS 14+ (le résumé
  nécessite Apple Intelligence). Voir les types `…Intent` dans `OKiaMarkdownViewerApp.swift`.
- **Portrait + paysage** : relayout fluide, colonne de lecture élargie en paysage.
- **Mode sombre iOS** : la page passe en sombre, les diagrammes restent sur un cadre clair pour
  préserver la palette OK-ia.
- **Interface bilingue FR/EN** : français par défaut si l'appareil est en français, anglais sinon ;
  choix manuel (Système / Français / English) dans **Réglages** sur l'écran d'accueil. Couvre les vues
  natives, les messages d'erreur, la couche web (`window.OKIA_LANG` : « Lire l'article », menus du
  diaporama) et la langue du résumé Apple Intelligence. Les App Intents (Siri/Raccourcis) suivent la
  langue **système** via `Localizable.xcstrings`. Voir `Models/Localization.swift` (`tr(fr, en)`).
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

1. **Signature** : la **Team** payante (`72NVM63N83`) et le **Bundle Identifier**
   `ch.ok-ia.markdownviewer` sont déjà configurés (signature **automatique**). Vérifiez dans Xcode →
   cible *OKiaMarkdownViewer* → **Signing & Capabilities** que **Automatically manage signing** est
   coché, la Team sélectionnée, et qu'aucune erreur de provisioning ne s'affiche (Xcode crée au besoin
   le certificat *Apple Distribution* et le profil App Store à la première archive).
2. **Versions** : `MARKETING_VERSION` = 1.0.0, `CURRENT_PROJECT_VERSION` incrémenté à chaque archive
   (build **10** au moment de la rédaction). App Store Connect refuse un build dont le numéro existe
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
