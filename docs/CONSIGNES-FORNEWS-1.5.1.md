# Consignes pour fornews : les nouvelles possibilités de md Viewer 1.5.1 dans les rapports

Rédigé le 26/11/2026, à la demande de Patrick : « donner les instructions à fornews pour ajouter
les nouvelles possibilités de md Viewer dans les rapports : illustrations SVG, formules math et
autres ».

Ce document s'adresse à qui travaille sur `fornews.ai`. md Viewer ne modifie pas fornews : il dit
ce que le lecteur sait afficher et la forme à produire, et fornews décide quand l'appliquer.

Pour les routines Cowork, qui écrivent tout le rapport avec Claude, voir plutôt
`docs/CONSIGNES-RAPPORTS-1.5.1.md`. Le modèle complet d'un rapport qui utilise tout est
`store/illustration-1.5.1/glaciers-alpins.md`, également lisible en ligne :
<https://ok-ia.ch/rapport.html?doc=/mdviewer/exemples/rapport-glaciers-alpins.md>

## 1. Ce qui change pour fornews

Dans fornews, **c'est le code qui assemble les rapports**. `CompositeurRapportAnalyste`,
`RapportHistoire`, `DossierEntite`, `RapportObsidian`, `BriefingRendu` et `PresentationAnalyste`
posent les blocs `mermaid` et `leaflet`, le HTML à styles en ligne et les images en base64. Le
modèle de l'appareil (8 k jetons) n'écrit que la prose.

Les consignes ci-dessous visent donc **les compositeurs**, pas le prompt. Ne pas demander au modèle
de l'appareil d'écrire du LaTeX ni du SVG : il en écrirait de faux, et la règle de fornews veut
qu'aucune illustration ne vaille mieux qu'une illustration fausse.

md Viewer 1.5.1 est en test (TestFlight, build 190). La version en vente, la 1.4, affiche
`$…$` tel quel et montre déjà les images SVG en base64.

## 2. D'abord, protéger les dollars (indispensable dès la 1.5.1)

md Viewer lit maintenant `$…$` comme une formule. Il protège les prix, à la manière de GitHub :
pas d'espace juste après le `$` ouvrant ni juste avant le `$` fermant, et pas de chiffre juste
après le fermant. Mais les textes d'actualité contiennent des dollars partout. Tests faits au
moteur de rendu le 26/11/2026 :

| Texte dans le rapport | Résultat dans md Viewer 1.5.1 |
|---|---|
| `Le titre vaut $5 et $10 demain.` | texte, correct |
| `Entre $5M et $10M.` | texte, correct |
| `de $20 à $30 par baril` | texte, correct |
| `Prix: $3.50/$4.00` | texte, correct |
| `1,2 milliard ($1.2bn)` | texte, correct |
| `$AAPL,$TSLA montent` | **devient une formule** (les symboles boursiers collés) |
| `\$AAPL,\$TSLA montent` | texte, correct : le `\` disparaît à l'affichage |
| `<p style="…">HTML $a,$b</p>` | texte, correct : rien n'est interprété dans un bloc HTML |

**Règle :** dans toute la prose Markdown que fornews écrit (titres, résumés, citations, légendes,
cellules de tableau Markdown), remplacer chaque `$` par `\$`. Ce remplacement s'applique **hors**
des blocs de code (```` ``` ````), **hors** des blocs HTML (où un `\$` resterait visible, et où le
`$` ne risque rien) et **hors** des formules que fornews pose lui-même.

`\$` est du Markdown standard : Obsidian, GitHub et un navigateur qui passe par `marked`
l'affichent `$`. C'est donc sans risque pour les documents qui doivent aussi se lire hors de
md Viewer.

## 3. Les formules mathématiques

**Syntaxe (KaTeX, sortie MathML, sans rien charger du web) :**
- dans la ligne : `$\frac{a}{b}$`, sans espace juste après le `$` ouvrant ni juste avant le `$`
  fermant ;
- en bloc : `$$` seul sur sa ligne, la formule, puis `$$` seul sur la ligne suivante ;
- ou un bloc ```` ```math ````.

Une formule fausse s'affiche en source, avec l'erreur en info-bulle : rien ne casse.

**Où, dans fornews :** très peu d'endroits, et seulement quand le code connaît la formule qu'il
applique. Par exemple, la note de méthode (`> [!info]` de `CompositeurRapportAnalyste`) qui
explique un indicateur calculé : variation de couverture, part d'une source, moyenne glissante. La
formule y est écrite par le code, jamais par le modèle.

**Où, nulle part :** dans `BriefingRendu`. Le briefing doit se lire tel quel dans un navigateur
(décision de Patrick du 04/10/2026), où `$…$` resterait en source.

## 4. Les illustrations SVG

C'est la nouveauté la plus utile pour fornews. Un schéma vectoriel, calculé par le code à partir de
données que fornews possède déjà, se lit net à toutes les tailles, en clair comme en sombre, et
passe partout.

**La forme à produire** (la même que le rapport des glaciers et la présentation de la fondue) :

```markdown
![Description complète de l'image, pour VoiceOver, dans la langue du rapport][svg-sources]

…le reste du rapport…

[svg-sources]: data:image/svg+xml;base64,PHN2ZyB4bWxucz0i…
```

- L'image est une **référence**, et sa définition va **en fin de fichier**. Le texte reste lisible
  dans un éditeur, et une ligne de 30 Ko ne coupe pas le rapport en deux.
- Encodage : `Data(svg.utf8).base64EncodedString()`, jamais une chaîne SVG en clair dans le
  Markdown. Un `<svg>` en clair dans le texte déborde s'il n'a pas `width="100%"`, et une ligne
  vide à l'intérieur fermerait le bloc HTML.
- `viewBox="0 0 1600 900"` avec `width` et `height`, fond `#F7F5F0`, traits `#111111`, accent
  `#E8972E`, gris `#6B6B63`, police `-apple-system, Helvetica, Arial, sans-serif`. Textes gros et
  courts, **dans la langue du rapport** (les 15 langues de fornews : passer par les libellés
  existants, comme `RapportObsidian.labels`).
- Le texte du SVG est échappé (`&`, `<`, `>`) : un nom d'entité comme « AT&T » casserait l'image.
- **Aucun chiffre inventé.** Un dessin ne montre que des valeurs calculées. Un schéma de principe
  sans données porte la mention « schéma sans échelle ».
- De une à quatre illustrations par rapport, et seulement quand elles expliquent quelque chose.

**Ce que md Viewer en fait :** il les affiche dans le lecteur, le livre, le diaporama et le lecteur
en ligne d'ok-ia.ch. Il les convertit en image dans ses exports Word, PowerPoint, ePub et PDF, et
les agrandit au toucher. Un navigateur les affiche aussi.

**Idées pour fornews**, toutes à partir de données déjà calculées :
- **Revue de presse / rapport d'analyste :** qui couvre le sujet. Une barre par source, avec le
  nombre d'articles. Mermaid `pie` le fait déjà, mais sans place pour les noms longs.
- **Histoire / dossier d'entité :** une carte des relations. L'entité au centre, les entités
  co-citées autour, l'épaisseur du trait selon le nombre d'articles communs. Elle remplace le
  `flowchart` qui devient illisible au-delà de huit nœuds.
- **Chiffres clés d'une histoire** (`ChiffresClesHistoire`) : un bandeau de trois à cinq chiffres
  tirés des articles, chacun avec sa source en petit.
- **Rythme de couverture** (`RythmeCouverture`) : une courbe d'articles par jour, avec les pics
  annotés du titre de l'article déclencheur.

## 5. Les autres possibilités utiles

- **Diagrammes Mermaid** : `flowchart`, `sequence`, `gantt`, `pie`, `mindmap`, `timeline`,
  `xychart-beta`. Dans `xychart-beta`, chaque étiquette de `x-axis` va entre guillemets
  (`["Lun", "Mar"]`). md Viewer répare leur absence depuis le build 158, mais un fichier propre
  passe aussi ailleurs. Huit éléments au plus, et pas de parenthèses ni de deux-points dans les
  libellés.
- **Cartes** : bloc ```` ```leaflet ```` avec `id:` et une ligne `marker: lat, lon, [[Nom]]` par lieu.
  md Viewer cadre la carte tout seul. La carte en PNG base64 de `RapportObsidian` reste la bonne
  forme pour Obsidian.
- **Encadrés** `> [!info]`, `> [!tip]`, `> [!warning]`, `> [!note]` et **wiki-liens** `[[Nom]]` :
  partout sauf dans le briefing (même raison que les formules).
- **Présentations** (`PresentationAnalyste`) :
  - **Notes de l'orateur** : un commentaire HTML dans la diapositive, `<!-- deux phrases à dire -->`.
    md Viewer les montre en mode présentateur et sur la télécommande, et les met dans le
    PowerPoint. Les commentaires qui commencent par `okia:` ou `fornews:` restent des marques
    internes, pas des notes.
  - **Diapositive masquée** : `<!-- okia:masquee -->` la garde dans le fichier sans la montrer.
  - Les images SVG ci-dessus valent aussi pour les diapositives : une par diapositive, seule.
  - Rappel : une ligne `---` dans un rapport fait passer md Viewer en diaporama. Elle reste interdite
    hors des présentations.

## 6. Chez fornews : le moteur de rendu copié

`FornewsCore/Sources/FornewsFeatures/Export/MoteurMdViewer/render.js` est une copie de celui de
md Viewer, prise le 04/10/2026. Il lui manque environ 1 100 lignes, dont :
- `formule` (KaTeX, avec le fichier `vendor` de KaTeX) ;
- `blocSVG` et `estSVG` (SVG dans les exports) ;
- `reparerXychart` et `ganttSansAujourdhuiLointain` ;
- `tableauxDefilants`.

Conséquence : tant que la copie n'est pas reprise, un rapport avec formules s'affiche **en source
dans fornews** et correctement dans md Viewer. Les images SVG s'affichent dans fornews, mais ses
exports Word et PowerPoint ne les convertissent pas forcément : à vérifier sur un export.

Patrick a reporté la reprise des diffs de `render.js` à **fornews 2.0** (décision du 29/10/2026).
D'ici là :
1. Protéger les dollars (§ 2) : c'est utile tout de suite, sans dépendre du moteur.
2. Les illustrations SVG (§ 4) peuvent venir avant 2.0 : vérifier seulement l'export de fornews.
3. Les formules (§ 3) attendent la reprise du moteur, ou ne vont que dans les rapports destinés
   à md Viewer.

Sens de copie : md Viewer est l'original. Reprendre ses `git show` hunk par hunk, jamais le
fichier entier par-dessus celui de fornews.
