# md Viewer après la 1.5 : 1.6, 1.7 et les fonctions pour tous

Le 6 novembre 2026, Patrick a retenu les dix propositions (« Ajoute les toutes, les idées sont
excellentes »), puis les a fait publier sur la feuille de route d'ok-ia.ch (OK-ia#585). Rien n'est
commencé. Les dates ne sont pas des promesses ; la répartition entre les versions peut bouger.

Contraintes déjà publiques, à tenir pour chacune : pas de serveur, pas d'IA distante (pas même
Private Cloud Compute), pas de compte, pas de pistage.

## 1.6 — Présenter (option Analytic)

- [x] **Répéter son diaporama** (fait le 12/11/2026, `RepetitionDiaporama`, `OutilsDiaporama.swift`) :
      menu du diaporama › Présenter › « Répéter… » ; une durée visée (retenue) ; un bandeau en bas
      compte le temps total et celui de la diapositive, en rouge au-delà de la part de chacune ;
      « Terminer » ouvre le bilan : le temps de chaque diapositive, les dépassements, celles non
      vues (« Arrêtée avant la fin »). Vu au simulateur iPad.
- [x] **L'iPhone pour télécommande** (fait le 12/11/2026, `Telecommande.swift`,
      `TelecommandeView`) : MultipeerConnectivity, chiffré, sans serveur ; le diaporama s'annonce
      (`_okia-telecom._tcp`), l'iPhone le trouve (menu du dossier › « Télécommande d'un
      diaporama… »), le présentateur autorise chaque appareil. L'iPhone reçoit l'image de la
      diapositive, son rang et ses notes ; il envoie suivante/précédente, **crayon, cercle,
      surligneur et pointeur** (Patrick : « faire des cercles, des traits, etc. montrer un
      pointeur »), affichés sur le diaporama et sur l'écran du public ; l'iPhone voit ce qu'il
      dessine. Mac : droit `network.server` ajouté au bac à sable.
      **Essayée par Patrick sur ses appareils le 13/11/2026 (builds 170 à 174)** ; ses retours :
      bouton Télécommande en vue sur l'accueil de l'iPhone (170) ; la diapositive bord à bord, en
      largeur plein écran avec fermer, chronomètre, outils, notes et flèches en verre par-dessus
      (172–173, harnais `OKIA_TELECOMMANDE=pilote`) ; la photo rognée à la diapositive, sans les
      boutons du diaporama, dessins recalés sur ce cadre (173) ; zone sûre, même marge des deux
      côtés (174) ; **annotations gardées par diapositive tout le diaporama** (174, « Les
      annotations restent bien, merci c'est parfait »).
- [x] **Polycopié PDF** (fait le 12/11/2026, `Polycopie`) : menu › « Polycopié PDF… » ; une, deux
      ou trois diapositives par page, avec ou sans les notes (trois par page : les notes, ou des
      lignes pour en prendre, à côté) ; A4, titre et numéro de page ; les diapositives toujours en
      16:9, même sur un iPad tenu droit. Vu au simulateur (PDF à 2 et 3 par page).
- [x] **Thèmes à vos couleurs** (fait le 12/11/2026, `ThemeMarque`, `MarqueView`) : menu ›
      « Thème à vos couleurs… » ; un logo (Photos ou fichier), fond, accent, police ; « Pour tous
      les diaporamas », sinon le thème « Ma marque » dans le menu des thèmes ; l'export PowerPoint
      reprend fond, couleurs, police et logo (masque, thème, et couleur et police sur chaque passage
      de texte : sans elles, Aperçu et Keynote écrivaient les zones de texte en noir) ; l'en-tête
      et les filets des tableaux prennent des nuances du fond. Vu au simulateur et dans Aperçu ;
      **pas encore ouvert dans PowerPoint ni Keynote**.

## 1.7 — Le coffre (option Analytic)

- [ ] **Le coffre ouvert à vos assistants** — revu le 13/11/2026 (Patrick : « le point interroger
      le coffre, on devrait le revoir : comment faciliter la lecture du coffre par claude, chatgpt,
      codex, copilot, etc. », puis « on pourrait faire un serveur mcp adapté à cela »). Devient la
      **1.6** sur la feuille de route. Le coffre est déjà ce que ces assistants lisent le mieux : un
      dossier de fichiers Markdown. md Viewer le leur rend lisible, sans rien envoyer lui-même.
      C'est vous qui ouvrez le coffre à l'assistant de votre choix, et rien n'est ouvert par défaut.

      **A. Un coffre qui s'explique (pour tous, réglage coupé par défaut).** md Viewer écrit dans le
      coffre ce qu'un assistant doit savoir :
      - `AGENTS.md` à la racine : la convention que lisent Codex, Copilot, Cursor, Gemini CLI, etc.
        Il décrit le rangement (année/mois, `coffre md viewer`, documents analysés), les champs
        YAML, les diapositives `---`, les notes de l'orateur en commentaire, le bloc
        `md-viewer-annotations` à ne pas toucher, la section « Entités » des rapports fornews, et
        comment citer un document (chemin et titre).
      - `CLAUDE.md` en une ligne qui renvoie à `AGENTS.md`, pour Claude Code.
      - Dans `.mdviewer/` (caché, donc ignoré par la lecture du coffre) :
        - `index.md` : un document par ligne, avec son titre, sa date, ses étiquettes, sa source et
          ses entités principales ;
        - `entites.md` et `entites.json` : chaque entité, ses documents et ses voisins ;
        - `annotations.md` : tous les surlignages et notes, avec leur document et leur citation.
      - Mis à jour après chaque relecture du coffre, par une écriture coordonnée, hors du fil
        principal.
      - Ouvrir ce dossier dans Claude Code, Codex, VS Code (Copilot) ou Cursor suffit alors.

      **B. Le serveur MCP du coffre (Mac, option Analytic).**
      - **Le modèle** : celui de fornews.ai, en reprenant le cœur MCP de l'édition Agence
        (`FornewsServeurAgence/…/ProtocoleMCP.swift`, `ServeurMCPAgence`, ses tests). Il comprend :
        - coupé par défaut ;
        - HTTP sur `http://127.0.0.1:<port>/mcp` ;
        - un **jeton** obligatoire ;
        - une portée « ce Mac » par défaut, « mon réseau privé (Tailscale) » sur demande.

        Pas le modèle de fornews 1.7.3, qui écoute toutes les interfaces sans authentification.
        Le droit `network.server` est déjà dans `macOS.entitlements` (ajouté pour la télécommande).
      - **Outils en lecture seule d'abord :**
        - `chercher` : le moteur de `RechercheCoffre` (mots, expression entre guillemets, sans
          casse ni accents) ; il rend des passages, avec leur document ;
        - `lister_documents` : par dates, dossier, étiquettes, origine (web, PDF, Word…) ;
        - `lire_document` : le Markdown, par section si le document est long, sans les images
          `data:`, notes de l'orateur comprises ;
        - `entites`, `fiche_entite` : où elle apparaît, avec qui, depuis quand ;
        - `annotations` : par document ou toutes ;
        - `point_de_la_semaine` ;
        - `lieux` : la carte du coffre en liste.
      - **Ressources** : chaque document en `coffre://chemin`.
      - **Invites** : « Note de synthèse sur… », « Qui est… dans mes documents », « Ce qui a changé
        cette semaine ».
      - **Écrire, plus tard et sur réglage à part** :
        - `creer_document`, rangé par année et mois, marqué « rédigé par un assistant » dans son
          en-tête ;
        - `ajouter_etiquette`.

        Jamais d'effacement.
      - **Ce que l'utilisateur voit** : le journal « Ce que les assistants ont lu » (outil, document,
        heure), et un bouton pour couper le serveur.
      - **Les clients à essayer** :
        - Claude Desktop et Claude Code ;
        - Codex CLI ;
        - VS Code (Copilot en mode agent) ;
        - ChatGPT : ses connecteurs MCP passent par une adresse publique en HTTPS. Pas de tunnel
          fourni par nous : pour ChatGPT, la voie C.
      - **À vérifier** :
        - le serveur ne vit que tant que md Viewer est ouvert sur le Mac ; faut-il un mode dans la
          barre des menus ?
        - l'accès au coffre (signet à portée de sécurité) depuis le serveur, dans le bac à sable.
      - iPhone et iPad : pas de serveur (iOS ne garde pas une app à l'écoute). À la place, des
        intentions (App Intents) — chercher, lire, entités — pour Raccourcis et Siri.

      **C. « Envoyer à un assistant » (tous les appareils, pour tous).**
      - Des documents choisis, un résultat de recherche, une collection ou une entité deviennent un
        seul dossier Markdown : les sources, leurs dates et leurs chemins, sans les images `data:`,
        avec la taille estimée en mots.
      - Il part par la feuille de partage (ChatGPT, Claude, Copilot…) ou se copie. C'est un geste de
        l'utilisateur, jamais un envoi de md Viewer.

      **D. Interroger sur l'appareil**, l'idée d'origine : la discussion d'un document étendue à
      tout le coffre, répondue par le modèle de l'appareil, qui cite ses documents, jamais un
      chiffre absent des sources. Gardée pour qui ne veut aucune IA extérieure, après A, B et C.

      **La promesse publique** « pas d'IA distante » reste vraie pour md Viewer lui-même. La page
      doit dire que l'ouverture à un assistant est un choix de l'utilisateur, coupé par défaut, et
      que c'est l'assistant qui lit.
- [x] **Le point de la semaine** (fait le 12/11/2026, `PointSemaine`, `PointSemaineView`) : un
      quatrième segment « Semaine » dans l'analyse du coffre, ouvert d'office quand il y a du
      nouveau. Depuis la dernière visite (retenue à la fermeture, si le point a été regardé), ou
      les 7 ou 30 derniers jours : les documents arrivés (date de modification), les noms nouveaux,
      ceux qui reviennent plus souvent que sur la période précédente de même durée. Résumé par le
      modèle de l'appareil (`MoteurRedaction`, titres et noms seulement, contrôle des inventions),
      une phrase composée ici sans Apple Intelligence. Vu au simulateur iPad.
- [x] **Importer Pages, Keynote, Numbers, Excel et CSV** (fait le 12/11/2026, option Analytic,
      mêmes entrées et même contrôle d'achat que Word, PDF et PowerPoint) :
      - Excel (`.xlsx`) et CSV/TSV deviennent des tableaux Markdown, une section par feuille
        (`ImportTableur`) : textes partagés, dates en AAAA-MM-JJ, formules par leur résultat,
        séparateur du CSV deviné (`;` `,` tabulation), 2 000 lignes par feuille au plus ;
      - **vérifié** : les documents d'iWork récents ne portent PAS d'aperçu PDF, seulement
        `preview.jpg` (la première page) ; seuls ceux d'iWork '09 ont `QuickLook/Preview.pdf`
        (l'import PDF les prend) ; WebKit ne les affiche pas sur iPhone et iPad ;
      - Pages : le texte du document, lu dans ses `.iwa` (Snappy + protobuf, `LecteurIWA`,
        `TSWP.StorageArchive`), paragraphes compris, puis l'image de la première page ;
      - Keynote et Numbers : l'image de la première diapositive ou feuille, avec une note qui
        conseille l'export PDF (l'ordre des diapositives et les cellules de Numbers ne se lisent
        pas sans le format complet) ;
      - vu au simulateur iPad avec de vrais documents créés par Pages, Keynote et Numbers.

## Pour tous, sans l'option, au fil des versions

- [ ] **Un tableau devient un graphique**, en barres ou en courbes, à la lecture comme au
      diaporama ; exporté en image dans Word et PowerPoint.
- [ ] **Lecture à voix haute** par les voix de l'appareil (`AVSpeechSynthesizer`), dans les quinze
      langues, le passage lu surligné.
- [ ] **Widgets et contrôles** : le dernier rapport fornews et les documents récents sur l'écran
      d'accueil ; la recherche dans le coffre dans le Centre de contrôle.
