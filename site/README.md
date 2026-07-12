# Site ok-ia.ch — page « md Viewer »

Contenu prêt à téléverser sur l'hébergement de **ok-ia.ch**.

## Fichiers

- `mdviewer/index.html` — la page produit **md Viewer** (FR/EN, bascule de langue,
  illustrations SVG inline, même patron que `/fornews/`). Aucune dépendance à part
  `/style.css` (déjà sur le site) et la police Nunito (Google Fonts).
- `mdviewer/confidentialite.html` — copie de `store/mdviewer-confidentialite.html`,
  liée depuis la page.
- `style.css` — **copie locale** de `https://ok-ia.ch/style.css`, uniquement pour la
  prévisualisation locale (`.claude/launch.json` → serveur `mdviewer-site`,
  http://localhost:8766/mdviewer/). Ne pas téléverser (le site a déjà le sien).

## Mise en ligne

1. Téléverser le dossier `mdviewer/` à la racine du site → `https://ok-ia.ch/mdviewer/`.
2. La page ne figure pas encore dans le menu des autres pages. Ajouter dans le
   `<ul class="nav-links">` de chaque page (après l'entrée fornews.ai) :

   ```html
   <li><a href="/mdviewer/">md Viewer</a></li>
   ```

   Et **supprimer l'entrée « Valeurs »** du menu général sur toutes les pages du site
   (déjà absente de `mdviewer/index.html`) :

   ```html
   <li><a href="/vision.html#valeurs">Valeurs</a></li>   <!-- à retirer -->
   ```

3. `TODO` dans `index.html` : remplacer le lien `#` du bouton
   « Rejoindre la bêta TestFlight / Join the TestFlight beta » (2 occurrences,
   FR et EN) par le lien d'invitation TestFlight (ou App Store plus tard).

## Langue

Même mécanique que fornews : `?lang=fr|en` dans l'URL, sinon choix mémorisé
(`localStorage['mdv-lang']`), sinon langue du navigateur (français → FR, sinon EN).
