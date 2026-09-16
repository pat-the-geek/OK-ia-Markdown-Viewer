# Notes pour l'App Review

À coller dans **App Store Connect → Version → App Review Information → Notes**.
Pas de compte requis → laisser les champs identifiants vides ; cocher **« Sign-in not required »**.

> **Coller la version anglaise.** Les examinateurs travaillent en anglais ; la française reste ici
> pour mémoire et pour relecture. Les deux disent la même chose.

---

## Notes (EN — à coller)

```
md Viewer is a Markdown document (report) reader. No account or login is required.

HOW TO TEST
• On launch, tap "View a sample" (FR: « Voir un exemple »). A bundled demo document opens and
  shows every rendering feature: Markdown, Mermaid diagrams, a map, callouts, entity highlighting.
• Any .md file can also be opened with "Open a file" (Files app).
• A document containing --- can be presented as a full-screen slideshow with the ▶ button.

NEW IN 1.2 — ON-DEVICE DOCUMENT TRANSLATION
• The demo document is written in French, so translation can be tested right away: in the
  reader's bar, tap the book icon ("Translate") and pick English. The document is
  translated paragraph by paragraph, including diagram labels; code, links and URLs stay intact.
  The same menu then offers "Show original".
• Translation uses Apple's Translation framework, ON-DEVICE. No text leaves the device and no
  remote service is called.
• If a language dictionary is not installed, the app downloads nothing on its own: it shows a
  banner and waits for the user's tap, then the SYSTEM prompt handles the download.
• 1.2 requires iOS/iPadOS 26.4 or macOS 26.4: the framework pieces it relies on do not exist
  before that version.

NEW IN 1.2 — OPENING DOCUMENTS FROM FORNEWS.AI
• The app declares the App Group "group.ai.fornews.native". fornews.ai is a separate app from the
  same developer (team PU9BSXN2V5). It writes a document into the shared container and opens
  md Viewer with the URL mdviewer://fichier?nom=<file name>. This exists because iOS cannot hand a
  file to a named app, and long reports do not fit in a URL.
• Reviewing this path requires the fornews.ai app; everything else works without it. The shared
  folder keeps only the last ten documents, stays on the device, and the received name is reduced
  to a plain file name so it cannot point outside the folder.

APPLE INTELLIGENCE (optional)
• "Document summary" and "Chat with the document" use Foundation Models ON-DEVICE and answer
  from the open document only. No text leaves the device.
• The ✦ menu only appears when Apple Intelligence is available on the device. Otherwise both
  features are hidden and the rest of the app works.

NETWORK
• The app works offline. Network is used only for map tiles (OpenFreeMap / OpenStreetMap) in
  documents containing a map, and to download a document when the user opens an https link.
• No user data is collected or transmitted.

SIRI / SHORTCUTS (App Intents)
• "Open report", "Open latest report" and "Summarize report" rely on an optional user-configured
  vault folder; without one, they have no report to offer.

PLATFORMS
• Universal app: iPhone, iPad and Mac (Mac Catalyst).
```

## Notes (FR — pour mémoire)

```
md Viewer est un lecteur de documents Markdown (rapports). Aucun compte ni connexion n'est requis.

COMMENT TESTER
• À l'ouverture, touchez « Voir un exemple » : un document de démonstration intégré illustre
  tout le rendu — Markdown, diagrammes Mermaid, carte, callouts, coloration d'entités.
• N'importe quel fichier .md s'ouvre aussi par « Ouvrir un fichier » (app Fichiers).
• Un document contenant --- se présente en diaporama plein écran par le bouton ▶.

NOUVEAU EN 1.2 — TRADUCTION DU DOCUMENT SUR L'APPAREIL
• Le document de démonstration est en français : la traduction s'éprouve donc tout de suite. Dans
  la barre du lecteur, touchez l'icône du livre et choisissez l'anglais. Le document se traduit
  paragraphe après paragraphe, libellés des diagrammes compris ; le code, les liens et les URL
  restent intacts. Le même menu propose ensuite « Voir l'original ».
• La traduction utilise le framework Translation d'Apple, SUR L'APPAREIL. Aucun texte ne quitte
  l'appareil, aucun service distant n'est appelé.
• Si le dictionnaire d'une langue manque, l'app ne télécharge rien d'elle-même : un bandeau
  attend le geste de l'utilisateur, puis c'est l'invite du SYSTÈME qui télécharge.
• La 1.2 exige iOS/iPadOS 26.4 ou macOS 26.4 : les pièces du framework dont elle dépend
  n'existent pas avant.

NOUVEAU EN 1.2 — OUVERTURE DE DOCUMENTS DEPUIS FORNEWS.AI
• L'app déclare le groupe d'applications « group.ai.fornews.native ». fornews.ai est une autre
  app du même développeur (équipe PU9BSXN2V5). Elle écrit un document dans le conteneur partagé et
  ouvre md Viewer par l'URL mdviewer://fichier?nom=<nom du fichier>. Ce détour existe parce qu'iOS
  ne sait pas remettre un fichier à une app désignée, et qu'un long rapport ne tient pas dans une
  URL.
• Éprouver ce chemin demande l'app fornews.ai ; tout le reste fonctionne sans elle. Le dossier
  partagé ne garde que les dix derniers documents, reste sur l'appareil, et le nom reçu est réduit
  à un simple nom de fichier pour ne pas désigner autre chose.

APPLE INTELLIGENCE (facultatif)
• « Résumé du document » et « Discuter avec le document » utilisent Foundation Models SUR
  L'APPAREIL et répondent à partir du seul document ouvert. Aucun texte ne quitte l'appareil.
• Le menu ✦ n'apparaît que si Apple Intelligence est disponible ; sinon les deux fonctions sont
  masquées et le reste de l'app fonctionne.

RÉSEAU
• L'app fonctionne hors ligne. Le réseau ne sert qu'aux tuiles de fond de carte (OpenFreeMap /
  OpenStreetMap) et au téléchargement d'un document quand l'utilisateur ouvre un lien https.
• Aucune donnée utilisateur n'est collectée ni transmise.

SIRI / RACCOURCIS (App Intents)
• « Ouvrir un rapport », « Ouvrir le dernier rapport » et « Résumer un rapport » s'appuient sur un
  dossier de coffre facultatif ; sans coffre, elles n'ont pas de rapport à proposer.

PLATEFORMES
• Application universelle : iPhone, iPad et Mac (Mac Catalyst).
```

## Rappels de soumission

- **Sign-in required :** Non.
- **Export compliance :** déjà géré (`ITSAppUsesNonExemptEncryption=false`), aucune question.
- **Build :** rattacher **`1.2 (39)`** sur **les deux plateformes** — iOS et macOS sont envoyés par
  `scripts/deploy-testflight.sh --both` depuis le même numéro, plus besoin de Transporter.
- **Contenu généré par IA :** si le formulaire le demande, préciser que résumé, discussion et
  traduction sont produits **sur l'appareil**, à partir du document que l'utilisateur a ouvert.
