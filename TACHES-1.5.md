# md Viewer — pour une prochaine version (après la 1.4)

Ce que Patrick a demandé de garder pour plus tard. Rien n'est commencé ; chaque point attend son
feu vert.

## Notes de l'orateur (demande du 1er novembre 2026)

Patrick : « Je ne trouve pas comment ajouter les notes de l'orateur », puis « Prend note pour une
prochaine version ».

**Aujourd'hui (1.4).** md Viewer n'écrit pas de notes : il lit celles du fichier, les commentaires
HTML d'une diapositive (`<!-- … -->`, avant le `---` suivant). `presentation.js` les extrait
(`notes(index)`), et seul le mode présentateur les montre (`ModePresentateur.swift`, option Analytic
et second écran). L'import PowerPoint les y range (« Notes de l'orateur : »). La syntaxe n'est
documentée nulle part pour l'utilisateur.

**À faire :**
- [ ] Écrire et modifier les notes de chaque diapositive dans l'app : depuis le mode présentateur,
      la grille des vignettes de la présentation générée, ou les deux. Elles s'écrivent dans le
      `.md` en commentaire HTML sous la diapositive (`--` interdit dans un commentaire : le
      remplacer, comme l'import). ⚠️ Écrire dans le fichier change son empreinte : les annotations
      du document y sont liées (`IdentiteDocument`) — exclure les notes de l'identité, comme les
      marques des diapositives masquées, ou faire suivre les annotations.
- [ ] Reprendre les notes dans l'**export PowerPoint** (`OOXMLExport` n'écrit pas de
      `notesSlide`) : aller-retour complet avec l'import.
- [ ] La **conversion en présentation** par Apple Intelligence pourrait proposer des notes tirées
      du rapport (à décider : jamais de chiffre absent du rapport).
- [ ] Documenter la syntaxe : page `mdviewer/import-et-annotations.html` (ou une page du
      diaporama), base du Terminal IA (`public/data/mdviewer-kb.md`), `docs/GUIDE-PRESENTATION.md`.

## Défauts vus pendant la 1.4

- [ ] Anglais : « Search the Store », « Search the Store… » et « Neither the Store nor Analyzed
      Documents contain any documents. » disent « Store » ; l'anglais garde « vault » (seuls
      l'allemand, l'espagnol et l'italien disent « Store »).
