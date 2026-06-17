# Notes pour l'App Review

À coller dans **App Store Connect → Version → App Review Information → Notes**.
Pas de compte requis → laisser les champs identifiants vides ; cocher **« Sign-in not required »**.

---

## Notes (FR — tu peux aussi fournir une version EN ci-dessous)

```
md Viewer est un lecteur de fichiers Markdown (rapports). Aucune connexion ni compte n'est requis.

COMMENT TESTER
• À l'ouverture, touchez « Voir un exemple » : un document de démonstration intégré s'affiche et
  illustre toutes les fonctionnalités (rendu Markdown, diagrammes Mermaid, carte Leaflet, callouts,
  coloration d'entités).
• Vous pouvez aussi ouvrir n'importe quel fichier .md via « Ouvrir un fichier » (app Fichiers).

ACCÈS RÉSEAU
• L'app fonctionne hors-ligne. Le réseau n'est utilisé que pour :
  - les tuiles de fond de carte des documents contenant une carte (OpenStreetMap / CARTO) ;
  - le téléchargement d'un document si l'utilisateur ouvre un lien https.
• Aucune donnée utilisateur n'est collectée ni transmise (voir l'étiquette de confidentialité).

APPLE INTELLIGENCE (facultatif)
• La fonction « Résumé du document » utilise Foundation Models ON-DEVICE. Le bouton n'apparaît que
  si Apple Intelligence est disponible (iOS 26 / macOS 26+, appareil compatible). Sur un appareil
  sans Apple Intelligence, la fonction est simplement masquée — le reste de l'app fonctionne.

SIRI / RACCOURCIS (App Intents)
• L'app expose des actions « Ouvrir un rapport », « Ouvrir le dernier rapport » et « Résumer un
  rapport ». Elles s'appuient sur un dossier de « coffre » optionnel configuré par l'utilisateur ;
  sans coffre configuré, elles n'ont simplement pas de rapport à proposer.

PLATEFORMES
• Application universelle : iPhone, iPad et Mac (Mac Catalyst).
```

## Notes (EN — optionnel)

```
md Viewer is a Markdown file (report) reader. No account or login is required.

HOW TO TEST
• On launch, tap "Voir un exemple" to load a bundled demo document showcasing every feature
  (Markdown rendering, Mermaid diagrams, a Leaflet map, callouts, entity highlighting).
• You can also open any .md file via "Ouvrir un fichier" (Files app).

NETWORK
• The app works offline. Network is only used for map tiles (OpenStreetMap / CARTO) in documents
  that contain a map, and to download a document when the user opens an https link.
• No user data is collected or transmitted.

APPLE INTELLIGENCE (optional)
• "Document summary" uses ON-DEVICE Foundation Models. The button only appears when Apple
  Intelligence is available (iOS 26 / macOS 26+). It is hidden otherwise; the rest of the app works.

SIRI / SHORTCUTS (App Intents)
• The app exposes "Open report", "Open latest report" and "Summarize report" actions based on an
  optional user-configured vault folder.

PLATFORMS
• Universal app: iPhone, iPad and Mac (Mac Catalyst).
```

## Rappels de soumission

- **Sign-in required:** Non.
- **Export compliance:** déjà géré (`ITSAppUsesNonExemptEncryption=false`) → pas de question.
- **Build:** iOS → rattacher `1.0.0 (3)` (déjà sur App Store Connect) ; macOS → archiver le
  Catalyst (« My Mac ») et le rattacher à la plateforme macOS de la même fiche.
- **Contenu généré par IA:** si le formulaire le demande, préciser que les résumés sont produits
  **sur l'appareil** par Apple Intelligence à partir du document ouvert par l'utilisateur.
