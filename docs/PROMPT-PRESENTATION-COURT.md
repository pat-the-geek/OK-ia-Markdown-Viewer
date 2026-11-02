# Prompt court — une présentation pour md Viewer, avec Siri

Version courte du [prompt de présentation](PROMPT-PRESENTATION-SVG.md), pour le Siri d'iOS 27 et
tout assistant qui refuse un long message ou n'exécute pas de code. Le prompt complet fait près de
16 000 caractères : une première version courte de 4 000 caractères n'est pas passée dans Siri,
celle-ci oui (1 500 caractères environ, 2 500 avec quatre photos).

Ce qu'elle laisse de côté : cartes, diagrammes, encodage des SVG en base64 (ils restent en clair,
md Viewer les affiche tels quels) et la séparation partie A / partie B qui protège des consignes
cachées dans les documents. Les photos sont fournies par l'utilisateur : un assistant qui ne vérifie
pas ses liens invente des adresses ou n'en met aucune.

---

````text
Crée une présentation de 10 diapositives au format Markdown pour l'app md Viewer.

Sujet : (votre sujet en une ou deux phrases)

Règles :
- Commence par :
---
title: (le titre)
type: presentation
lang: fr
---
- Sépare les diapositives par une ligne qui ne contient que ---
- Une idée par diapositive, 30 mots au plus, un titre ## qui affirme.
- Ajoute à la fin de chaque diapositive une note pour l'orateur : <!-- une phrase -->
- N'invente aucun chiffre. Termine par une diapositive « Sources et crédits ».
- Livre tout le fichier dans un seul bloc de code markdown.

Illustrations : 4 dessins SVG, dont la couverture, de vraies illustrations et pas des schémas.
- Des scènes riches : 25 à 40 formes, plusieurs plans (fond, milieu, premier plan), des dégradés (linearGradient), des ombres en formes semi-transparentes, des objets reconnaissables du sujet.
- La même palette de 5 couleurs pour tous les dessins.
- Chaque SVG en clair dans la diapositive, sans ligne vide à l'intérieur, et qui commence par :
<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 1600 900" role="img" aria-label="description">
- Un fond plein, du texte de 48 px au moins, 8 mots au plus par dessin.

Photos : utilise ces photos libres, une par diapositive, chacune suivie de sa légende sur une ligne.
(collez ici vos photos, deux lignes par photo :
![description](https://upload.wikimedia.org/…/image.jpg)
> Légende · Auteur · Licence)
N'ajoute aucune autre photo, sauf une adresse upload.wikimedia.org que tu as réellement trouvée.
````

## Exemple : la fondue

Le prompt essayé dans Siri le 2 novembre 2026, avec quatre photos de Wikimedia Commons choisies à
l'avance.

````text
Crée une présentation de 10 diapositives au format Markdown pour l'app md Viewer.

Sujet : la fondue au fromage en Suisse, le vacherin et la moitié-moitié : histoire, régions, accompagnements, nouvelles recettes.

Règles :
- Commence par :
---
title: (le titre)
type: presentation
lang: fr
---
- Sépare les diapositives par une ligne qui ne contient que ---
- Une idée par diapositive, 30 mots au plus, un titre ## qui affirme.
- Ajoute à la fin de chaque diapositive une note pour l'orateur : <!-- une phrase -->
- N'invente aucun chiffre. Termine par une diapositive « Sources et crédits ».
- Livre tout le fichier dans un seul bloc de code markdown.

Illustrations : 4 dessins SVG, dont la couverture, de vraies illustrations et pas des schémas.
- Des scènes riches : 25 à 40 formes, plusieurs plans (ciel, montagnes, premier plan), des dégradés (linearGradient), des ombres en formes semi-transparentes, des objets reconnaissables (caquelon, réchaud, fourchettes, pain, fromages).
- La même palette de 5 couleurs pour tous les dessins.
- Chaque SVG en clair dans la diapositive, sans ligne vide à l'intérieur, et qui commence par :
<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 1600 900" role="img" aria-label="description">
- Un fond plein, du texte de 48 px au moins, 8 mots au plus par dessin.

Photos : utilise ces 4 photos libres, une par diapositive, chacune suivie de sa légende sur une ligne.
![Fondue servie à Genève](https://upload.wikimedia.org/wikipedia/commons/thumb/6/6a/Swiss_cheese_fondue.JPG/1280px-Swiss_cheese_fondue.JPG)
> Genève · Brücke-Osteuropa · CC0
![Vacherin Fribourgeois AOP](https://upload.wikimedia.org/wikipedia/commons/thumb/c/c9/Vacherin_Fribourgeois_Rustic_1.JPG/1280px-Vacherin_Fribourgeois_Rustic_1.JPG)
> Vacherin Fribourgeois AOP · Guy Waterval · Apache 2.0
![Château de Gruyères](https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/12_Chateau_de_Gruy%C3%A8res_Photo_by_Giles_Laurent.jpg/1280px-12_Chateau_de_Gruy%C3%A8res_Photo_by_Giles_Laurent.jpg)
> Château de Gruyères · Giles Laurent · CC BY-SA 4.0
![La religieuse au fond du caquelon](https://upload.wikimedia.org/wikipedia/commons/thumb/2/20/Religieuse_-_Fondue_au_fromage.jpg/1280px-Religieuse_-_Fondue_au_fromage.jpg)
> La religieuse · Rudolf H. Boettcher · CC BY-SA 4.0
N'ajoute aucune autre photo, sauf une adresse upload.wikimedia.org que tu as réellement trouvée.
````

## Ce qui a été vérifié (2 novembre 2026)

- Siri : le prompt de la fondue passe et donne une présentation qui s'ouvre dans md Viewer, meilleure
  qu'un premier essai qui demandait des dessins « simples » et ne fournissait pas de photos (celui-là
  n'en avait aucune, et des illustrations pauvres).
- `width="100%"` sans `height` : dans le lecteur en ligne, le SVG en clair remplit la largeur, en
  lecture comme en diaporama. Avec `width="1600" height="900"`, il gardait 1 600 px et sortait de la
  page (même CSS dans l'app : aucune règle ne limite la largeur d'un `<svg>` en clair).
- Le diagramme Mermaid `timeline` sort minuscule en diaporama : la version courte n'en demande pas.
