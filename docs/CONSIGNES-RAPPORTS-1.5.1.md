# Consignes de format pour les rapports générés (md Viewer 1.5.1)

Rédigé le 26/11/2026, à la demande de Patrick : « quelles instructions donner [aux tâches
planifiées Claude qui génèrent des rapports] pour qu'il travaille avec les nouvelles possibilités
et les illustrations SVG ».

## Où les coller

À la fin du prompt de chaque routine qui produit un rapport pour md Viewer. Les deux routines de
veille actuelles vivent dans Cowork : « Rapport de veille fornews — IA quotidien » et « Veille
hebdomadaire espace et environnement ». **C'est Patrick qui modifie leur prompt, dans Cowork** :
Cowork régénère toute la configuration à chaque modification, et l'API RemoteTrigger ne met à jour
qu'en renvoyant tout `job_config` (environ 160 Ko). Ne pas les modifier par l'API.

Modèle complet à montrer à une routine : `store/illustration-1.5.1/glaciers-alpins.md` (formules,
diagrammes, carte, schémas SVG, encadrés).

## Le bloc à coller

````text
## Format de sortie pour md Viewer (1.5.1)

Le rapport est un seul fichier Markdown, lu dans md Viewer. En plus du Markdown habituel :

FORMULES
- Une formule seulement quand le sujet l'exige (taux, croissance, physique, statistique).
- Dans la ligne : $…$, sans espace juste après le $ ouvrant ni juste avant le $ fermant.
- En bloc : $$ sur une ligne, la formule, $$ sur la ligne suivante.
- Syntaxe LaTeX standard (KaTeX) : \frac, \sum, \int, \sqrt, indices _ et exposants ^.
- Les montants restent du texte : écris « 5 $ », « 10 USD » ou « 5 francs », jamais $5$.

DIAGRAMMES (blocs ```mermaid)
- flowchart, sequence, gantt, pie, mindmap, timeline ou xychart-beta.
- 8 éléments au plus, libellés courts, sans parenthèses ni deux-points dans les libellés.
- xychart-beta : chaque étiquette de x-axis entre guillemets, ["Jan", "Fév", "Mar"].
- Seulement avec des chiffres tirés des sources. Pas de chiffre : pas de graphique.

CARTES (blocs ```leaflet)
- Une ligne id: nom-de-la-carte, puis une ligne par lieu :
  marker: latitude, longitude, [[Nom du lieu]]
- Coordonnées vérifiées, 3 décimales. La carte se cadre toute seule.

ILLUSTRATIONS SVG
- Une à quatre illustrations qui expliquent quelque chose : un mécanisme, une comparaison, un
  schéma de principe. Pas de décor.
- Format : SVG 1600×900 (viewBox="0 0 1600 900"), fond clair #F7F5F0, traits #111111,
  accent orange #E8972E, gris #6B6B63, police -apple-system, textes en français, gros et courts.
- Chaque SVG est encodé en base64 et rangé en fin de fichier, en image de référence :
  dans le texte : ![Description complète de l'image, pour la lecture vocale][svg-nom]
  en fin de fichier : [svg-nom]: data:image/svg+xml;base64,PHN2Zy…
- Encode avec un script (Python : base64.b64encode(svg.encode()).decode()), jamais à la main.
- Pas de chiffre ni de distance inventés dans un dessin : un schéma sans données porte la
  mention « schéma sans échelle ».

ENCADRÉS ET LIENS
- Points clés dans > [!info], > [!tip], > [!warning] ou > [!note].
- Personnes, organisations et lieux importants en wiki-liens : [[Nom]].

RÈGLES
- N'invente ni chiffre, ni date, ni source : ce qui manque est dit.
- Avant de livrer, vérifie que chaque formule, chaque bloc mermaid et chaque bloc leaflet est
  fermé, et que chaque image [svg-…] a sa référence en fin de fichier.
````

## Pourquoi ces choix

- **Les SVG en base64, en fin de fichier** : la forme de la présentation de la fondue. Elle passe
  dans l'app, dans le lecteur en ligne et dans les exports Word, PowerPoint et ePub. Un `<svg>` en
  clair dans le texte déborde s'il n'a pas `width="100%"` (aucune règle CSS ne le borne).
- **La description de l'image** est ce que lit VoiceOver.
- **Les guillemets sur `x-axis`** : md Viewer répare leur absence (`reparerXychart` dans
  `render.js`, build 158), mais un fichier propre passe aussi ailleurs.
- **Les montants** : la règle « un prix reste un prix » de `render.js` protège « 5 $ » et
  « $5 et $10 » (pas d'espace juste après le `$` ouvrant ni avant le fermant, pas de chiffre
  juste après le fermant, comme GitHub), mais pas « $5$ ».
- **Pas de chiffre inventé** : la règle des prompts existants, étendue aux graphiques et aux
  dessins.
