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
- [ ] **Le point de la semaine.** Ce qui est entré dans le coffre depuis la dernière visite :
      nouveaux documents, entités qui apparaissent ou reviennent plus souvent, résumé sur
      l'appareil.
- [ ] **Importer Pages, Keynote, Numbers, Excel et CSV.** Les paquets d'Apple portent un aperçu
      PDF (à vérifier pour chaque format et version) qui passe par l'import PDF ; Excel et CSV
      deviennent des tableaux Markdown.

## Pour tous, sans l'option, au fil des versions

- [ ] **Un tableau devient un graphique**, en barres ou en courbes, à la lecture comme au
      diaporama ; exporté en image dans Word et PowerPoint.
- [ ] **Lecture à voix haute** par les voix de l'appareil (`AVSpeechSynthesizer`), dans les quinze
      langues, le passage lu surligné.
- [ ] **Widgets et contrôles** : le dernier rapport fornews et les documents récents sur l'écran
      d'accueil ; la recherche dans le coffre dans le Centre de contrôle.
