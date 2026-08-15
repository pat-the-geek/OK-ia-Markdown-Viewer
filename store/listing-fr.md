# Fiche App Store (FR) — OK-ia Markdown Viewer

Langue principale : **Français (Suisse)**. Vaut pour **iOS** et **macOS** (mêmes textes).
Copier-coller dans App Store Connect → *Informations sur l'app* et *Version*.

---

## Nom de l'app (30 car. max)
**`OK-ia Markdown Viewer`** (24) ✅ retenu — doit être **unique** sur l'App Store.
Replis si déjà pris : `OK-ia — Markdown` / `md Viewer OK-ia`.

> Le nom d'affichage sur l'appareil reste **« md Viewer »** (`CFBundleDisplayName`), indépendant du nom store.

## Sous-titre (30 car. max)
- `Lecteur Markdown & Mermaid` (26) ✅
- alt : `Rapports Markdown hors-ligne` (28)

## Texte promotionnel (170 car. — modifiable sans review)
> Ouvrez vos fichiers Markdown avec diagrammes Mermaid, cartes Leaflet, callouts et coloration
> d'entités — fidèle à ok-ia.ch, 100 % hors-ligne.

## Description
```
OK-ia Markdown Viewer affiche vos fichiers Markdown exactement selon la charte du viewer ok-ia.ch —
typographie, couleurs et pipeline de rendu identiques.

FONCTIONNALITÉS
• Rendu Markdown fidèle (titres, tableaux, listes, citations)
• Diagrammes Mermaid : flowchart, séquence, gantt, pie, mindmap — avec zoom plein écran
• Cartes géographiques Leaflet (style plugin Obsidian) : marqueurs positionnés, fonds CARTO/OSM,
  bouton plein écran pour naviguer en portrait ou paysage
• Callouts Obsidian (note, tip, warning, bug…), wiki-links, coloration des entités (NER)
• Résumé du document par Apple Intelligence — sur l'appareil, mis en forme (chapitres, gras, listes)
  (nécessite un appareil compatible Apple Intelligence)
• Siri, Spotlight et Raccourcis : « Ouvre le dernier rapport », « Résume un rapport »…
• Sommaire automatique, recherche dans le document, taille de texte ajustable
• Export PDF et partage du fichier .md
• Mode sombre, portrait et paysage, iPhone + iPad + Mac
• 100 % hors-ligne : le rendu, les diagrammes, les callouts et le résumé IA ne nécessitent aucune
  connexion (seules les tuiles de fond de carte se chargent en ligne)

Ouvrez un .md depuis Fichiers, le partage iOS, une autre app, ou un lien web (mdviewer://).

« Ce que les algorithmes ignorent encore. » — ok-ia.ch
```

## Mots-clés (100 car. max, séparés par des virgules, sans espaces superflus)
```
markdown,mermaid,diagramme,leaflet,carte,obsidian,callout,rapport,résumé,ia,pdf,md
```
(~95 car. — ajuster si besoin ; « siri/raccourcis » sont indexés via les phrases App Shortcuts)

## URLs
- **URL d'assistance** (obligatoire) : `https://ok-ia.ch` ✅
- **URL marketing** (facultative) : `https://ok-ia.ch`
- **URL politique de confidentialité** (obligatoire) : `https://ok-ia.ch/mdviewer/confidentialite.html` ✅
  → héberger le fichier [`mdviewer-confidentialite.html`](mdviewer-confidentialite.html) à cette adresse.

## Catégorie
- Principale : **`Productivité`** ✅
- Secondaire (facultative) : `Utilitaires`

## Classification par âge
- Visée : **4+**. Au questionnaire, tout répondre « Aucun/Jamais ».
- ⚠️ Point d'attention : la question **« Accès web sans restriction »** → répondre **Non**
  (l'app affiche des documents Markdown, ce n'est pas un navigateur). Les liens externes s'ouvrent
  dans Safari/le navigateur système, ce qui n'est pas un accès web intégré sans restriction.

## Copyright
- **`© 2026 OK-ia`** ✅

## Prix
- **Gratuit** ✅ — aucune disponibilité limitée, disponible dans tous les pays.

## Nouveautés de cette version (release notes 1.1.0)
```
Cinq langues, et vos rapports deviennent conversationnels.

NOUVEAU
• Interface en français, anglais, allemand, espagnol et italien — l'app suit la
  langue de votre appareil, ou celle que vous choisissez dans les Réglages
• Discuter avec le document : posez vos questions sur le rapport ouvert. Les
  réponses sont structurées en chapitres et s'appuient sur son seul contenu
• L'écran de départ propose des questions tirées du document lui-même
• Les réponses sont rédigées dans la langue de l'app, même si le rapport est
  écrit dans une autre
• Export PDF au format A4 (ou Letter selon votre région) : un vrai document
  paginé, qui s'annote au Pencil dans Notes ou se transmet tel quel. Les cartes
  et les diagrammes y figurent en entier, et aucun titre ne reste seul en bas
  d'une page

PLUS RAPIDE, PLUS CLAIR
• Les rapports riches en images s'affichent immédiatement : les images se
  chargent au fil de la lecture au lieu de retarder tout le document
• La coloration des entités fonctionne désormais quelle que soit la langue du
  rapport
• Hors connexion, une carte annonce son indisponibilité et liste ses marqueurs,
  au lieu d'afficher un cadre gris
• Les documents très volumineux affichent un message d'attente plutôt qu'un
  écran vide

Le résumé et la discussion nécessitent un appareil compatible Apple Intelligence
(iOS 26 ou ultérieur). Comme le reste de l'app, ils fonctionnent sur l'appareil :
aucun texte n'est envoyé nulle part.
```

<details>
<summary>Archive — release notes 1.0.0</summary>

```
Première version publique.
• Lecture de Markdown fidèle à ok-ia.ch
• Diagrammes Mermaid avec zoom
• Cartes Leaflet avec plein écran
• Callouts, wiki-links, coloration d'entités
• Résumé du document par Apple Intelligence (sur l'appareil)
• Actions Siri / Spotlight / Raccourcis
• Export PDF, recherche, sommaire
• iPhone, iPad et Mac
```

</details>
