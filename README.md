# OK-ia Markdown Viewer (iOS)

> Ce que les algorithmes ignorent encore. — [ok-ia.ch](https://ok-ia.ch)

Application iOS native (SwiftUI) qui ouvre des fichiers **Markdown contenant des diagrammes
Mermaid** et les affiche **exactement selon le principe du viewer de ok-ia.ch** : même charte,
même pipeline (frontmatter, callouts Obsidian, wiki-links, coloration NER), même thème Mermaid
normalisé. Tout fonctionne **100 % hors-ligne** — `marked` et `mermaid` sont embarqués dans l'app.

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
- **Fichiers récents** : les derniers `.md` ouverts sont mémorisés (bookmarks security-scoped) et
  proposés sur l'écran d'accueil.
- **Sommaire (TOC)** : liste des titres du document avec saut direct à une section.
- **Recherche dans le document** : surlignage des occurrences + navigation précédent/suivant.
- **Partage / export** : export du rendu en **PDF** ou partage du fichier `.md` via la share sheet iOS.

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
│   └── MarkdownDocument.swift      # chargement UTF-8 → Latin-1, security-scoped, sans UIKit
├── Views/
│   ├── RootView.swift              # routage + .fileImporter + alertes
│   ├── EmptyStateView.swift        # accueil (ouvrir / exemple)
│   ├── ReaderView.swift            # barre titre + overlay zoom
│   ├── MarkdownWebView.swift       # WKWebView + message handlers + injection JSON sûre
│   └── DiagramZoomView.swift       # overlay pinch/pan/double-tap (SVG vectoriel)
├── Web/                            # (référence de dossier — copiée verbatim dans le bundle)
│   ├── renderer.html               # gabarit ; charge vendor + thème + render.js
│   ├── render.js                   # pipeline complet OK-ia
│   ├── mermaid-okia-theme.js       # thème + normalizeMermaidPalette + applyMermaidTextColors
│   ├── style.css                   # charte, callouts, wiki-links, NER, mermaid, dark mode
│   ├── fonts/Nunito-{Black,Regular}.woff2
│   └── vendor/marked.min.js, mermaid.min.js   # bundlés offline (aucun CDN)
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
2. **Versions** : `MARKETING_VERSION` = 1.0.0, `CURRENT_PROJECT_VERSION` = 1. App Store Connect refuse
   un build dont le numéro existe déjà : si l'upload signale « build already exists », **incrémentez
   `CURRENT_PROJECT_VERSION`** (le `.xcodeproj` étant commité et XcodeGen non requis, modifiez-le via
   *Xcode → General → Build*, ou `project.yml` + `xcodegen generate` si XcodeGen est installé).
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
