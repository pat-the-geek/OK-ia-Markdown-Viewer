# TestFlight — informations de test

À coller dans **App Store Connect → TestFlight**. Deux niveaux :
- **Test Information** (par app, partagé) — description bêta, e-mail de feedback, URLs.
- **What to Test** (par build) — ce que les testeurs doivent essayer.
- **Beta App Review Information** — requis seulement pour les **testeurs externes** (revue légère).

> ⚠️ **Build à utiliser : `1.3 (58)`** — version de développement de la 1.3 : conversion d'un rapport
> en présentation, thèmes de lecture, nouvelles transitions du diaporama et leur export PowerPoint. Envoyé par
> `scripts/deploy-testflight.sh --bump --both`, compilé avec **Xcode 27.1 RC** (seul à compiler le Duo ;
> Apple en accepte les binaires) : le script refuse d'envoyer depuis une bêta.
>
> **Cette version demande iOS/iPadOS 26.4 ou macOS 26.4**, comme la 1.2.

---

## Test Information (App-level)

- **Beta App Description**
```
md Viewer (OK-ia Markdown Viewer) affiche des fichiers Markdown à la charte ok-ia.ch :
diagrammes Mermaid, cartes Leaflet, callouts, coloration d'entités, résumé et discussion par
Apple Intelligence, et traduction du document sur l'appareil.
Cette bêta sert à valider le rendu, la navigation, la traduction et la stabilité sur iPhone,
iPad et Mac.
```
- **Feedback Email** : `patrick@ok-ia.ch`
- **Marketing URL** : `https://ok-ia.ch`
- **Privacy Policy URL** : `https://ok-ia.ch/mdviewer/confidentialite.html`

---

## What to Test — 1.3 (58)

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA PLUS GRANDE SURFACE D'AFFICHAGE
• Le texte prend toute la largeur de l'écran, avec une petite marge (sauf le
  thème Éditorial, à colonne étroite — mais pas dans le livre, où chaque page
  est pleine). Signalez toute ligne trop longue à lire.
• Le mode livre : iPhone Duo partiellement replié, iPad ou grand iPhone en
  paysage. Tournez la page avec le doigt : elle se courbe comme une feuille,
  suit le doigt, et retombe sous son poids du côté où elle penche, avec un
  léger rebond. Un coin corné indique qu'il y a une suite. Signalez tout blanc
  en bas de page qui ne précède ni un titre ni un grand visuel.
• Une pastille de verre, au coin de chaque diagramme, image, chronologie ou
  tableau, signale qu'il s'ouvre en plein écran (à gauche sur la page de droite
  du livre). Touchez-la, ou l'objet : il s'ouvre en entier ; pincez pour
  agrandir. Sur iPhone en portrait, une longue chronologie passe à la ligne.
  Dans le livre, le bouton plein écran d'une carte l'ouvre aussi.
• Touchez une page pour faire revenir la barre, une seconde fois pour la renvoyer.
• iPhone Duo déplié ou plié : les commandes sont rangées dans la colonne de
  droite, et la page va jusqu'à elle.

NOUVEAU — L'ALLURE D'UNE APP
• Le lecteur prend la barre d'outils du système : titre, maison, commandes en
  groupes de verre (Liquid Glass), icônes monochromes. Sur iPhone tenu droit,
  trois commandes et un menu « … » pour le reste.
• La recherche est celle du système : touchez la loupe, tapez, ↑ ↓ pour passer
  d'un résultat à l'autre.
• Sur Mac, une vraie barre de fenêtre, sur une seule rangée. L'app est désormais
  « optimisée pour le Mac » : dites-nous tout ce qui paraît trop grand, trop
  petit ou mal placé — réglages, feuilles, menus, diaporama.
• L'écran d'accueil devient une liste : récents et coffre par date ; balayez une
  ligne pour la retirer. Ouvrir et « Voir un exemple » sont dans la barre.

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, sur l'iPhone Duo déplié et sur Mac
  (fenêtre large), la conversion s'ouvre à droite du rapport : continuez de lire.
• La vue suit la dernière diapositive. Remontez en voir une plus ancienne : elle
  ne doit pas vous ramener en bas ; redescendez, elle suit de nouveau.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• La dernière diapositive, « À retenir », doit toujours porter des puces, même
  pour un rapport court.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (56) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA PLUS GRANDE SURFACE D'AFFICHAGE
• Le texte prend toute la largeur de l'écran, avec une petite marge (sauf le
  thème Éditorial, à colonne étroite). Signalez toute ligne trop longue à lire.
• Le mode livre : iPhone Duo partiellement replié, iPad ou grand iPhone en
  paysage. Deux pages côte à côte ; tournez la page avec le doigt, elle se
  soulève et découvre la suivante. Lâchez-la avant la moitié : elle retombe.
  Un coin corné indique qu'il y a une suite. Signalez tout blanc en bas de
  page qui ne précède ni un titre ni un grand visuel.
• Dans le livre comme en portrait, touchez un diagramme, la chronologie d'un
  rapport ou un tableau : il s'ouvre en plein écran, en entier ; pincez pour
  agrandir.
• Touchez une page pour faire revenir la barre, une seconde fois pour la renvoyer.
• iPhone Duo déplié ou plié : les commandes sont rangées dans la colonne de
  droite, et la page va jusqu'à elle.

NOUVEAU — L'ALLURE D'UNE APP
• Le lecteur prend la barre d'outils du système : titre, maison, commandes en
  groupes de verre (Liquid Glass), icônes monochromes. Sur iPhone tenu droit,
  trois commandes et un menu « … » pour le reste.
• La recherche est celle du système : touchez la loupe, tapez, ↑ ↓ pour passer
  d'un résultat à l'autre.
• Sur Mac, une vraie barre de fenêtre, sur une seule rangée. L'app est désormais
  « optimisée pour le Mac » : dites-nous tout ce qui paraît trop grand, trop
  petit ou mal placé — réglages, feuilles, menus, diaporama.
• L'écran d'accueil devient une liste : récents et coffre par date ; balayez une
  ligne pour la retirer. Ouvrir et « Voir un exemple » sont dans la barre.

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, sur l'iPhone Duo déplié et sur Mac
  (fenêtre large), la conversion s'ouvre à droite du rapport : continuez de lire.
• La vue suit la dernière diapositive. Remontez en voir une plus ancienne : elle
  ne doit pas vous ramener en bas ; redescendez, elle suit de nouveau.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• La dernière diapositive, « À retenir », doit toujours porter des puces, même
  pour un rapport court.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (55) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA PLUS GRANDE SURFACE D'AFFICHAGE
• Le texte prend toute la largeur de l'écran, avec une petite marge (sauf le
  thème Éditorial, à colonne étroite). Signalez toute ligne trop longue à lire.
• Le mode livre : iPhone Duo partiellement replié, iPad ou grand iPhone en
  paysage. Deux pages côte à côte ; tournez la page avec le doigt, elle se
  soulève et découvre la suivante. Lâchez-la avant la moitié : elle retombe.
  Un coin corné indique qu'il y a une suite. Signalez tout blanc en bas de
  page qui ne précède ni un titre ni un grand visuel.
• Touchez une page pour faire revenir la barre, une seconde fois pour la renvoyer.
• iPhone Duo déplié ou plié : les commandes sont rangées dans la colonne de
  droite, et la page va jusqu'à elle.

NOUVEAU — L'ALLURE D'UNE APP
• Le lecteur prend la barre d'outils du système : titre, maison, commandes en
  groupes de verre (Liquid Glass), icônes monochromes. Sur iPhone tenu droit,
  trois commandes et un menu « … » pour le reste.
• La recherche est celle du système : touchez la loupe, tapez, ↑ ↓ pour passer
  d'un résultat à l'autre.
• Sur Mac, une vraie barre de fenêtre, sur une seule rangée. L'app est désormais
  « optimisée pour le Mac » : dites-nous tout ce qui paraît trop grand, trop
  petit ou mal placé — réglages, feuilles, menus, diaporama.
• L'écran d'accueil devient une liste : récents et coffre par date ; balayez une
  ligne pour la retirer. Ouvrir et « Voir un exemple » sont dans la barre.

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, sur l'iPhone Duo déplié et sur Mac
  (fenêtre large), la conversion s'ouvre à droite du rapport : continuez de lire.
• La vue suit la dernière diapositive. Remontez en voir une plus ancienne : elle
  ne doit pas vous ramener en bas ; redescendez, elle suit de nouveau.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• La dernière diapositive, « À retenir », doit toujours porter des puces, même
  pour un rapport court.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (54) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA PLUS GRANDE SURFACE D'AFFICHAGE
• Le texte prend toute la largeur de l'écran, avec une petite marge (sauf le
  thème Éditorial, à colonne étroite). Signalez toute ligne trop longue à lire.
• iPhone Duo partiellement replié : le mode livre. La page de droite est la
  suite de celle de gauche, et l'on tourne les pages comme dans Kindle : la
  double page suit le doigt vers la gauche (suivante) ou la droite
  (précédente) ; lâchez-la avant le tiers, elle revient. Aucune ligne ne doit
  être coupée en bas d'une page. La barre s'efface : touchez une page pour la
  faire revenir, une seconde fois pour la renvoyer.
• iPhone Duo déplié ou plié : les commandes sont rangées dans la colonne de
  droite, et la page va jusqu'à elle.

NOUVEAU — L'ALLURE D'UNE APP
• Le lecteur prend la barre d'outils du système : titre, maison, commandes en
  groupes de verre (Liquid Glass), icônes monochromes. Sur iPhone tenu droit,
  trois commandes et un menu « … » pour le reste.
• La recherche est celle du système : touchez la loupe, tapez, ↑ ↓ pour passer
  d'un résultat à l'autre.
• Sur Mac, une vraie barre de fenêtre, sur une seule rangée. L'app est désormais
  « optimisée pour le Mac » : dites-nous tout ce qui paraît trop grand, trop
  petit ou mal placé — réglages, feuilles, menus, diaporama.
• L'écran d'accueil devient une liste : récents et coffre par date ; balayez une
  ligne pour la retirer. Ouvrir et « Voir un exemple » sont dans la barre.

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, sur l'iPhone Duo déplié et sur Mac
  (fenêtre large), la conversion s'ouvre à droite du rapport : continuez de lire.
• La vue suit la dernière diapositive. Remontez en voir une plus ancienne : elle
  ne doit pas vous ramener en bas ; redescendez, elle suit de nouveau.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• La dernière diapositive, « À retenir », doit toujours porter des puces, même
  pour un rapport court.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

CORRIGÉ — LE RÉSUMÉ ET LA DISCUSSION DÉFILENT À DROITE
• En paysage, le résumé et la discussion ouverts à droite du document se font
  défiler jusqu'en bas, même pendant une traduction.
• Sur Mac, ils s'ouvrent aussi à droite quand la fenêtre est large.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
• Touchez un appel de source orange : la note s'ouvre en aperçu. Sur Mac, survolez-le.
• Export Word : les sources deviennent des notes de fin. Dites-nous ce qu'en affiche Word.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (53) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA PLUS GRANDE SURFACE D'AFFICHAGE
• Le texte prend toute la largeur de l'écran, avec une petite marge (sauf le
  thème Éditorial, à colonne étroite). Signalez toute ligne trop longue à lire.
• iPhone Duo partiellement replié : le mode livre. La page de droite est la
  suite de celle de gauche ; les deux défilent ensemble. La barre s'efface :
  touchez une page pour la faire revenir, une seconde fois pour la renvoyer.
• iPhone Duo déplié ou plié : les commandes sont rangées dans la colonne de
  droite, et la page va jusqu'à elle.

NOUVEAU — L'ALLURE D'UNE APP
• Le lecteur prend la barre d'outils du système : titre, maison, commandes en
  groupes de verre (Liquid Glass), icônes monochromes. Sur iPhone tenu droit,
  trois commandes et un menu « … » pour le reste.
• La recherche est celle du système : touchez la loupe, tapez, ↑ ↓ pour passer
  d'un résultat à l'autre.
• Sur Mac, une vraie barre de fenêtre, sur une seule rangée. L'app est désormais
  « optimisée pour le Mac » : dites-nous tout ce qui paraît trop grand, trop
  petit ou mal placé — réglages, feuilles, menus, diaporama.
• L'écran d'accueil devient une liste : récents et coffre par date ; balayez une
  ligne pour la retirer. Ouvrir et « Voir un exemple » sont dans la barre.

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, sur l'iPhone Duo déplié et sur Mac
  (fenêtre large), la conversion s'ouvre à droite du rapport : continuez de lire.
• La vue suit la dernière diapositive. Remontez en voir une plus ancienne : elle
  ne doit pas vous ramener en bas ; redescendez, elle suit de nouveau.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• La dernière diapositive, « À retenir », doit toujours porter des puces, même
  pour un rapport court.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

CORRIGÉ — LE RÉSUMÉ ET LA DISCUSSION DÉFILENT À DROITE
• En paysage, le résumé et la discussion ouverts à droite du document se font
  défiler jusqu'en bas, même pendant une traduction.
• Sur Mac, ils s'ouvrent aussi à droite quand la fenêtre est large.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
• Touchez un appel de source orange : la note s'ouvre en aperçu. Sur Mac, survolez-le.
• Export Word : les sources deviennent des notes de fin. Dites-nous ce qu'en affiche Word.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (52) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — L'ALLURE D'UNE APP
• Le lecteur prend la barre d'outils du système : titre, maison, commandes en
  groupes de verre (Liquid Glass), icônes monochromes. Sur iPhone tenu droit,
  trois commandes et un menu « … » pour le reste.
• La recherche est celle du système : touchez la loupe, tapez, ↑ ↓ pour passer
  d'un résultat à l'autre.
• Sur Mac, une vraie barre de fenêtre, sur une seule rangée. L'app est désormais
  « optimisée pour le Mac » : dites-nous tout ce qui paraît trop grand, trop
  petit ou mal placé — réglages, feuilles, menus, diaporama.
• L'écran d'accueil devient une liste : récents et coffre par date ; balayez une
  ligne pour la retirer. Ouvrir et « Voir un exemple » sont dans la barre.

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, sur l'iPhone Duo déplié et sur Mac
  (fenêtre large), la conversion s'ouvre à droite du rapport : continuez de lire.
• La vue suit la dernière diapositive. Remontez en voir une plus ancienne : elle
  ne doit pas vous ramener en bas ; redescendez, elle suit de nouveau.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• La dernière diapositive, « À retenir », doit toujours porter des puces, même
  pour un rapport court.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

CORRIGÉ — LE RÉSUMÉ ET LA DISCUSSION DÉFILENT À DROITE
• En paysage, le résumé et la discussion ouverts à droite du document se font
  défiler jusqu'en bas, même pendant une traduction.
• Sur Mac, ils s'ouvrent aussi à droite quand la fenêtre est large.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
• Touchez un appel de source orange : la note s'ouvre en aperçu. Sur Mac, survolez-le.
• Export Word : les sources deviennent des notes de fin. Dites-nous ce qu'en affiche Word.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (51) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, sur l'iPhone Duo déplié et sur Mac
  (fenêtre large), la conversion s'ouvre à droite du rapport : continuez de lire.
• La vue suit la dernière diapositive. Remontez en voir une plus ancienne : elle
  ne doit pas vous ramener en bas ; redescendez, elle suit de nouveau.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• La dernière diapositive, « À retenir », doit toujours porter des puces, même
  pour un rapport court.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

CORRIGÉ — LE RÉSUMÉ ET LA DISCUSSION DÉFILENT À DROITE
• En paysage, le résumé et la discussion ouverts à droite du document se font
  défiler jusqu'en bas, même pendant une traduction.
• Sur Mac, ils s'ouvrent aussi à droite quand la fenêtre est large.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
• Touchez un appel de source orange : la note s'ouvre en aperçu. Sur Mac, survolez-le.
• Export Word : les sources deviennent des notes de fin. Dites-nous ce qu'en affiche Word.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (50) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, sur l'iPhone Duo déplié et sur Mac
  (fenêtre large), la conversion s'ouvre à droite du rapport : continuez de lire.
• La vue suit la dernière diapositive. Remontez en voir une plus ancienne : elle
  ne doit pas vous ramener en bas ; redescendez, elle suit de nouveau.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

CORRIGÉ — LE RÉSUMÉ ET LA DISCUSSION DÉFILENT À DROITE
• En paysage, le résumé et la discussion ouverts à droite du document se font
  défiler jusqu'en bas, même pendant une traduction.
• Sur Mac, ils s'ouvrent aussi à droite quand la fenêtre est large.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
• Touchez un appel de source orange : la note s'ouvre en aperçu. Sur Mac, survolez-le.
• Export Word : les sources deviennent des notes de fin. Dites-nous ce qu'en affiche Word.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (49) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA PRÉSENTATION SE CONSTRUIT SOUS VOS YEUX
Bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Chaque diapositive apparaît en vignette dès qu'elle est prête, avec le thème,
  les images et la carte ; une case en pointillés annonce la suivante.
• En paysage sur iPhone Pro Max ou iPad, et sur l'iPhone Duo déplié, la
  conversion s'ouvre à droite du rapport : continuez de lire pendant ce temps.
• Remontez voir une vignette plus ancienne : la vue ne doit pas vous ramener en bas.
• À la fin, « Lancer le diaporama » ; en le quittant, les vignettes sont toujours là.
• Tournez l'appareil pendant la conversion : elle doit continuer.
• Choisissez 5, 10, 15, 20 ou 25 diapositives : la présentation doit compter
  exactement ce nombre. Signalez tout chiffre ou nom absent du rapport.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.

CORRIGÉ — LE RÉSUMÉ ET LA DISCUSSION DÉFILENT À DROITE
• En paysage, le résumé et la discussion ouverts à droite du document se font
  défiler jusqu'en bas, même pendant une traduction.

LA BARRE EN LIQUID GLASS
• La barre du lecteur flotte sur la page. Pliez ou tournez l'appareil en haut
  d'un document : le titre doit rester visible sous la barre.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot.

DEUX PARTIES EN PAYSAGE ET SUR LE DUO
• En paysage (Pro Max, iPad) ou Duo déplié, le sommaire, le résumé et la
  discussion s'ouvrent à côté du document. En portrait, ce sont des feuilles.
• Sur le Duo, la page va jusqu'au bord ; seul le coin de l'heure est évité.

RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
• Touchez un appel de source orange : la note s'ouvre en aperçu. Sur Mac, survolez-le.
• Export Word : les sources deviennent des notes de fin. Dites-nous ce qu'en affiche Word.

TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama, dont le Damier ; l'export PowerPoint reprend la
  transition choisie : dites-nous ce qu'en garde Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre.
• Nécessite un appareil compatible Apple Intelligence pour la conversion, le
  résumé et la discussion ; tout se calcule sur l'appareil.
```

---

## What to Test — 1.3 (48) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA BARRE EN LIQUID GLASS
• La barre du lecteur devient deux capsules de verre qui flottent sur la page :
  le document défile dessous. Le titre ne s'affiche que s'il tient en entier.
• Pliez ou tournez l'appareil en haut d'un document : le titre doit rester
  visible sous la barre, jamais caché dessous.
• Changez de thème (bouton Aa) sur un document avec une carte : la carte doit
  suivre la nouvelle largeur, sans bande grise.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot (« Si » dans
  « Siri »).

NOUVEAU — DEUX PARTIES EN PAYSAGE (iPhone Pro Max, iPad)
• Tournez un grand iPhone ou un iPad en paysage, puis ouvrez le sommaire, le
  résumé ou la discussion : ils s'ouvrent à droite du document. En portrait,
  ils restent des feuilles.

NOUVEAU — IPHONE DUO (si vous en avez un)
• Déplié, le sommaire, le résumé et la discussion s'ouvrent de l'autre côté de
  la pliure, à côté du document. Plié, ils restent des feuilles.
• La page va jusqu'au bord ; seul le coin de l'heure et de la caméra est évité.

NOUVEAU — LES RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
Ouvrez un rapport de veille de fornews.ai.
• Les appels de source deviennent des exposants orange. Touchez-en un (iPhone,
  iPad) : la note s'ouvre en aperçu, avec « Aller à la note ». Sur Mac, survolez-le.
• La section « Notes » réunit les sources, avec leurs liens. ↩ ramène à l'appel.
• L'avertissement final doit rester le tout dernier élément du rapport.
• Dates et montants colorés : la légende en haut les nomme.
• Exportez en Word : les sources deviennent des notes de fin, et la synthèse doit
  être là. Dites-nous ce que Word en affiche.

NOUVEAU — CONVERTIR UN RAPPORT EN PRÉSENTATION (Apple Intelligence)
Ouvrez un rapport, puis bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Choisissez 5, 10, 15, 20 ou 25 diapositives, ou « Autre ». La présentation doit
  compter exactement ce nombre.
• Suivez l'avancement : la liste des diapositives prêtes doit s'allonger au fur
  et à mesure, titre et plan d'abord. Puis « Lancer le diaporama ».
• Vérifiez les chiffres : chacun doit se retrouver dans le rapport. Signalez tout
  chiffre ou tout nom qui n'y figure pas.
• Les diagrammes et la carte du rapport doivent être repris tels quels.
• Les images du rapport passent dans la présentation : dites-nous si une image
  tombe mal ou si une section manque.
• La présentation garde la langue du rapport : essayez un rapport en anglais ou en
  allemand.
• « Laissé de côté » doit dire honnêtement ce qui manque, surtout à 5 diapositives.
• « Enregistrer le fichier .md » : le fichier doit s'ouvrir dans md Viewer.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.
• Nécessite un appareil compatible Apple Intelligence ; tout se calcule sur
  l'appareil.


TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama (menu du diaporama → Transition), dont le Damier
  aux cases qui pivotent ; « Réduire les animations » les change en fondu.
• L'export PowerPoint reprend la transition choisie ; dites-nous ce qu'en garde
  Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre ; le PDF reste
  aux couleurs OK-ia.
```

## What to Test — 1.3 (47) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LA BARRE EN LIQUID GLASS
• La barre du lecteur devient deux capsules de verre qui flottent sur la page :
  le document défile dessous. Le titre ne s'affiche que s'il tient en entier.
• Pliez ou tournez l'appareil en haut d'un document : le titre doit rester
  visible sous la barre, jamais caché dessous.
• Changez de thème (bouton Aa) sur un document avec une carte : la carte doit
  suivre la nouvelle largeur, sans bande grise.
• Les noms surlignés ne doivent plus l'être au milieu d'un mot (« Si » dans
  « Siri »).

NOUVEAU — IPHONE DUO (si vous en avez un)
• Déplié, le sommaire, le résumé et la discussion s'ouvrent de l'autre côté de
  la pliure, à côté du document. Plié, ils restent des feuilles.
• La page va jusqu'au bord ; seul le coin de l'heure et de la caméra est évité.

NOUVEAU — LES RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
Ouvrez un rapport de veille de fornews.ai.
• Les appels de source deviennent des exposants orange. Touchez-en un (iPhone,
  iPad) : la note s'ouvre en aperçu, avec « Aller à la note ». Sur Mac, survolez-le.
• La section « Notes » réunit les sources, avec leurs liens. ↩ ramène à l'appel.
• L'avertissement final doit rester le tout dernier élément du rapport.
• Dates et montants colorés : la légende en haut les nomme.
• Exportez en Word : les sources deviennent des notes de fin, et la synthèse doit
  être là. Dites-nous ce que Word en affiche.

NOUVEAU — CONVERTIR UN RAPPORT EN PRÉSENTATION (Apple Intelligence)
Ouvrez un rapport, puis bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Choisissez 5, 10, 15, 20 ou 25 diapositives, ou « Autre ». La présentation doit
  compter exactement ce nombre.
• Suivez l'avancement : la liste des diapositives prêtes doit s'allonger au fur
  et à mesure, titre et plan d'abord. Puis « Lancer le diaporama ».
• Vérifiez les chiffres : chacun doit se retrouver dans le rapport. Signalez tout
  chiffre ou tout nom qui n'y figure pas.
• Les diagrammes et la carte du rapport doivent être repris tels quels.
• Les images du rapport passent dans la présentation : dites-nous si une image
  tombe mal ou si une section manque.
• La présentation garde la langue du rapport : essayez un rapport en anglais ou en
  allemand.
• « Laissé de côté » doit dire honnêtement ce qui manque, surtout à 5 diapositives.
• « Enregistrer le fichier .md » : le fichier doit s'ouvrir dans md Viewer.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.
• Nécessite un appareil compatible Apple Intelligence ; tout se calcule sur
  l'appareil.


TOUJOURS À ESSAYER — DIAPORAMA, EXPORT POWERPOINT, THÈMES
• Onze transitions au diaporama (menu du diaporama → Transition), dont le Damier
  aux cases qui pivotent ; « Réduire les animations » les change en fondu.
• L'export PowerPoint reprend la transition choisie ; dites-nous ce qu'en garde
  Keynote.
• Bouton « Aa » : cinq thèmes de lecture, en clair et en sombre ; le PDF reste
  aux couleurs OK-ia.
```

## What to Test — 1.3 (46) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — LES RAPPORTS DE VEILLE FORNEWS : NOTES DE BAS DE PAGE
Ouvrez un rapport de veille de fornews.ai.
• Les appels de source deviennent des exposants orange. Touchez-en un (iPhone,
  iPad) : la note s'ouvre en aperçu, avec « Aller à la note ». Sur Mac, survolez-le.
• La section « Notes » réunit les sources, avec leurs liens. ↩ ramène à l'appel.
• L'avertissement final doit rester le tout dernier élément du rapport.
• Dates et montants colorés : la légende en haut les nomme.
• Exportez en Word : les sources deviennent des notes de fin, et la synthèse doit
  être là. Dites-nous ce que Word en affiche.

NOUVEAU — CONVERTIR UN RAPPORT EN PRÉSENTATION (Apple Intelligence)
Ouvrez un rapport, puis bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Choisissez 5, 10, 15, 20 ou 25 diapositives, ou « Autre ». La présentation doit
  compter exactement ce nombre.
• Suivez l'avancement : la liste des diapositives prêtes doit s'allonger au fur
  et à mesure, titre et plan d'abord. Puis « Lancer le diaporama ».
• Vérifiez les chiffres : chacun doit se retrouver dans le rapport. Signalez tout
  chiffre ou tout nom qui n'y figure pas.
• Les diagrammes et la carte du rapport doivent être repris tels quels.
• Nouveau dans ce build : les images du rapport passent dans la présentation —
  en couverture, sous les puces, ou seules avec leur phrase. Essayez un rapport
  illustré et dites-nous si une image tombe mal ou si une section manque.
• La présentation garde la langue du rapport : essayez un rapport en anglais ou en
  allemand.
• « Laissé de côté » doit dire honnêtement ce qui manque, surtout à 5 diapositives.
• « Enregistrer le fichier .md » : le fichier doit s'ouvrir dans md Viewer.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.
• Nécessite un appareil compatible Apple Intelligence ; tout se calcule sur
  l'appareil.


NOUVEAU — SIX TRANSITIONS DE PLUS AU DIAPORAMA
Ouvrez un document découpé en diapositives par des lignes --- (par exemple une
présentation exportée de fornews.ai) et lancez le diaporama (bouton ▶).
• Menu du diaporama → Transition : Balayage, Découverte, Cube, Iris, Fondu au noir
  et Damier s'ajoutent aux cinq existantes.
• Essayez chacune en avançant ET en reculant : la plupart changent de sens.
• Damier (refait dans ce build) : la diapositive se découpe en cases qui pivotent
  une à une, au hasard, pour découvrir la suivante.
• Aucune trace ne doit rester à l'écran après une transition, et les cartes et
  diagrammes doivent rester à leur place, même après Cube et Damier.
• Dites-nous si l'une d'elles saccade, et sur quel appareil.
• Réglages de l'appareil → Accessibilité → Mouvement → Réduire les animations :
  toutes les transitions doivent alors devenir un simple fondu.

NOUVEAU — LES TRANSITIONS DANS L'EXPORT POWERPOINT
• Choisissez une transition, puis Menu du diaporama → Exporter en PowerPoint.
• Ouvrez le fichier dans PowerPoint : chaque diapositive doit porter la transition
  choisie (onglet Transitions).
• Le Damier devient dans PowerPoint le « Scintillement » en losanges, son plus
  proche parent.
• Ouvrez-le aussi dans Keynote et dites-nous ce qu'il en reste : l'Échelle, le
  Retournement, le Cube et le Damier y prévoient un repli, au cas où.

NOUVEAU — LES THÈMES DE LECTURE
• Bouton « Aa » du lecteur : OK-ia, Administratif, Éditorial, Lecture longue,
  Contraste élevé. Essayez-les en clair et en sombre.
• Exportez en PDF depuis un autre thème que OK-ia : le PDF doit rester aux
  couleurs OK-ia.
```

## What to Test — 1.3 (45) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — CONVERTIR UN RAPPORT EN PRÉSENTATION (Apple Intelligence)
Ouvrez un rapport, puis bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Choisissez 5, 10, 15, 20 ou 25 diapositives, ou « Autre ». La présentation doit
  compter exactement ce nombre.
• Suivez l'avancement : la liste des diapositives prêtes doit s'allonger au fur
  et à mesure, titre et plan d'abord. Puis « Lancer le diaporama ».
• Vérifiez les chiffres : chacun doit se retrouver dans le rapport. Signalez tout
  chiffre ou tout nom qui n'y figure pas.
• Les diagrammes et la carte du rapport doivent être repris tels quels.
• Nouveau dans ce build : les images du rapport passent dans la présentation —
  en couverture, sous les puces, ou seules avec leur phrase. Essayez un rapport
  illustré et dites-nous si une image tombe mal ou si une section manque.
• La présentation garde la langue du rapport : essayez un rapport en anglais ou en
  allemand.
• « Laissé de côté » doit dire honnêtement ce qui manque, surtout à 5 diapositives.
• « Enregistrer le fichier .md » : le fichier doit s'ouvrir dans md Viewer.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.
• Nécessite un appareil compatible Apple Intelligence ; tout se calcule sur
  l'appareil.


NOUVEAU — SIX TRANSITIONS DE PLUS AU DIAPORAMA
Ouvrez un document découpé en diapositives par des lignes --- (par exemple une
présentation exportée de fornews.ai) et lancez le diaporama (bouton ▶).
• Menu du diaporama → Transition : Balayage, Découverte, Cube, Iris, Fondu au noir
  et Damier s'ajoutent aux cinq existantes.
• Essayez chacune en avançant ET en reculant : la plupart changent de sens.
• Damier (refait dans ce build) : la diapositive se découpe en cases qui pivotent
  une à une, au hasard, pour découvrir la suivante.
• Aucune trace ne doit rester à l'écran après une transition, et les cartes et
  diagrammes doivent rester à leur place, même après Cube et Damier.
• Dites-nous si l'une d'elles saccade, et sur quel appareil.
• Réglages de l'appareil → Accessibilité → Mouvement → Réduire les animations :
  toutes les transitions doivent alors devenir un simple fondu.

NOUVEAU — LES TRANSITIONS DANS L'EXPORT POWERPOINT
• Choisissez une transition, puis Menu du diaporama → Exporter en PowerPoint.
• Ouvrez le fichier dans PowerPoint : chaque diapositive doit porter la transition
  choisie (onglet Transitions).
• Le Damier devient dans PowerPoint le « Scintillement » en losanges, son plus
  proche parent.
• Ouvrez-le aussi dans Keynote et dites-nous ce qu'il en reste : l'Échelle, le
  Retournement, le Cube et le Damier y prévoient un repli, au cas où.

NOUVEAU — LES THÈMES DE LECTURE
• Bouton « Aa » du lecteur : OK-ia, Administratif, Éditorial, Lecture longue,
  Contraste élevé. Essayez-les en clair et en sombre.
• Exportez en PDF depuis un autre thème que OK-ia : le PDF doit rester aux
  couleurs OK-ia.
```

## What to Test — 1.3 (44) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — CONVERTIR UN RAPPORT EN PRÉSENTATION (Apple Intelligence)
Ouvrez un rapport, puis bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Choisissez 5, 10, 15, 20 ou 25 diapositives, ou « Autre ». La présentation doit
  compter exactement ce nombre.
• Suivez l'avancement : la liste des diapositives prêtes doit s'allonger au fur
  et à mesure, titre et plan d'abord. Puis « Lancer le diaporama ».
• Vérifiez les chiffres : chacun doit se retrouver dans le rapport. Signalez tout
  chiffre ou tout nom qui n'y figure pas.
• Les diagrammes et la carte du rapport doivent être repris tels quels.
• La présentation garde la langue du rapport : essayez un rapport en anglais ou en
  allemand.
• « Laissé de côté » doit dire honnêtement ce qui manque, surtout à 5 diapositives.
• « Enregistrer le fichier .md » : le fichier doit s'ouvrir dans md Viewer.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.
• Nécessite un appareil compatible Apple Intelligence ; tout se calcule sur
  l'appareil.


NOUVEAU — SIX TRANSITIONS DE PLUS AU DIAPORAMA
Ouvrez un document découpé en diapositives par des lignes --- (par exemple une
présentation exportée de fornews.ai) et lancez le diaporama (bouton ▶).
• Menu du diaporama → Transition : Balayage, Découverte, Cube, Iris, Fondu au noir
  et Damier s'ajoutent aux cinq existantes.
• Essayez chacune en avançant ET en reculant : la plupart changent de sens.
• Damier (refait dans ce build) : la diapositive se découpe en cases qui pivotent
  une à une, au hasard, pour découvrir la suivante.
• Aucune trace ne doit rester à l'écran après une transition, et les cartes et
  diagrammes doivent rester à leur place, même après Cube et Damier.
• Dites-nous si l'une d'elles saccade, et sur quel appareil.
• Réglages de l'appareil → Accessibilité → Mouvement → Réduire les animations :
  toutes les transitions doivent alors devenir un simple fondu.

NOUVEAU — LES TRANSITIONS DANS L'EXPORT POWERPOINT
• Choisissez une transition, puis Menu du diaporama → Exporter en PowerPoint.
• Ouvrez le fichier dans PowerPoint : chaque diapositive doit porter la transition
  choisie (onglet Transitions).
• Le Damier devient dans PowerPoint le « Scintillement » en losanges, son plus
  proche parent.
• Ouvrez-le aussi dans Keynote et dites-nous ce qu'il en reste : l'Échelle, le
  Retournement, le Cube et le Damier y prévoient un repli, au cas où.

NOUVEAU — LES THÈMES DE LECTURE
• Bouton « Aa » du lecteur : OK-ia, Administratif, Éditorial, Lecture longue,
  Contraste élevé. Essayez-les en clair et en sombre.
• Exportez en PDF depuis un autre thème que OK-ia : le PDF doit rester aux
  couleurs OK-ia.
```

## What to Test — 1.3 (43) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — CONVERTIR UN RAPPORT EN PRÉSENTATION (Apple Intelligence)
Ouvrez un rapport, puis bouton Apple Intelligence du lecteur → « Convertir en présentation ».
• Choisissez 5, 10, 15, 20 ou 25 diapositives, ou « Autre ». La présentation doit
  compter exactement ce nombre.
• Suivez l'avancement section par section, puis « Lancer le diaporama ».
• Vérifiez les chiffres : chacun doit se retrouver dans le rapport. Signalez tout
  chiffre ou tout nom qui n'y figure pas.
• Les diagrammes et la carte du rapport doivent être repris tels quels.
• La présentation garde la langue du rapport : essayez un rapport en anglais ou en
  allemand.
• « Laissé de côté » doit dire honnêtement ce qui manque, surtout à 5 diapositives.
• « Enregistrer le fichier .md » : le fichier doit s'ouvrir dans md Viewer.
• Dites-nous combien de temps a pris la conversion, et sur quel appareil.
• Nécessite un appareil compatible Apple Intelligence ; tout se calcule sur
  l'appareil.


NOUVEAU — SIX TRANSITIONS DE PLUS AU DIAPORAMA
Ouvrez un document découpé en diapositives par des lignes --- (par exemple une
présentation exportée de fornews.ai) et lancez le diaporama (bouton ▶).
• Menu du diaporama → Transition : Balayage, Découverte, Cube, Iris, Fondu au noir
  et Damier s'ajoutent aux cinq existantes.
• Essayez chacune en avançant ET en reculant : la plupart changent de sens.
• Aucune trace ne doit rester à l'écran après une transition, et les cartes et
  diagrammes doivent rester à leur place, même après Cube et Damier.
• Dites-nous si l'une d'elles saccade, et sur quel appareil.
• Réglages de l'appareil → Accessibilité → Mouvement → Réduire les animations :
  toutes les transitions doivent alors devenir un simple fondu.

NOUVEAU — LES TRANSITIONS DANS L'EXPORT POWERPOINT
• Choisissez une transition, puis Menu du diaporama → Exporter en PowerPoint.
• Ouvrez le fichier dans PowerPoint : chaque diapositive doit porter la transition
  choisie (onglet Transitions).
• Ouvrez-le aussi dans Keynote et dites-nous ce qu'il en reste : l'Échelle, le
  Retournement et le Cube y prévoient un fondu de repli, au cas où.

NOUVEAU — LES THÈMES DE LECTURE
• Bouton « Aa » du lecteur : OK-ia, Administratif, Éditorial, Lecture longue,
  Contraste élevé. Essayez-les en clair et en sombre.
• Exportez en PDF depuis un autre thème que OK-ia : le PDF doit rester aux
  couleurs OK-ia.
```

## What to Test — 1.3 (42) — archive

```
Merci de tester la 1.3 de md Viewer, en cours de développement. Points à vérifier :

NOUVEAU — SIX TRANSITIONS DE PLUS AU DIAPORAMA
Ouvrez un document découpé en diapositives par des lignes --- (par exemple une
présentation exportée de fornews.ai) et lancez le diaporama (bouton ▶).
• Menu du diaporama → Transition : Balayage, Découverte, Cube, Iris, Fondu au noir
  et Damier s'ajoutent aux cinq existantes.
• Essayez chacune en avançant ET en reculant : la plupart changent de sens.
• Aucune trace ne doit rester à l'écran après une transition, et les cartes et
  diagrammes doivent rester à leur place, même après Cube et Damier.
• Dites-nous si l'une d'elles saccade, et sur quel appareil.
• Réglages de l'appareil → Accessibilité → Mouvement → Réduire les animations :
  toutes les transitions doivent alors devenir un simple fondu.

NOUVEAU — LES TRANSITIONS DANS L'EXPORT POWERPOINT
• Choisissez une transition, puis Menu du diaporama → Exporter en PowerPoint.
• Ouvrez le fichier dans PowerPoint : chaque diapositive doit porter la transition
  choisie (onglet Transitions).
• Ouvrez-le aussi dans Keynote et dites-nous ce qu'il en reste : l'Échelle, le
  Retournement et le Cube y prévoient un fondu de repli, au cas où.

NOUVEAU — LES THÈMES DE LECTURE
• Bouton « Aa » du lecteur : OK-ia, Administratif, Éditorial, Lecture longue,
  Contraste élevé. Essayez-les en clair et en sombre.
• Exportez en PDF depuis un autre thème que OK-ia : le PDF doit rester aux
  couleurs OK-ia.
```

## What to Test — 1.2 (39) — archive

```
Merci de tester md Viewer ! Points à vérifier :

NOUVEAU DANS CE BUILD — L'OUVERTURE DEPUIS FORNEWS.AI
• Sur iPhone comme sur Mac, depuis fornews.ai, demandez à ouvrir un rapport dans
  md Viewer. Le document doit s'afficher ici, en entier, y compris un long rapport :
  c'était impossible sur iPhone jusqu'à ce build.
• Enchaînez une dizaine de rapports : rien ne doit ralentir ni gonfler, la boîte
  partagée ne gardant que les derniers dépôts.
• Si un document ne s'ouvre pas, l'app doit dire lequel manque, et non « lien
  invalide ». Signalez-nous le message exact.

NOUVEAU DANS CE BUILD — LA COLONNE DE LECTURE
• Le texte occupe une colonne plus large et des marges resserrées, surtout visible
  sur Mac et iPad. Dites-nous si la ligne vous paraît trop longue à lire, et sur
  quel appareil : c'est un réglage, il se corrige.

CORRIGÉ DEPUIS LE BUILD 35
• Diaporama d'un document traduit : les libellés des diagrammes Mermaid restaient
  dans la langue d'origine, à l'écran comme dans l'export PowerPoint. Vérifiez-les,
  y compris sur une diapositive que vous n'aviez pas encore ouverte.
• Écran d'accueil : les fichiers récents et les rapports du coffre sont maintenant
  groupés par date — aujourd'hui, hier, 7 puis 30 derniers jours, ensuite par mois.
  L'heure s'affiche pour aujourd'hui et hier, la date courte au-delà.

DANS CETTE VERSION — LA TRADUCTION
Prenez un rapport écrit dans une langue que l'app ne parle pas à l'écran : allemand
ou italien si votre app est en français. Des exemples sont fournis dans le dépôt,
dossier tools/documents-test.

• Bouton 📖 dans la barre du lecteur → choisissez une langue. Le document se traduit
  paragraphe après paragraphe, du haut vers le bas, en partant de ce qui est à l'écran.
• Le bandeau au-dessus du document annonce la traduction et la langue d'origine.
  « Voir l'original » doit rendre le texte de départ, immédiatement, à l'identique —
  et « Voir la traduction » le ramener sans rien recalculer.
• Réglages → « Traduire les documents » : à l'ouverture, un document dans une autre
  langue se traduit tout seul.
• Ce qui NE doit PAS être traduit : le code entre accents graves et les blocs de code,
  les URL, les noms d'entités colorés, les cibles des liens. Signalez tout mot qui
  apparaîtrait deux fois, ou deux mots collés sans espace.
• Ce qui DOIT l'être : les titres, les tableaux, les listes, les libellés des
  diagrammes Mermaid, et les bulles des marqueurs de cartes (touchez un marqueur).
• Diaporama (bouton ▶) sur un document traduit : les diapositives doivent l'être
  aussi, y compris celles que vous n'avez pas encore ouvertes après un export
  PowerPoint.
• Si une langue demande un téléchargement, l'app doit le DIRE avant, par un bandeau,
  et ne rien télécharger sans que vous ayez touché « Traduire ».
• Sur un long rapport, comptez le temps : la traduction est volontairement
  progressive. Dites-nous si l'attente devient pénible, et sur quel appareil.

RAPPEL DES VERSIONS PRÉCÉDENTES — LES CARTES
• Ouvrez le document de démonstration, section « Carte géographique » : le fond
  doit être net, sans filigrane en travers, avec les noms de villes lisibles.
• Bouton des couches (en haut à droite de la carte) : basculez Clair / Sombre /
  OpenStreetMap. Les trois doivent se dessiner, et les marqueurs rester en place.
• Zoomez à fond, puis dézoomez : les noms restent nets, jamais pixelisés, et
  aucun lieu ne s'affiche deux fois dans deux alphabets.
• Bouton plein écran (⛶), en portrait ET en paysage.
• Exportez en PDF puis en Word : la carte doit y figurer entière, avec ses
  marqueurs et la mention de source en bas.
• En mode Avion : la carte annonce son indisponibilité et liste ses marqueurs,
  plutôt qu'un cadre vide.
• Sur un réseau lent (cellulaire, loin du wifi) : pendant que la carte charge, le cadre
  doit afficher « Chargement de la carte… » — et jamais rester gris et muet. Si c'est
  vraiment long, l'app bascule d'elle-même sur le fond OpenStreetMap, qui se remplit
  case par case.

OUVERTURE
• « Voir un exemple » pour charger le document de démonstration.
• Ouvrir un .md depuis Fichiers, le partage, ou un lien web.

RENDU
• Lecture fidèle (titres, tableaux, listes, citations) ; le titre du document ne doit PAS
  être coupé sous la barre d'outils.
• Diagrammes Mermaid + zoom plein écran.
• Cartes Leaflet : marqueurs, fonds de carte, bouton plein écran (portrait ET paysage).
• Callouts (note/tip/warning/bug) et coloration des entités.

RÉSUMÉ APPLE INTELLIGENCE (appareils compatibles)
• Bouton ✦ dans la barre du lecteur → « Résumé du document » : le résumé doit être structuré
  (chapitres, gras, listes). Le bouton est masqué si Apple Intelligence n'est pas disponible.

DISCUTER AVEC LE DOCUMENT (appareils compatibles)
• Bouton ✦ → « Discuter avec le document » : l'écran d'accueil propose des questions tirées
  du document lui-même, et pas seulement « Résume ce document ». Touchez-en une.
• Posez ensuite votre propre question : la réponse doit s'appuyer sur le seul contenu du
  rapport et rester structurée. Une question à laquelle le document ne répond pas doit être
  déclinée, pas inventée.
• Ouvrez un rapport rédigé dans une autre langue que l'app : les réponses doivent rester
  dans la langue de l'app.
• Changez la langue de l'app pendant une conversation : elle doit être réinitialisée, et
  l'app doit le dire.
• Bouton « Nouvelle conversation ». Enchaînez ensuite une dizaine de questions : quand
  l'historique devient trop long, l'app doit l'annoncer et poursuivre, pas se bloquer.

SIRI / SPOTLIGHT / RACCOURCIS
• « Ouvre le dernier rapport dans md Viewer », « Résume un rapport dans md Viewer » (nécessite un
  dossier de coffre configuré).

DIVERS
• Bouton « Ouvrir un fichier » (doit ouvrir le sélecteur).
• Mode sombre, rotation, export PDF, recherche, sommaire.
• iPhone, iPad et Mac.
```

---

## Beta App Review Information (testeurs externes uniquement)

- **Sign-in required** : Non.
- **Contact** : prénom/nom + e-mail + téléphone du responsable. ⚠️ à compléter.
- **Notes pour la review** (réutiliser celles de [`review-notes.md`](review-notes.md)) :
```
Aucun compte requis. Touchez « Voir un exemple » pour un document de démo couvrant toutes les
fonctionnalités. L'app fonctionne hors-ligne ; le réseau ne sert qu'aux tuiles de carte
(OpenFreeMap/OpenStreetMap) et au téléchargement d'un document via lien https. Le résumé utilise Apple
Intelligence ON-DEVICE (aucune donnée envoyée) et n'apparaît que sur appareil compatible.
```

---

## Rappels

- **Testeurs internes** (jusqu'à 100, membres de l'équipe) : aucune revue, build dispo
  immédiatement après traitement.
- **Testeurs externes** (jusqu'à 10 000, par groupe + lien public) : **revue bêta légère** requise
  une fois (puis automatique pour les builds suivants du même train).
- **Export compliance** : déjà géré (`ITSAppUsesNonExemptEncryption=false`).
- La version **macOS (Mac Catalyst)** se teste via **TestFlight pour Mac** (même fiche, archiver le
  Catalyst « My Mac »).
