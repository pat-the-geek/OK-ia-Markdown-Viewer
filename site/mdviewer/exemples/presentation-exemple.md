---
titre: md Viewer — Présentation de démonstration
source: ok-ia.ch
auteur: OK-ia
date: 2026-07-12
url: https://ok-ia.ch/mdviewer/
---

# md Viewer

**Vos rapports Markdown, rendus parfaitement.**

Avancez d'un tap, aux flèches ← →, à la barre d'espace ou d'un glissement.

*Échap ou ✕ pour quitter · ▦ pour la vue d'ensemble · ⚙ pour les réglages*

---

## Au programme

1. Une diapositive par bloc séparé par `---` — rien d'autre à apprendre
2. Les **cinq familles Mermaid** : flowchart, séquence, gantt, pie, mindmap
3. Une **carte Leaflet** interactive
4. Tableaux, callouts, entités colorées
5. **Cinq thèmes**, **cinq transitions**, export **PowerPoint**

> [!tip] Tout de suite
> Touchez **⚙** et changez le thème : Clair, Sombre, Console, Sépia, Océan.
> Votre choix est mémorisé pour la prochaine fois.

---

## Flowchart — un flux, trois usages

```mermaid
flowchart LR
    R[Rapport .md] --> V[Lecture]
    R --> P[Diaporama]
    R --> X[Exports]
    V --> S[Résumé ✦]
    X --> W[Word .docx]
    X --> K[PowerPoint .pptx]
    style R fill:#E8972E,color:#111111
    style K fill:#111111,color:#FAFAF8
```

---

## Séquence — du coffre à l'écran

```mermaid
sequenceDiagram
    participant C as Coffre iCloud
    participant V as md Viewer
    participant U as Vous
    C-->>V: nouveau rapport détecté
    V->>U: il apparaît sur l'accueil
    U->>V: « Ouvre le dernier rapport » (Siri)
    V-->>U: rendu complet, hors-ligne
```

---

## Gantt — le trimestre en un regard

```mermaid
gantt
    title Feuille de route T3 2026
    dateFormat YYYY-MM-DD
    section Veille
    Sources cantonales   :done,   v1, 2026-07-01, 14d
    Détection tensions   :active, v2, after v1, 21d
    section Diffusion
    Rapport mensuel      :        d1, 2026-08-01, 3d
    Présentation membres :        d2, after d1, 1d
```

---

## Pie — la semaine en parts

```mermaid
pie showData
    title Signaux collectés
    "Régulation" : 32
    "Modèles & recherche" : 41
    "Adoption PME" : 19
    "Souveraineté" : 8
```

---

## Mindmap — les idées en étoile

```mermaid
mindmap
  root((IA romande))
    Régulation
      Consultation fédérale
      Règlement GE
    Compétences
      EPFL
      HES-SO
    Adoption
      PME
      Administrations
    Souveraineté
      Cloud suisse
```

---

## La Suisse romande en carte

Les cartes restent interactives en plein diaporama — et passent en plein écran.

```leaflet
id: presentation-romandie
minZoom: 7
maxZoom: 13
height: 430px
marker: 46.2044, 6.1432, [[Genève]]
marker: 46.5197, 6.6323, [[Lausanne]]
marker: 46.8065, 7.1620, [[Fribourg]]
marker: 46.2331, 7.3606, [[Sion]]
```

---

## En chiffres

| Fonction            | Rapport | Diaporama |
|---------------------|:-------:|:---------:|
| Mermaid (5 types)   | ✅      | ✅        |
| Cartes Leaflet      | ✅      | ✅        |
| Résumé ✦ on-device  | ✅      | —         |
| Export Word         | ✅      | —         |
| Export PowerPoint   | —       | ✅        |
| 100 % hors-ligne    | ✅      | ✅        |

Les tableaux restent **éditables** après export.

---

## Le mot de la veille

> [!quote] Entendu à Lausanne
> « L'enjeu n'est pas d'avoir des modèles suisses, mais de savoir ce que nos
> données deviennent. »

Les entités sont colorées ici aussi : la [[Confédération suisse]], l'[[EPFL]]
et [[OK-ia]] gardent leurs couleurs d'une diapositive à l'autre.

---

## Cinq transitions au choix

**Fondu** · **Poussée** · **Entrée** · **Échelle** · **Retournement 3D**

Changez-les dans **⚙ → Transition** et revenez en arrière pour comparer :
la transition joue dans les deux sens.

> [!note] Vue d'ensemble
> Touchez **▦** : toutes les diapositives en vignettes, sautez où vous voulez.

---

## Emportez cette présentation

**⚙ → Export → PowerPoint (.pptx)**

- Texte et **tableaux éditables** dans PowerPoint *et* Keynote
- Diagrammes et cartes intégrés en haute résolution
- Le fichier `.md` source reste la vérité — versionnable, diffable, léger

---

# Merci !

**md Viewer** — par [[OK-ia]]

*Ce que les algorithmes ignorent encore.*

[ok-ia.ch/mdviewer](https://ok-ia.ch/mdviewer/)
