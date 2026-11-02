# Mini prompt — a presentation for md Viewer, with Siri

Short version of the [Pro Max prompt](PROMPT-PRESENTATION-SVG.en.md), for Siri in iOS 27 and any
assistant that refuses a long message or cannot run code. Translated from the French version, which
is the one tested in Siri (see [PROMPT-PRESENTATION-COURT.md](PROMPT-PRESENTATION-COURT.md) for the
test notes).

The user supplies the facts and the photos: without facts, Siri writes from memory and gets things
wrong; it finds no photos on its own. The Mini prompt leaves out maps, diagrams, base64 encoding of
the SVGs (they stay as plain text, md Viewer displays them as they are) and the Part A / Part B
split that guards against instructions hidden in documents.

---

````text
Create an 11-slide presentation in Markdown for the md Viewer app.

Subject: (your subject in one or two sentences)

Rules:
- Start with:
---
title: (the title)
type: presentation
lang: en
---
- Separate the slides with a line that contains only ---
- One idea per slide, 30 words at most, a ## title that makes a claim.
- A blank line between each element: title, text, image or SVG, caption, note.
- Slide 1: the cover, an SVG alone with the title drawn inside it.
- At the end of each slide, a speaker note drawn from the facts: <!-- one sentence -->
- Use all the facts below and no others. End with "Sources and credits": these sources and the photos.
- Deliver the whole file in a single markdown code block.

Facts:
(paste your facts here, one per line, each with its source:
- The fact, figure or date (source))

Illustrations: 4 SVG drawings, including the cover — real illustrations, not diagrams.
- Rich scenes: 25 to 40 shapes, several layers (background, middle ground, foreground), gradients (linearGradient), shadows as semi-transparent shapes, recognisable objects from the subject.
- The same 5-colour palette for all the drawings.
- Each SVG as plain text in the slide, with no blank line inside, starting with:
<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 1600 900" role="img" aria-label="description">
- A solid background, text of at least 48 px, 8 words at most per drawing.

Photos: these photos, one per slide, each followed by its caption.
(paste up to 6 photos here, two lines per photo:
![description](https://commons.wikimedia.org/wiki/Special:FilePath/File_name.jpg?width=1280)
> Caption · Author · Licence)
````

## Example: cheese fondue

````text
Create an 11-slide presentation in Markdown for the md Viewer app.

Subject: cheese fondue in Switzerland, vacherin and moitié-moitié: history, regions, side dishes, new recipes.

Rules:
- Start with:
---
title: (the title)
type: presentation
lang: en
---
- Separate the slides with a line that contains only ---
- One idea per slide, 30 words at most, a ## title that makes a claim.
- A blank line between each element: title, text, image or SVG, caption, note.
- Slide 1: the cover, an SVG alone with the title drawn inside it.
- At the end of each slide, a speaker note drawn from the facts: <!-- one sentence -->
- Use all the facts below and no others. End with "Sources and credits": these sources and the photos.
- Deliver the whole file in a single markdown code block.

Facts:
- Oldest recipe close to today's: Zurich, 1699 (Wikipedia).
- Almost unknown in most regions until the mid-20th century; the Swiss Cheese Union made it the national dish, the army adopted it in the 1950s (Swissinfo, 2022).
- Moitié-moitié: half Gruyère AOP, half Vacherin Fribourgeois AOP, with white wine, served hot (Fribourg Region).
- Pure vacherin: with water, no wine, served lukewarm, with bread and potatoes (Terroir Fribourg).
- Gruyère AOP: Fribourg, Vaud, Neuchâtel, Jura, Bernese Jura; at least 5 months of ripening (Wikipedia).
- Neuchâtel style: Gruyère and Emmental; Valais style: with raclette cheese; eastern Switzerland: Appenzeller and cider (Wikipedia).
- The religieuse: the toasted crust at the bottom of the caquelon pot.
- With tea, the stomach empties faster than with wine, but the discomfort is the same (BMJ, 2010).
- New ideas: with whisky (Gault&Millau), Neapolitan with fusilli and tomato (Fooby), fondue train and boat in the Gruyère region (Fribourg Region).

Illustrations: 4 SVG drawings, including the cover — real illustrations, not diagrams.
- Rich scenes: 25 to 40 shapes, several layers (sky, mountains, foreground), gradients (linearGradient), shadows as semi-transparent shapes, recognisable objects (caquelon pot, burner, forks, bread, cheeses).
- The same 5-colour palette for all the drawings.
- Each SVG as plain text in the slide, with no blank line inside, starting with:
<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 1600 900" role="img" aria-label="description">
- A solid background, text of at least 48 px, 8 words at most per drawing.

Photos: these 6 photos, one per slide, each followed by its caption.
![Fondue in Geneva](https://commons.wikimedia.org/wiki/Special:FilePath/Swiss_cheese_fondue.JPG?width=1280)
> Geneva · Brücke-Osteuropa · CC0
![Fondue restaurant sign in Geneva](https://commons.wikimedia.org/wiki/Special:FilePath/Fondue_au_fromage.jpg?width=1280)
> Geneva · BiiJii · CC0
![Vacherin Fribourgeois AOP](https://commons.wikimedia.org/wiki/Special:FilePath/Vacherin_Fribourgeois_Rustic_1.JPG?width=1280)
> Vacherin Fribourgeois · Guy Waterval · Apache 2.0
![Gruyère ripening cellar](https://commons.wikimedia.org/wiki/Special:FilePath/Fromagerie_gruy%C3%A8res-affinage.jpg?width=1280)
> Ripening cellar, Gruyères · SuperManu · CC BY-SA 3.0
![Gruyères Castle](https://commons.wikimedia.org/wiki/Special:FilePath/12_Chateau_de_Gruy%C3%A8res_Photo_by_Giles_Laurent.jpg?width=1280)
> Gruyères Castle · Giles Laurent · CC BY-SA 4.0
![The religieuse at the bottom of the caquelon](https://commons.wikimedia.org/wiki/Special:FilePath/Religieuse_-_Fondue_au_fromage.jpg?width=1280)
> The religieuse · Rudolf H. Boettcher · CC BY-SA 4.0
````
