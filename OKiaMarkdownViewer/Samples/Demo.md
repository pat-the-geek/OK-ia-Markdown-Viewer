---
titre: Démonstration OK-ia Viewer
source: ok-ia.ch
auteur: OK-ia
date: 2026-06-06
temps_lecture: 5 min
url: https://ok-ia.ch
---

# Démonstration OK-ia Viewer

Ce document met en évidence le rendu Markdown + Mermaid de l'application, fidèle au viewer
de [[ok-ia.ch]]. Il couvre les **callouts**, les *wiki-links*, la coloration des entités (NER)
et plusieurs types de diagrammes.

> [!tip] Astuce
> Touchez n'importe quel diagramme pour l'ouvrir en plein écran : pincez pour zoomer,
> glissez pour vous déplacer, double-tapez pour (dé)zoomer.

> [!warning] À savoir
> L'application fonctionne **100 % hors-ligne**. Les bibliothèques `marked` et `mermaid`
> sont embarquées dans l'app.

## Flowchart

```mermaid
flowchart TD
    A[Fichier .md] --> B{Frontmatter ?}
    B -->|oui| C[Titre + méta]
    B -->|non| D[Premier H1]
    C --> E[marked.parse]
    D --> E
    E --> F[mermaid.run]
    F --> G[Rendu OK-ia]
    style A fill:#E8972E,color:#111111
    style G fill:#111111,color:#FAFAF8
```

## Diagramme de séquence

```mermaid
sequenceDiagram
    participant U as Utilisateur
    participant A as App
    participant W as WKWebView
    U->>A: Ouvre un .md
    A->>W: injecte le Markdown (JSON)
    W->>W: pipeline OK-ia
    W-->>U: Rendu + diagrammes
    Note over W: marked + mermaid (offline)
```

## Diagramme de Gantt

```mermaid
gantt
    title Itération TestFlight
    dateFormat YYYY-MM-DD
    section Build
    Scaffold        :done,    s1, 2026-06-01, 1d
    Pipeline rendu  :done,    s2, after s1, 2d
    Vues SwiftUI    :active,  s3, after s2, 2d
    section Livraison
    Archive         :         s4, after s3, 1d
    TestFlight      :         s5, after s4, 1d
```

## Camembert (pie)

```mermaid
pie showData
    title Répartition du temps de rendu
    "Markdown" : 25
    "Mermaid" : 55
    "NER + callouts" : 20
```

## Mindmap

```mermaid
mindmap
  root((OK-ia Viewer))
    Ouverture
      Fichiers.app
      Partager
      Bouton intégré
    Rendu
      Markdown
      Mermaid
      Callouts
    Zoom
      Pincer
      Glisser
      Double-tap
```

## Carte géographique

Bloc `leaflet` à la façon d'Obsidian — points positionnés, fond de carte CARTO,
bouton plein écran (⛶) pour naviguer en portrait ou paysage.

```leaflet
id: demo-afrique-est
minZoom: 2
maxZoom: 12
height: 460px
marker: 0.347, 32.582, [[Kampala]]
marker: -1.943, 30.059, [[Kigali]]
marker: -3.373, 29.360, [[Bujumbura]]
marker: 7.862, 29.694, [[Soudan du Sud]]
marker: -4.322, 15.307, [[Kinshasa]]
```

## Tableau

| Fonction        | État    |
|-----------------|---------|
| Ouverture .md   | ✅      |
| Mermaid         | ✅      |
| Zoom diagramme  | ✅      |
| Hors-ligne      | ✅      |

## Entités

### Organisations
- [[OK-ia]]
- [[Apple]]

### Produits
- [[TestFlight]]
- [[WKWebView]]

### Personnes
- [[Patrick Ostertag]]

Le projet OK-ia s'appuie sur WKWebView d'Apple et sera distribué via TestFlight.
Patrick Ostertag pilote l'itération.
