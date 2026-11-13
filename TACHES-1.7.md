# md Viewer après la 1.6 : écrire, veiller, de nouvelles sources, présenter partout

Le 13 novembre 2026, Patrick a demandé une analyse de la feuille de route publiée
(https://ok-ia.ch/mdviewer/roadmap.html) et quinze évolutions, puis : « planifie les toutes. est-ce
qu'on peut prévoir effectivement un éditeur markdown ? pour des documents et pour les
présentations ». Rien n'est commencé. Rien n'est annoncé sur le site. La répartition entre les
versions est une proposition, à valider.

Contraintes publiques, à tenir pour chacune : pas de compte, pas de serveur, pas d'IA distante (pas
même Private Cloud Compute), pas de pistage. La lecture reste gratuite.

## Répartition proposée

| Version | Thème | Contenu |
|---|---|---|
| 1.6 | Le coffre ouvert à vos assistants | revue le 13/11/2026 : un coffre qui s'explique (`AGENTS.md`), un serveur MCP sur Mac, « Envoyer à un assistant », puis l'interrogation sur l'appareil (TACHES-1.6.md) |
| 1.7 | Écrire | l'éditeur de documents (1), l'éditeur de présentations (1 bis), écrire avec l'IA de l'appareil (1 ter), des diagrammes sur demande (1 quater), les modèles (2), comparer deux versions (3) |
| 1.8 | Le coffre qui veille | étiquettes (4), liens entre documents (5), surveiller un nom (6), frise (7), réseau des entités (8) |
| 1.9 | De nouvelles sources | l'audio (9), l'EPUB et les e-mails (10) |
| 2.0 | Présenter partout | la montre (11), SharePlay (12), le diaporama traduit (13), vidéo et page web autonome (14) |
| au fil des versions | Pour tous | VoiceOver (15), avec le graphique d'un tableau, la voix et les widgets déjà annoncés |

L'éditeur passe en tête : c'est le manque le plus visible (on ne peut écrire que les notes de
l'orateur), et plusieurs évolutions en dépendent (modèles, étiquettes, liens, diapositives).

---

## 1.7 — Écrire

### 1. L'éditeur de documents

**Faisable : oui.** Deux choses, vérifiées dans le code le 13/11/2026, le rendent sûr :

- **Les annotations survivent aux retouches.** Elles s'ancrent par citation (`annotations.js`,
  `ancrerTexte` : le texte exact, avec ce qui le précède et le suit), comme les sélecteurs de
  citation du W3C, pas par position : une retouche ailleurs ne les déplace pas, et une annotation
  dont le texte a disparu se dit introuvable. Ce qui change, c'est leur **clé** : le nom du fichier
  et l'empreinte de son contenu (`IdentiteDocument.cle`, SHA-256 sans les commentaires). À chaque
  enregistrement, l'éditeur doit donc les faire passer sous la nouvelle clé, comme le fait déjà
  « Relier à un document… » (`AnnotationsStore.relier`).
- **L'app réécrit déjà les fichiers sans risque** : notes de l'orateur (`NotesOrateur.enregistrer`)
  et annotations dans le document (`AnnotationsIntegrees`) passent par une écriture coordonnée, hors
  du fil principal, seulement dans un fichier Markdown hors de l'app, lisible en UTF-8, et qui n'a
  pas changé depuis l'ouverture.

**Le choix de fond : le Markdown visible, avec l'aperçu à côté — pas un traitement de texte.**

- Un éditeur « tel quel » (WYSIWYG, `contenteditable`) ferait l'aller-retour Markdown → HTML →
  Markdown à chaque frappe : il perdrait des tableaux, des blocs Mermaid, des cartes, des
  commentaires, des images `data:`. Le fichier ne serait plus celui que Patrick a écrit.
- Donc : le texte Markdown, coloré (titres, gras, listes, liens, code, commentaires en gris), dans
  une vue TextKit 2 ; à côté, l'aperçu rendu par `render.js`, rafraîchi pendant la frappe.
  - Côte à côte sur le Duo déplié, l'iPad et le Mac ;
  - sur l'iPhone et le Duo plié, une bascule « Texte / Aperçu ».
- L'aperçu suit le curseur : toucher un paragraphe de l'aperçu place le curseur dans le texte, et
  inversement.

**Ce qu'il faut savoir faire :**

- **La barre d'outils :**
  - titre, gras, italique, liste, liste numérotée, citation, lien, tableau, bloc de code,
    séparateur `---` ;
  - insérer une image : depuis Photos ou Fichiers, copiée à côté du document en chemin relatif ;
    `data:` seulement si le document l'est déjà (import) ;
  - insérer un diagramme Mermaid ou une carte depuis un modèle.
- **Ce qu'il faut protéger :**
  - **Les longues images `data:` des documents importés** (lignes de centaines de milliers de
    caractères) sont repliées en une puce « image » : jamais affichées en clair, jamais coupées par
    une frappe.
  - **Le bloc des annotations en fin de fichier** (`md-viewer-annotations`) et l'en-tête YAML ne
    s'éditent pas en clair : l'en-tête passe par une feuille « Propriétés » (titre, date,
    étiquettes du point 4).
  - **Les notes de l'orateur** (commentaires) restent visibles, en gris, modifiables.
- **Enregistrer :**
  - enregistrement automatique quelques secondes après la dernière frappe ;
  - annuler et rétablir, y compris au clavier sur Mac ;
  - si le fichier a changé ailleurs entre-temps (iCloud, Obsidian sur le Mac, autre appareil) :
    jamais d'écrasement silencieux. La version de l'autre est gardée à côté (`NSFileVersion`), avec
    un choix « Garder la mienne / Prendre l'autre / Comparer » (le point 3 sert ici).
- **Où l'éditeur est possible :**
  - les fichiers `.md`, `.markdown` et `.txt` du coffre, d'iCloud Drive et des dossiers choisis ;
  - **pas** les pièces jointes en lecture seule, les rapports distants ni les documents convertis à
    la volée : là, « Enregistrer une copie dans le coffre » d'abord.
- **Créer :**
  - « Nouveau document » dans le coffre (au mois en cours, comme les imports) ;
  - « Dupliquer pour modifier » sur une carte de l'accueil.

**Pour tous** (décidé par Patrick le 13/11/2026 : « Pour tous ») : écrire un document ne demande pas
l'option. Un lecteur Markdown qui ne permet pas de corriger une coquille déçoit. Restent proposés
dans l'option Analytic, sauf avis contraire : l'éditeur de présentations, l'écriture avec l'IA, les
modèles et la comparaison.

**Les essais :**

- un document du coffre annoté : retouches avant, dans et après un passage surligné ; les
  annotations restent, sous la nouvelle clé, sur l'appareil et dans le bloc du fichier ;
- un import PDF avec des images `data:` : rien n'est cassé après dix minutes de frappe ;
- conflit : le même fichier modifié dans TextEdit sur le Mac pendant l'édition sur l'iPad ;
- Duo plié et déplié, clavier matériel sur iPad, Mac.

### 1 bis. L'éditeur de présentations

Le format ne change pas : un document Markdown, des diapositives séparées par `---`, les notes en
commentaire. L'éditeur de présentations est une autre façon de regarder le même fichier.

- **Le plan des diapositives** :
  - la vue d'ensemble du diaporama (déjà là), qui devient modifiable : glisser pour réordonner ;
  - dupliquer, supprimer, masquer (le masquage `okia:masquee` existe), ajouter après.
- **Une diapositive** :
  - à gauche, son Markdown, et seulement le sien ;
  - à droite, son aperçu en 16:9, avec le thème, la marque et la transition du diaporama ;
  - dessous, ses notes de l'orateur (le champ d'aujourd'hui).
- **Des mises en page prêtes**, posées comme du Markdown ordinaire :
  - titre seul, titre et liste, image pleine page, deux colonnes, citation, chiffre clé, carte,
    diagramme ;
  - ce que `presentation.js` sait déjà mettre en page ; il faut les nommer, les proposer, et
    ajouter deux colonnes si le rendu ne le fait pas encore.
- **De l'éditeur au diaporama, sans enregistrer à part** : « Présenter depuis cette diapositive ».
- **La conversion en présentation** (1.3) ouvre son résultat dans l'éditeur, pour retoucher avant de
  l'enregistrer.
- Le découpage est celui de `splitSlides` (`presentation.js`) : un seul découpage, jamais un second
  côté Swift (même règle que pour les notes, voir le commentaire de `avecNote`).

### 1 ter. Écrire avec l'IA de l'appareil

Patrick, 13/11/2026 : « on pourrait utiliser l'ia pour editer les documents. qu'en penses-tu ? »
Oui, à trois règles, celles de la conversion en présentation et des imports :

1. **Sur l'appareil seulement** : le modèle d'Apple Intelligence (Foundation Models), jamais un
   serveur.
2. **L'IA propose, l'auteur décide** : chaque proposition s'affiche en différences (point 3),
   acceptée ou refusée passage par passage. Rien ne remplace le texte sans un geste.
3. **Jamais un fait inventé** : le contrôle de la conversion (`noteVerifiee`, `MoteurRedaction`)
   s'applique. Un chiffre, un nom ou une date absents de la source ou du coffre sont refusés ou
   signalés.

**Pour un document (option Analytic) :**

- **Retoucher une sélection** : plus court, plus clair, plus formel, plus simple, en liste, en
  tableau, corriger l'orthographe.
- **Rédiger depuis des notes** : quelques puces deviennent un paragraphe, sans rien ajouter qui
  n'y soit pas.
- **Les consignes dans le texte** : une ligne `<!-- ia: résumer la section en trois phrases -->`,
  exécutée sur demande. C'est la généralisation de l'import, qui rédige déjà ce que demandent les
  commentaires de relecture. La consigne disparaît une fois la proposition acceptée.
- **Relire** : les répétitions, les phrases trop longues, les incohérences (deux dates pour le même
  fait), les chiffres sans source. Avec la 1.6 (le coffre ouvert, interrogé sur l'appareil) : « ce chiffre ne se trouve
  dans aucun document du coffre ».
- **Titres et chapeau** : proposer un titre, un sous-titre, un résumé d'en-tête.

**Pour une présentation (option Analytic) :**

- un paragraphe devient une diapositive ;
- une diapositive trop chargée se découpe en deux ;
- une liste devient un tableau ou un diagramme Mermaid ;
- les notes de l'orateur se proposent pour la diapositive en cours (la conversion le fait déjà
  pour tout un diaporama).

**Les outils d'écriture du système** (Writing Tools d'Apple) arrivent d'eux-mêmes dans une vue
TextKit 2. À vérifier avant de les laisser actifs :

- qu'ils restent sur l'appareil pour nos usages (relire, réécrire, résumer) ;
- que l'extension ChatGPT d'Apple, réglage du système, ne les fait pas sortir de l'appareil.

Si ce n'est pas garanti, `writingToolsBehavior = .none` dans l'éditeur, et nos propres commandes à
la place. La promesse « pas d'IA distante » passe avant.

**Limites à dire, pas à cacher :**

- le modèle de l'appareil a une petite fenêtre : il travaille section par section, jamais sur un
  long document d'un bloc ;
- sa qualité varie selon les quinze langues : comme aujourd'hui, md Viewer propose une autre langue
  quand Apple Intelligence ne parle pas celle choisie ;
- sans Apple Intelligence (appareil trop ancien, désactivée), les commandes ne s'affichent pas ;
  l'éditeur reste entier.

### 1 quater. Des diagrammes sur demande, depuis une consigne et des données

Patrick, 13/11/2026 : « dans le cadre de l'éditeur de document ou de présentation, on pourra créer
des diagrammes mermaid en donnant des instructions à l'IA et en important des fichiers de
données ». Option Analytic, dans l'éditeur de documents comme dans celui des présentations.

**Le geste :**

- « Insérer un diagramme… » ;
- une consigne : « l'évolution du chiffre d'affaires par trimestre », « les étapes du processus
  décrit dans cette section », « qui dépend de qui » ;
- et, si besoin, une source : un fichier de données (CSV, TSV, Excel, JSON), un tableau du
  document, la sélection, ou la section en cours.

Le diagramme arrive dans l'aperçu ; on le garde, on le retouche par une nouvelle consigne (« en
barres », « seulement 2025 », « en français ») ou à la main dans son bloc ` ```mermaid `. Dans
l'éditeur de présentations, il peut devenir une diapositive à lui seul.

**La règle : le modèle choisit, le code calcule — jamais un chiffre inventé.** Le modèle de l'appareil
est petit et compte mal. Il ne voit donc pas les données entières :

1. md Viewer lit le fichier lui-même : `ImportTableur` sait déjà lire Excel, CSV et TSV ; JSON est
   à ajouter, tableaux d'objets et objets de séries. Il en tire le **schéma** (colonnes, types
   devinés : date, nombre, catégorie) et quelques lignes d'exemple.
2. Le modèle reçoit la consigne, le schéma et l'exemple. Il rend une **spécification**, en sortie
   guidée (`@Generable` de Foundation Models) :
   - le type de diagramme ;
   - les colonnes à prendre ;
   - le regroupement (par mois, par catégorie) et le calcul (somme, moyenne, nombre) ;
   - le filtre, le tri ;
   - le titre et les libellés.
3. Le **code Swift** applique la spécification à toutes les lignes : il regroupe, calcule, trie,
   puis écrit le Mermaid (`xychart-beta` en barres ou en courbes, `pie`, `gantt`,
   `quadrantChart`, `sankey-beta`…). Les chiffres du diagramme viennent du fichier, au calcul
   près.
4. Sous le diagramme, une ligne discrète dit d'où il vient (« données : ventes-2025.xlsx, feuille
   T4, somme de Montant par Mois »), pour qu'on puisse vérifier.

**Les diagrammes de structure** (organigramme, séquence, états, carte mentale, frise `timeline`,
relations entre entités) se tirent d'un texte, pas d'un tableau. Là, le modèle écrit lui-même le
Mermaid, section par section, avec le contrôle des inventions : chaque libellé doit se trouver dans
le texte source, ou être signalé.

**Valider avant de montrer :**

- le Mermaid passe par `mermaid.parse` dans la vue web avant d'être proposé ;
- en cas d'erreur, le message repart au modèle, deux essais au plus ;
- les réparations connues s'appliquent (`reparerXychart`, les dates sans guillemets) ;
- jamais un bloc cassé dans le document.

**À ne pas confondre avec « Un tableau devient un graphique » (pour tous)** : ce point est sans IA,
un geste sur un tableau déjà dans le document, en barres ou en courbes. Les deux partagent le même
code de calcul et d'écriture Mermaid (étape 3) ; on le fait une fois.

**Limites :**

- au-delà de 50 000 lignes, un échantillon, et le diagramme le dit ;
- un fichier Numbers passe par l'export CSV ou Excel (TACHES-1.6.md : on ne lit pas ses
  cellules) ;
- sans Apple Intelligence, la commande ne s'affiche pas ; le graphique d'un tableau reste.

**Les essais :**

- un classeur Excel de ventes ;
- un CSV d'export bancaire, avec des dates au format suisse et des montants à virgule ;
- un JSON d'API ;
- la consigne « organigramme » sur une section de rapport fornews ;
- vérifier chaque chiffre du diagramme contre un calcul fait à la main dans Numbers.

### 2. Partir d'un modèle

« Nouveau » propose des modèles :

- document vide ;
- compte rendu de réunion ;
- fiche de lecture ;
- note de veille, à la manière de fornews ;
- diaporama (titre, plan, trois parties, conclusion) ;
- diaporama de rapport.

Les modèles sont des fichiers Markdown livrés avec l'app. On en ajoute à soi en mettant un document
dans un dossier « Modèles » du coffre. Rangé dans le coffre au mois en cours.

### 3. Comparer deux versions

- Les différences entre deux documents, ou entre un document et une version précédente : versions
  d'iCloud (`NSFileVersion`), copie gardée lors d'un conflit (point 1).
- Diff par paragraphe, puis par mot dans un paragraphe changé ; ajouts en vert, retraits barrés, en
  texte rendu, pas en Markdown brut.
- Les fenêtres côte à côte existent déjà (Mac, iPad) ; il manque le calcul et la vue.

---

## 1.8 — Le coffre qui veille

### 4. Étiquettes et collections

- Les étiquettes vivent dans l'en-tête YAML (`tags: [veille, ia]`), le format d'Obsidian : tout
  éditeur les lit.
- Les poser :
  - depuis l'éditeur (feuille « Propriétés ») ;
  - sans éditeur, depuis le menu d'une carte (même écriture coordonnée).
- Le coffre filtre par étiquette. Une collection est une recherche enregistrée : étiquettes, mots,
  entité, période.

### 5. Les liens entre documents

- `[[Titre du document]]` et `[[Titre|texte affiché]]`, comme Obsidian, résolus par nom de fichier
  dans le coffre ; les liens Markdown ordinaires vers un `.md` du coffre aussi.
- En bas de chaque document, « Cité dans » : les rétroliens, depuis l'index du coffre.
- Dans l'analyse du coffre, une vue « Liens » : le graphe des documents.

### 6. Surveiller un nom

- Sur la fiche d'une entité, ou depuis une recherche : « Me prévenir ». Le nom est gardé dans le
  stockage clé-valeur d'iCloud, comme l'emplacement du coffre : le même sur tous les appareils.
- À chaque relecture du coffre, y compris en arrière-plan (`BGAppRefreshTask` sur iOS, la
  relecture périodique sur Mac) : un nouveau document qui le mentionne déclenche une notification
  locale. Rien ne sort de l'appareil.
- Le point de la semaine (1.5) les met en tête.

### 7. La frise chronologique

- Les dates des documents (« le 12 mars 2026 », « en 2019 », « hier » rapporté à la date du
  document), via `NSDataDetector` et `NLTagger`, reliées aux entités de la même phrase.
- Une quatrième vue de l'analyse du coffre, à côté de la semaine, de la liste, de la galerie et de
  la carte ; et une frise par entité sur sa fiche.
- Chaque point de la frise cite sa phrase et ouvre son document à cet endroit.

### 8. Le réseau des entités

- Qui apparaît avec qui : l'analyse le calcule déjà, sans le dessiner. Un graphe des
  co-occurrences : épaisseur d'un lien selon le nombre de documents partagés, couleur selon le
  genre.
- Toucher un lien : les documents où les deux noms se croisent.
- Dessin en JavaScript dans la vue web (comme la carte), placé hors du fil principal ; au-delà de
  200 nœuds, seuls les plus cités.

---

## 1.9 — De nouvelles sources

### 9. L'audio

- Importer un enregistrement (Dictaphone, réunion, podcast téléchargé) : transcription sur
  l'appareil (framework Speech, `SpeechAnalyzer` d'iOS 26), dans la langue choisie, horodatée.
- Le document obtenu suit le chemin des autres imports : entités, résumé et rapport d'analyse
  proposés (jamais cochés d'avance), rangé dans le coffre.
- Chaque paragraphe garde son temps : le toucher rejoue le passage. Le fichier audio est copié à
  côté du document.
- À vérifier : les langues que `SpeechAnalyzer` couvre hors ligne, et la durée de transcription
  d'une heure d'audio sur l'iPhone.

### 10. EPUB et e-mails

- EPUB : un livre (sans DRM) devient un document Markdown, chapitre par chapitre, avec ses images,
  ouvert dans le mode livre (1.3).
- E-mails `.eml`, par « Ouvrir avec » depuis Mail ou Fichiers : l'en-tête (de, à, date, objet) dans
  le YAML, le corps en Markdown, les pièces jointes Word, PDF et PowerPoint importées et liées.

---

## 2.0 — Présenter partout

### 11. L'Apple Watch en télécommande

- Une app de montre : suivante et précédente (couronne ou toucher), le chronomètre, le rang.
- Une vibration quand une diapositive dépasse le temps prévu à la répétition (1.5).
- Par l'iPhone (`WatchConnectivity`), qui relaie à la télécommande d'aujourd'hui : pas de second
  protocole.

### 12. Présenter à distance par SharePlay

- Pendant un appel FaceTime : « Présenter avec SharePlay ». Chaque participant qui a md Viewer voit
  la diapositive en direct, le pointeur et les dessins compris. Les autres reçoivent la photo de la
  diapositive, comme la télécommande.
- `GroupActivities` : les données passent par FaceTime, pas par un serveur de l'éditeur.
- À vérifier : une app tierce peut-elle rejoindre sans l'avoir ? Sinon, la photo seule.

### 13. Le diaporama traduit pour le public

- Au lancement, « Langue du public » : l'écran du public (second écran, AirPlay, SharePlay) montre
  les diapositives traduites ; le présentateur garde les siennes et ses notes.
- Le framework Translation de la 1.2, sur l'appareil, diapositive par diapositive à l'avance. La
  traduction est gardée avec le document pour les fois suivantes.

### 14. Vidéo et page web autonome

- **Vidéo** : la répétition (1.5) enregistrée avec la voix du micro, les dessins et le pointeur ;
  export `.mp4` en 1080p (`AVAssetWriter`).
- **Page web autonome** : le diaporama en un seul fichier `.html`, images, thème et transitions
  compris. Il s'ouvre dans n'importe quel navigateur, Windows et Linux compris, sans md Viewer ;
  `presentation.js` est déjà autonome dans la vue web.

---

## Pour tous, au fil des versions

### 15. Des descriptions pour VoiceOver

- Les images sans texte de remplacement en reçoivent un, calculé sur l'appareil (Vision pour la
  scène, le modèle de l'appareil pour la phrase) ; gardé, jamais écrit dans le fichier sans
  accord.
- Les diagrammes Mermaid : une description tirée de leur source (« organigramme : A mène à B, puis
  à C ou D »).
- Les diapositives suivent la taille du texte du système en lecture, pas en présentation.
- Revue VoiceOver de tout le parcours : accueil, lecteur, diaporama, télécommande, analyse.

À tenir avec ce qui est déjà annoncé pour tous : le graphique d'un tableau, la lecture à voix
haute, les widgets (TACHES-1.6.md).

---

## À décider par Patrick

- La répartition ci-dessus, et l'ordre : l'éditeur d'abord ?
- ~~Écrire un document : pour tous, ou dans l'option Analytic ?~~ **Pour tous** (13/11/2026).
- Les outils d'écriture du système : les laisser actifs (après vérification) ou les remplacer par
  nos seules commandes ?
- La 2.0 : un nouveau numéro majeur pour « Présenter partout », ou continuer en 1.x ?
- Annoncer ou non ces versions sur la feuille de route publique, et quand.
