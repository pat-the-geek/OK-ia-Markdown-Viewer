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
      pointeur »), affichés sur le diaporama et sur l'écran du public, effacés au changement de
      diapositive ; l'iPhone voit ce qu'il dessine. Mac : droit `network.server` ajouté au bac à
      sable. **Non vérifié d'appareil à appareil** : deux simulateurs du même Mac ne se trouvent
      pas ; le dessin et les commandes sont vérifiés au simulateur par `OKIA_TELECOM_ESSAI`. À
      essayer sur l'iPhone et l'iPad (ou le Mac) réels.
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

- [ ] **Interroger tout le coffre.** La discussion d'un document étendue à tous : recherche dans
      l'index du coffre (`AnalyseCoffre`, `RechercheCoffre`), réponse sur l'appareil qui cite ses
      documents, jamais un chiffre absent des sources (même vérification que la conversion).
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
