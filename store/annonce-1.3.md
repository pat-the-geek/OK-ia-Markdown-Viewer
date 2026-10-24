# Annonce de la 1.3 — à publier le jour de la sortie

Compte : @ok_ia_ch@techhub.social. Un fil de trois messages, comme le 2026-10-09.
Rien ne part sans le feu vert de Patrick.

| Message | Langue | Médias (`store/entete-1.3/`) |
|---|---|---|
| 1 | anglais | `mastodon-en.jpg` (illustration sombre) + `entete-en-mastodon.jpg` (en-tête App Store) |
| 2, en réponse | français | `mastodon-fr.jpg` + `entete-fr-mastodon.jpg` |
| 3, en réponse | les deux | la vidéo `~/Developer/OK-ia/public/mdviewer/videos/md-viewer-duo-livre.mp4` (64 s, sans son, 26 Mo) |

Mastodon ne mêle pas vidéo et images dans un même message : la vidéo a le sien. Elle a déjà servi
le 2026-10-09 (film du Duo, en test) ; ici, elle montre ce qui est désormais en vente.

---

## Message 1 — anglais (deux images)

```
md Viewer 1.3 is out 📖

On iPhone Duo half-folded, your Markdown reports open like a book: two pages either side of the hinge, turned with your finger. Maps, images and diagrams never split across pages.

Also new: turn a report into a presentation with Apple Intelligence, on-device. Five reading themes. Every command one tap away.

Free, iPhone · iPad · iPhone Duo · Mac.
https://ok-ia.ch/mdviewer/?lang=en

#Apple #iOS #iPhoneDuo #Markdown #AppleIntelligence
```

## Message 2 — français, en réponse (deux images)

```
md Viewer 1.3 est sortie 📖

Sur l'iPhone Duo à moitié replié, vos rapports Markdown s'ouvrent comme un livre : deux pages de part et d'autre de la charnière, tournées du doigt. Cartes, images et diagrammes ne sont jamais coupés.

Aussi : un rapport devient une présentation grâce à Apple Intelligence, sur l'appareil. Cinq thèmes de lecture.

Gratuit, iPhone · iPad · iPhone Duo · Mac.
https://ok-ia.ch/mdviewer/

#Apple #iOS #iPhoneDuo #Markdown
```

## Texte alt — en-tête App Store, anglais (`entete-en-mastodon.jpg`)

```
White background. On the left, "md Viewer" in orange, then the headline "Read it like a book." and the line "On iPhone Duo half-folded, your Markdown files become two pages you turn with your finger." On the right, an iPhone Duo half-folded like an open book: the left page shows the title "Annual Report 2026", a short introduction and a photo of green cliffs above a winding road; the right page continues with the "Public works" section. A column of round toolbar buttons sits along the inner edge of the left page.
```

## Message 3 — en réponse, avec la vidéo

```
See the page turn — and the report become a presentation. 🎬
Voir la page tourner, et le rapport devenir une présentation.
```

## Texte alt — illustration sombre, anglais (`mastodon-en.jpg`)

```
Dark illustration with amber accents. On the left, a terminal prompt "patrick@fribourg:~$ open report.md --book", the title "md Viewer", "1.3 · out now", the headline "Read it like a book." and the line "iPhone Duo half-folded: two pages, either side of the hinge, turned with your finger." Three points follow: "Report → presentation, on-device", "Five reading themes", "Free · iPhone · iPad · Duo · Mac". On the right, an iPhone Duo half-folded like an open book, showing an annual report with a photo of green cliffs on the left page and the "Public works" section on the right. Footer: "App Store · ok-ia.ch/mdviewer".
```

## Texte alt — illustration sombre, français (`mastodon-fr.jpg`)

```
Illustration sombre aux accents ambre. À gauche, une invite de terminal « patrick@fribourg:~$ open report.md --book », le titre « md Viewer », « 1.3 · disponible », la phrase « Lisez comme dans un livre. » et la ligne « iPhone Duo à moitié replié : deux pages, de part et d'autre de la charnière, tournées du doigt. » Suivent trois points : « Rapport → présentation, sur l'appareil », « Cinq thèmes de lecture », « Gratuit · iPhone · iPad · Duo · Mac ». À droite, un iPhone Duo à moitié replié, ouvert comme un livre, sur un rapport d'activité : une photo de falaises vertes sur la page de gauche, la section « Travaux » sur celle de droite. Pied : « App Store · ok-ia.ch/mdviewer ».
```

## Texte alt — en-tête App Store, français (`entete-fr-mastodon.jpg`)

```
Fond blanc. À gauche, « md Viewer » en orange, puis la phrase « Lisez comme dans un livre. » et la ligne « Sur l'iPhone Duo à moitié replié, vos fichiers Markdown deviennent deux pages qui se tournent du doigt. » À droite, un iPhone Duo à moitié replié, ouvert comme un livre : sur la page de gauche, le titre « Rapport d'activité 2026 », une courte introduction et une photo de falaises vertes au-dessus d'une route sinueuse ; sur la page de droite, la suite avec la section « Travaux ».
```

## Texte alt — vidéo (bilingue)

```
Screen recording on iPhone Duo, no sound. Half-folded, a report opens as a book and pages are turned with a finger; then the report is converted into a presentation and played as a slideshow. — Enregistrement d'écran sur l'iPhone Duo, sans son : à moitié replié, un rapport s'ouvre comme un livre et l'on tourne les pages du doigt ; puis le rapport devient une présentation, jouée en diaporama.
```

---

## Site perso (@patcedar) — anglais, ton dev

Publié par Patrick lui-même (pas de jeton pour ce compte). Image : `store/entete-1.3/mastodon-dev.jpg`
(source `mastodon-dev.html`), texte alt plus bas.

```
md Viewer 1.3 just shipped 📖 — iPhone Duo support, the hard way.

• Fold position from reservedRegions(kind: .division), never screen ÷ 2
• Hinge posture via UIHingeInteraction → half-fold = book mode
• Page curl: CATransformLayer strips + gravity, around X when the Duo goes laptop
• Two WKWebViews, one paginator that never splits a map or a table
• 22 TestFlight builds in 2 days (66 → 87)

https://ok-ia.ch/mdviewer/?lang=en

#Apple #iOSDev #SwiftUI #iPhoneDuo #WebKit
```

### Texte alt — illustration dev (`mastodon-dev.jpg`)

```
Dark illustration with amber accents. Top left, a terminal prompt "patrick@fribourg:~$ git log --oneline v1.2.2..v1.3 | wc -l" and the title "md Viewer 1.3". Below, a Swift code panel with three commented snippets: the fold read from proxy.reservedRegions(kind: .division, options: .includeInactive) "not at width / 2"; a UIHingeInteraction that switches to book mode when the hinge status is .partiallyOpen; and the page curl, a CATransform3DMakeRotation around the Y axis, or the X axis in laptop posture. Three stat tiles: "22 TestFlight builds · 2 days", "2 WKWebViews · 1 paginator", "0 maps split across pages". On the right, an iPhone Duo half-folded like an open book showing "Annual Report 2026", with an amber marker on the hinge labelled "x 455 · 40 pt". Footer: "SwiftUI · UIKit · WebKit · Apple Intelligence on-device · ok-ia.ch/mdviewer".
```
