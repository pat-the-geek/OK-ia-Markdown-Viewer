# Site ok-ia.ch — page « md Viewer »

Contenu prêt à téléverser sur l'hébergement de **ok-ia.ch**.

## Fichiers

- `mdviewer/index.html` — la page produit **md Viewer** (FR/EN, bascule de langue,
  illustrations SVG inline, même patron que `/fornews/`). Aucune dépendance à part
  `/style.css` (déjà sur le site) et la police Nunito (Google Fonts).
- `mdviewer/confidentialite.html` — copie de `store/mdviewer-confidentialite.html`,
  liée depuis la page.
- `mdviewer/exemples/rapport-exemple.md` et `mdviewer/exemples/presentation-exemple.md` —
  fichiers de démonstration liés depuis la section « Essayez, tout de suite » :
  téléchargement direct + lien profond `mdviewer://open?url=https://ok-ia.ch/mdviewer/exemples/…`
  (ouvre le fichier dans l'app si elle est installée). ⚠️ Les liens profonds pointent vers
  ok-ia.ch : ils ne fonctionneront qu'une fois le dossier déployé.
- `style.css` — **copie locale** de `https://ok-ia.ch/style.css`, uniquement pour la
  prévisualisation locale (`.claude/launch.json` → serveur `mdviewer-site`,
  http://localhost:8766/mdviewer/). Ne pas téléverser (le site a déjà le sien).

## Mise en ligne

Le site **n'est pas déployé par téléversement** : il vit dans le dépôt
[`pat-the-geek/OK-ia`](https://github.com/pat-the-geek/OK-ia), sous `public/mdviewer/`,
et c'est le **merge sur `main` qui déclenche la publication** (`deploy.yml`).

1. Reporter les fichiers modifiés de `site/mdviewer/` vers `public/mdviewer/` du dépôt
   du site. En pratique, seul `index.html` change.
2. Ouvrir une **pull request ciblant `main`** — ce dépôt interdit le push direct sur
   `main` et impose une branche `claude/<description>-<session-id>` pour les assistants
   (voir son `CLAUDE.md`). Le merge publie.

`site/style.css` est une copie locale pour la prévisualisation : ne jamais la reporter,
le site a la sienne.

> Vérifié le 2026-08-01 — deux tâches que ce fichier réclamait sont **faites**, ne pas
> les refaire : l'entrée `md Viewer` figure dans les 33 menus principaux du site, et
> l'entrée « Valeurs » n'existe plus nulle part (les 4 pages d'archives ont un menu
> contextuel réduit, c'est voulu). Le bouton « Rejoindre la bêta TestFlight » a lui aussi
> disparu au profit des liens App Store — il ne reste aucun `href="#"` dans la page.

## Langue

Même mécanique que fornews : `?lang=fr|en` dans l'URL, sinon choix mémorisé
(`localStorage['mdv-lang']`), sinon langue du navigateur (français → FR, sinon EN).
