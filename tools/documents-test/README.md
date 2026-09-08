# Documents de test pour la traduction

Quatre documents pour éprouver la version 1.2 sur un appareil réel : un rapport et une
présentation, en italien et en allemand. Ouvrez-les avec l'app réglée sur une autre langue —
le français, par exemple — et l'option **Traduire les documents** activée dans les Réglages.

| Fichier | Ce qu'il sert à voir |
|---|---|
| `Rapporto annuale 2026 (it).md` | la vague sur un document long, italien → autre langue |
| `Jahresbericht 2026 (de).md` | le même, en allemand : c'est la langue qui rallonge le plus |
| `Presentazione conti 2026 (it).md` | le diaporama et son export PowerPoint |
| `Präsentation Rechnung 2026 (de).md` | idem |

## Ce que chaque document contient, et pourquoi

Rien n'y est décoratif. Chaque élément éprouve un point qui a demandé du travail :

- **wiki-liens** `[[Losone]]`, `[[Köniz]]` — leur cible ne doit jamais être traduite, sans quoi
  le coffre et la coloration d'entités cassent ;
- **code inline** `calcolaTotale()`, `berechneTotal()` et un bloc Python — le code n'est la
  langue de personne ;
- **diagramme Mermaid** — les libellés se traduisent, `flowchart TD` non, et les branches
  « Sì / No », « Ja / Nein » sont les libellés d'un seul mot qui avaient été perdus une fois ;
- **carte Leaflet** — coordonnées intactes, libellés de marqueurs traduits sans que la carte
  se redessine ;
- **tableau, listes, cases à cocher, callout, frontmatter** ;
- **URL affichée en clair**, qui ne doit pas être traduite ;
- **section Entités** (`## Entità`, `## Entitäten`), qui alimente la coloration ;
- des **phrases dont la syntaxe se réorganise** en français : c'est là qu'on voit si les
  morceaux se remettent dans le bon ordre.

## Un défaut connu, que ces documents ont révélé

Le modèle recopie parfois le contenu protégé dans le segment voisin, et l'on lit alors
« du quartier d'Arcegno **Arcegno** » ou « la fonction calculateTotalest utilisée
`calcolaTotale()` ». Le morceau protégé est bien intact — c'est sa copie, dans le texte
traduit d'à côté, qui est en trop. Ce n'est pas corrigé dans la 1.2 (32).
