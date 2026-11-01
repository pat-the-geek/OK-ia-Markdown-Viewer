# Notes pour l'App Review

À coller dans **App Store Connect → Version → App Review Information → Notes**.
Pas de compte requis → laisser les champs identifiants vides ; cocher **« Sign-in not required »**.

> **Coller la version anglaise.** Les examinateurs travaillent en anglais ; la française reste ici
> pour mémoire et pour relecture. Les deux disent la même chose.

---

## Notes (EN — à coller) — version 1.4, 1er novembre 2026

```
md Viewer is a reader for Markdown reports. No account or login is required.

NEW IN 1.4 — THE ANALYTIC OPTION (in-app purchase, submitted with this version)
• One non-consumable product per platform: ch.okia.markdownviewer.analytic (iPhone and iPad) and ch.okia.markdownviewer.analytic.mac (Mac). Family Sharing is on.
• To see the offer: on the home screen tap "View a sample", then the Entities button (two people) in the reader's toolbar. "Unlock Analytic · <price>" buys it with the sandbox account; "Restore purchases" sits below.
• With the option, on the same sample:
 – Entities: the people, organisations, places and products of the document, as a list, a gallery and a map. Found ON-DEVICE (NaturalLanguage; Foundation Models when available).
 – Wikidata is OFFERED, never imposed: at the first analysis the app asks "Complete with Wikidata?". Only after "yes" does it send the NAME of an entity (never the document or its title) to wikidata.org, then reads that entry's Wikipedia summary and Wikimedia Commons photo. "Entity options" turns it off again. Without it, everything works from the document alone.
 – Annotate (pencil button): Apple Pencil, finger or mouse; the notes follow into the slideshow and into PDF and Word exports.
 – Import Word, PDF or PowerPoint: folder button in the reader's toolbar (Mac: File menu, Shift-Cmd-I), or "Open a file" with such a file. The conversion runs on the device.
 – Vault analysis: once a vault folder is chosen, an analysis of all its reports.
 – Safari: Share, then "md Viewer" turns the page into a reading sheet, translated on the device.
• iCloud: annotations, entity corrections and the entity cache go to the user's PRIVATE CloudKit database, for their other devices; documents the app creates go to the user's iCloud Drive, folder "md Viewer". We have no access to either.
• Spotlight: with the option, the vault's documents are indexed ON-DEVICE so a system search finds them.
• The interface now speaks 15 languages.

HOW TO TEST THE REST
• "View a sample" opens a bundled demo document with every rendering feature: Markdown, Mermaid diagrams, a map, callouts, entity highlighting. Any .md file opens with "Open a file".
• A document containing --- is presented full screen with the slideshow button.
• Apple Intelligence (only shown on a device that has it): "Document summary", "Chat with the document" and "Convert to presentation" run ON-DEVICE with Foundation Models (SystemLanguageModel). No text leaves the device.
• Translate (book icon): Apple's Translation framework, ON-DEVICE; a missing language comes only through the SYSTEM prompt. The sample is in French.
• iPhone Duo: two parts across the fold, and a book mode when half-folded.

FORNEWS.AI
• The app declares the App Group "group.ai.fornews.native", shared with fornews.ai, a separate app from the same developer (team PU9BSXN2V5). fornews.ai writes a document there and opens md Viewer with mdviewer://fichier?nom=<file name>, because iOS cannot hand a file to a named app. With both apps installed, md Viewer also reads the entity entries fornews.ai saved there; nothing goes over the network. The folder keeps the last ten documents, and the received name is reduced to a plain file name.

NETWORK
• The app works offline. It goes online only for: map tiles (OpenFreeMap / OpenStreetMap); a document or image opened from an https link; a web page or PDF shared from Safari; and Wikidata, Wikipedia and Wikimedia Commons, only after the user's consent.
• No user data is collected or transmitted to us. No analytics, no advertising, no tracking.

SIRI / SHORTCUTS
• "Open report", "Open latest report" and "Summarize report" need a vault folder chosen by the user; the option adds "Analyze a Document", "Import into md Viewer", "Make a Reading Sheet of a Web Page" and "Export as PDF with Annotations".

PLATFORMS
• Universal app: iPhone, iPad and Mac (Mac Catalyst). Minimum system: iOS, iPadOS and macOS 26.4.
```

## Notes (FR — pour mémoire)

```
NOUVEAU EN 1.3 — COMMENT TESTER
• Convertir en présentation (appareil compatible Apple Intelligence) : ouvrez l'exemple (« Voir
  un exemple »), touchez le bouton ✦ de la barre du lecteur, puis « Convertir en présentation ».
  Choisissez un nombre de diapositives et touchez « Convertir ». Le modèle rédige les diapositives
  SUR L'APPAREIL (Foundation Models, SystemLanguageModel) ; chacune apparaît en vignette dès
  qu'elle est prête, puis « Lancer le diaporama » les présente. Aucun texte ne quitte l'appareil.
• Sur grand écran (iPad ou iPhone Pro Max en paysage, fenêtre Mac large, iPhone Duo déplié), la
  conversion, le résumé, la discussion et le sommaire s'ouvrent à côté du document plutôt que
  dans une feuille.
• Thèmes de lecture : le bouton « Aa » propose cinq thèmes, en clair et en sombre.
• iPhone Duo : l'app occupe tout l'écran intérieur et se partage en deux de part et d'autre de la
  pliure.
• Notes de bas de page des rapports de veille fornews.ai : toucher un appel en exposant montre la
  note.
• Compilée avec le SDK iOS 27.1 ; le système minimal reste iOS/iPadOS/macOS 26.4.

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
• « Résumé du document », « Discuter avec le document » et « Convertir en présentation »
  utilisent Foundation Models SUR L'APPAREIL, à partir du seul document ouvert. Aucun texte ne
  quitte l'appareil.
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
- **Build :** rattacher le dernier build **`1.3`** de TestFlight (50 au 09/10/2026) sur **les deux plateformes** — iOS et macOS sont envoyés par
  `scripts/deploy-testflight.sh --both` depuis le même numéro, plus besoin de Transporter.
- **Contenu généré par IA :** si le formulaire le demande, préciser que résumé, discussion et
  traduction sont produits **sur l'appareil**, à partir du document que l'utilisateur a ouvert —
  la conversion en présentation aussi (1.3).
