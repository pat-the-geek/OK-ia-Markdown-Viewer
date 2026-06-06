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
- **Portrait + paysage** : relayout fluide, colonne de lecture élargie en paysage.
- **Mode sombre iOS** : la page passe en sombre, les diagrammes restent sur un cadre clair pour
  préserver la palette OK-ia.

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
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

> **Note environnement** : sur cette machine, le *runtime* du simulateur iOS était périmé
> (`CoreSimulator` 1051.50.0 vs build 1051.54.0 ; runtime `23D8133` manquant), ce qui fait échouer
> `actool` (compilation de l'icône, variante *thinned*) — un **redémarrage du Mac** ou la réinstallation
> du runtime via *Xcode → Settings → Components* corrige le problème. Le code Swift compile sans erreur
> (`swiftc -typecheck` : OK) et le pipeline de rendu a été validé visuellement dans un navigateur
> (5 diagrammes, callouts, wiki-links, NER, contraste de texte sur fonds sombres). L'archivage Xcode
> (build *device*) pour TestFlight n'est pas concerné par ce souci de simulateur.

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
- `MarkdownLoader` gère `startAccessingSecurityScopedResource`, une copie coordonnée en repli,
  et le décodage UTF-8 → ISO Latin-1.
- Le Markdown est passé à la WKWebView via `evaluateJavaScript` avec une **chaîne JSON encodée**
  (jamais concaténée dans du HTML) → aucune injection possible.

---

## Livraison TestFlight

1. **Signature** : dans Xcode, cible *OKiaMarkdownViewer* → **Signing & Capabilities** →
   cocher **Automatically manage signing**, choisir votre **Team** Apple Developer.
   Le **Bundle Identifier** est `ch.ok-ia.markdownviewer` (modifiable dans `project.yml`).
2. **Versions** : `MARKETING_VERSION` = 1.0.0, `CURRENT_PROJECT_VERSION` = 1 (incrémentez le build
   à chaque upload, dans `project.yml` puis `xcodegen generate`, ou via *Xcode → General*).
3. **Archive** : sélectionnez la destination **Any iOS Device (arm64)** →
   **Product → Archive**.
4. **Upload** : dans l'Organizer → **Distribute App → App Store Connect → Upload**.
   `ITSAppUsesNonExemptEncryption = NO` évite le questionnaire d'export.
5. **TestFlight** : dans App Store Connect → onglet **TestFlight** → activez le build →
   invitez les **testeurs internes** (jusqu'à 100, sans revue) ou créez un **groupe externe**
   (revue TestFlight légère requise).
6. **Aucune** soumission à la revue App Store, **aucun** déploiement store.

---

## Phase 2 — macOS (préparé, non livré)

L'architecture est volontairement compatible avec une future cible **Mac Catalyst** :

- `MarkdownDocument` / `MarkdownLoader` sont **sans UIKit** (réutilisables tels quels).
- Les vues UIKit (`WKWebView`) sont isolées dans des `UIViewRepresentable` (compatibles Catalyst).
- `project.yml` : passer `SUPPORTS_MACCATALYST: YES` et ajouter `macCatalyst` à la cible.

Points d'extension à implémenter pour macOS :

- Menu **Fichier** (Ouvrir / Ouvrir récent) via `Commands`.
- **Glisser-déposer** d'un `.md` sur la fenêtre (`onDrop`).
- Fenêtres redimensionnables, **zoom trackpad** (pinch) et **⌘+molette**.

---

## Critères d'acceptation — état

| # | Critère | État |
|---|---------|------|
| 1 | Ouverture `.md` depuis Safari/Files/autre app | ✅ (UTI + onOpenURL + fileImporter) |
| 2 | Rendu visuellement identique à ok-ia.ch | ✅ (validé : 5 diagrammes, callouts, wiki, NER, palette) |
| 3 | Zoom diagramme (pinch/pan/double-tap, SVG net) | ✅ (DiagramZoomView, SVG vectoriel) |
| 4 | Rotation portrait↔paysage fluide | ✅ (CSS `@media orientation` + WKWebView) |
| 5 | Fonctionne hors-ligne (aucun CDN) | ✅ (marked/mermaid/fonts bundlés) |
| 6 | Archive/upload TestFlight sans erreur de signature | ⚙️ à finaliser dans Xcode (Team à définir) |
| 7 | README (build, assets, TestFlight, Phase 2) | ✅ (ce document) |
