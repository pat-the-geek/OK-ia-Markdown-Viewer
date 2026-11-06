# md Viewer 1.5

Le 6 novembre 2026, une fois la 1.4 en vente partout, Patrick a affecté à la 1.5 tous les points
restants : ceux qu'il avait gardés pour plus tard pendant la 1.4, et les défauts vus pendant la 1.4.
Rien n'est commencé.

Les travaux côté fornews.ai relevés pendant la 1.4 (filtre des entités à majuscule, genres en
cinq langues, reprise des diffs de `render.js`) n'en font pas partie : ils restent pour fornews 2.0,
comme décidé le 29 octobre 2026.

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

## Images embarquées perdues à l'export Word et PowerPoint (demande du 1er novembre 2026)

Vu en écrivant `docs/PROMPT-PRESENTATION-SVG.md` ; lu dans le code, pas essayé dans l'app.
`exportModel` (render.js) passe une image comme `{ t: 'image', src }`, mais `OOXMLExport` ne
télécharge que les `src` en `http` (`imageURLs`) : une image en `data:` n'est jamais résolue et
disparaît de l'export. Cela touche les images des documents importés (Word, PDF, PowerPoint, 1.4)
comme les SVG embarqués en base64 du prompt de présentation.

- [ ] Essayer d'abord dans l'app : exporter en Word et en PowerPoint un document importé avec images.
- [ ] Décoder les `data:image/…;base64` côté Swift (JPEG et PNG tels quels).
- [ ] SVG : `UIImage` ne lit pas le SVG — le rastériser en PNG côté JavaScript avant l'export,
      comme les diagrammes Mermaid (`svgToPng`), à la taille d'affichage × 2.
- [ ] Vérifier l'export PDF avec les mêmes documents.

## Défauts vus pendant la 1.4

- [ ] Anglais : « Search the Store », « Search the Store… » et « Neither the Store nor Analyzed
      Documents contain any documents. » disent « Store » ; l'anglais garde « vault » (seuls
      l'allemand, l'espagnol et l'italien disent « Store »).
- [ ] Un `<svg>` en clair dans le document (réponse d'IA) garde sa largeur : avec
      `width="1600"`, il déborde de la page en lecture et du cadre en diaporama (vu dans le lecteur
      en ligne le 2 novembre 2026 ; même CSS dans l'app, pas essayé dans l'app). Borner
      `svg[width]` hors Mermaid dans `style.css` et `presentation.css` (max-width 100 %, height
      auto), dans l'app et dans le lecteur en ligne. Les prompts contournent déjà avec
      `width="100%"`.
