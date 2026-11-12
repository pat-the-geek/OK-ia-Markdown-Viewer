# md Viewer après la 1.5 : 1.6, 1.7 et les fonctions pour tous

Le 6 novembre 2026, Patrick a retenu les dix propositions (« Ajoute les toutes, les idées sont
excellentes »), puis les a fait publier sur la feuille de route d'ok-ia.ch (OK-ia#585). Rien n'est
commencé. Les dates ne sont pas des promesses ; la répartition entre les versions peut bouger.

Contraintes déjà publiques, à tenir pour chacune : pas de serveur, pas d'IA distante (pas même
Private Cloud Compute), pas de compte, pas de pistage.

## 1.6 — Présenter (option Analytic)

- [ ] **Répéter son diaporama.** Une durée visée ; le mode présentateur chronomètre chaque
      diapositive ; à la fin, le temps passé sur chacune et les dépassements. S'appuie sur le
      chronomètre de `ModePresentateur.swift` et sur les notes de la 1.5.
- [ ] **L'iPhone pour télécommande.** Faire avancer le diaporama du Mac ou de l'iPad depuis
      l'iPhone, et y lire ses notes. D'appareil à appareil (réseau local, Multipeer ou Network
      framework), sans serveur. La séance partagée (`SeancePresentation`) est le point d'entrée.
- [ ] **Polycopié PDF.** Les diapositives et leurs notes, une à trois par page.
- [ ] **Thèmes à vos couleurs.** Un logo, deux couleurs et une police, appliqués à tous les
      diaporamas et repris dans l'export PowerPoint (`OOXMLExport`).

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
