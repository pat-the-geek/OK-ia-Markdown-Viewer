# Prompt mini — une présentation pour md Viewer, avec Siri

Version courte du [prompt pro max](PROMPT-PRESENTATION-SVG.md), pour le Siri d'iOS 27 et tout
assistant qui refuse un long message ou n'exécute pas de code. Le prompt pro max fait près de
16 000 caractères ; Siri a refusé un message de 4 000 caractères et accepté celui de la fondue
(environ 3 650).

L'utilisateur fournit les faits et les photos : sans faits, Siri écrit de mémoire et se trompe ;
il ne trouve pas de photos seul. Le prompt mini laisse de côté les cartes, les diagrammes, l'encodage
des SVG en base64 (ils restent en clair, md Viewer les affiche tels quels) et la séparation partie A
/ partie B qui protège des consignes cachées dans les documents.

---

````text
Crée une présentation de 11 diapositives au format Markdown pour l'app md Viewer.

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
- Une ligne vide entre chaque élément : titre, texte, image ou SVG, légende, note.
- Diapositive 1 : la couverture, un SVG seul avec le titre dessiné dedans.
- À la fin de chaque diapositive, une note pour l'orateur, tirée des faits : <!-- une phrase -->
- Utilise tous les faits ci-dessous et aucun autre. Termine par « Sources et crédits » : ces sources et les photos.
- Livre tout le fichier dans un seul bloc de code markdown.

Faits :
(collez ici vos faits, un par ligne, chacun avec sa source :
- Le fait, le chiffre ou la date (source))

Illustrations : 4 dessins SVG, dont la couverture, de vraies illustrations et pas des schémas.
- Des scènes riches : 25 à 40 formes, plusieurs plans (fond, milieu, premier plan), des dégradés (linearGradient), des ombres en formes semi-transparentes, des objets reconnaissables du sujet.
- La même palette de 5 couleurs pour tous les dessins.
- Chaque SVG en clair dans la diapositive, sans ligne vide à l'intérieur, et qui commence par :
<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 1600 900" role="img" aria-label="description">
- Un fond plein, du texte de 48 px au moins, 8 mots au plus par dessin.

Photos : ces photos, une par diapositive, chacune suivie de sa légende.
(collez ici jusqu'à 6 photos, deux lignes par photo :
![description](https://commons.wikimedia.org/wiki/Special:FilePath/Nom_du_fichier.jpg?width=1280)
> Légende · Auteur · Licence)
````

## Exemple : la fondue

Le prompt essayé dans Siri le 2 novembre 2026 (cinquième essai), avec neuf faits sourcés, tirés de
la version longue de l'exemple, et six photos de Wikimedia Commons choisies à l'avance.

````text
Crée une présentation de 11 diapositives au format Markdown pour l'app md Viewer.

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
- Une ligne vide entre chaque élément : titre, texte, image ou SVG, légende, note.
- Diapositive 1 : la couverture, un SVG seul avec le titre dessiné dedans.
- À la fin de chaque diapositive, une note pour l'orateur, tirée des faits : <!-- une phrase -->
- Utilise tous les faits ci-dessous et aucun autre. Termine par « Sources et crédits » : ces sources et les photos.
- Livre tout le fichier dans un seul bloc de code markdown.

Faits :
- Plus ancienne recette proche : Zurich, 1699 (Wikipédia).
- Presque inconnue dans la plupart des régions jusqu'au milieu du XXe siècle ; l'Union suisse du fromage en fait le plat national, l'armée l'adopte dans les années 1950 (Swissinfo, 2022).
- Moitié-moitié : moitié Gruyère AOP, moitié Vacherin Fribourgeois AOP, au vin blanc, servie chaude (Région de Fribourg).
- Vacherin pur : à l'eau, sans vin, servie tiède, avec pain et pommes de terre (Terroir Fribourg).
- Gruyère AOP : Fribourg, Vaud, Neuchâtel, Jura, Jura bernois ; 5 mois d'affinage au moins (Wikipédia).
- Neuchâteloise : Gruyère et Emmental ; valaisanne : avec fromage à raclette ; Suisse orientale : Appenzeller et cidre (Wikipédia).
- La religieuse : la croûte grillée au fond du caquelon.
- Avec du thé, l'estomac se vide plus vite qu'avec du vin, mais les malaises sont les mêmes (BMJ, 2010).
- Nouveautés : au whisky (Gault&Millau), napolitaine aux fusilli et tomate (Fooby), train et bateau fondue en Gruyère (Région de Fribourg).

Illustrations : 4 dessins SVG, dont la couverture, de vraies illustrations et pas des schémas.
- Des scènes riches : 25 à 40 formes, plusieurs plans (ciel, montagnes, premier plan), des dégradés (linearGradient), des ombres en formes semi-transparentes, des objets reconnaissables (caquelon, réchaud, fourchettes, pain, fromages).
- La même palette de 5 couleurs pour tous les dessins.
- Chaque SVG en clair dans la diapositive, sans ligne vide à l'intérieur, et qui commence par :
<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 1600 900" role="img" aria-label="description">
- Un fond plein, du texte de 48 px au moins, 8 mots au plus par dessin.

Photos : ces 6 photos, une par diapositive, chacune suivie de sa légende.
![Fondue à Genève](https://commons.wikimedia.org/wiki/Special:FilePath/Swiss_cheese_fondue.JPG?width=1280)
> Genève · Brücke-Osteuropa · CC0
![Enseigne de fondue à Genève](https://commons.wikimedia.org/wiki/Special:FilePath/Fondue_au_fromage.jpg?width=1280)
> Genève · BiiJii · CC0
![Vacherin Fribourgeois AOP](https://commons.wikimedia.org/wiki/Special:FilePath/Vacherin_Fribourgeois_Rustic_1.JPG?width=1280)
> Vacherin Fribourgeois · Guy Waterval · Apache 2.0
![Cave d'affinage du Gruyère](https://commons.wikimedia.org/wiki/Special:FilePath/Fromagerie_gruy%C3%A8res-affinage.jpg?width=1280)
> Cave d'affinage, Gruyères · SuperManu · CC BY-SA 3.0
![Château de Gruyères](https://commons.wikimedia.org/wiki/Special:FilePath/12_Chateau_de_Gruy%C3%A8res_Photo_by_Giles_Laurent.jpg?width=1280)
> Château de Gruyères · Giles Laurent · CC BY-SA 4.0
![La religieuse au fond du caquelon](https://commons.wikimedia.org/wiki/Special:FilePath/Religieuse_-_Fondue_au_fromage.jpg?width=1280)
> La religieuse · Rudolf H. Boettcher · CC BY-SA 4.0
````

## Ce que cinq essais dans Siri ont montré (2 novembre 2026)

1. Prompt de 4 000 caractères : refusé. Prompts de 950 à 3 650 caractères : acceptés.
2. Sans faits fournis, Siri écrit de mémoire : « le vin blanc facilite la digestion » (l'étude du
   BMJ de 2010 dit le contraire pour la vidange de l'estomac), une « histoire de conservation » sans
   source, un Gruyère produit « dans la région de la Gruyère » seulement. Avec les faits, il s'y
   tient, les utilise tous quand on le demande, mais ajoute encore des détails dans les notes
   (« plus digeste », « découverte à Zurich »).
3. Sans photos fournies, aucune photo. Fournies, il les place toutes, avec leur légende.
4. Les dessins restent des formes simples (cercles, rectangles, un dégradé), même quand on demande
   des scènes riches ; ils varient d'un essai à l'autre. La consigne détaillée (« de vraies
   illustrations et pas des schémas », les plans nommés, une palette) donne un peu mieux qu'une
   consigne courte.
5. Sans la règle des lignes vides, Siri colle les éléments : le texte qui suit une photo entre dans
   sa légende, celui qui suit un SVG s'affiche en tout petit. Sans « diapositive 1 : la
   couverture », pas de couverture.

Vérifié dans le lecteur en ligne : `width="100%"` sans `height` fait remplir la largeur au SVG en
clair (avec `width="1600" height="900"`, il garde 1 600 px et déborde) ; les adresses
`Special:FilePath` de Wikimedia Commons, qui redirigent vers l'image, s'affichent.
