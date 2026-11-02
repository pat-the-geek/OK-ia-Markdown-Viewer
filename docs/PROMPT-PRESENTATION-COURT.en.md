# Short prompt — a presentation for md Viewer, with Siri

Short version of the [presentation prompt](PROMPT-PRESENTATION-SVG.en.md), for Siri in iOS 27 and
any assistant that refuses a long message or cannot run code. Translated from the French version,
which is the one tested in Siri.

What it leaves out: maps, diagrams, base64 encoding of the SVGs (they stay as plain text, md Viewer
displays them as they are) and the Part A / Part B split that guards against instructions hidden in
documents. The photos are supplied by the user: an assistant that does not check its links makes up
addresses or adds none.

---

````text
Create a 10-slide presentation in Markdown for the md Viewer app.

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
- At the end of each slide, add a speaker note: <!-- one sentence -->
- Do not make up any figure. End with a "Sources and credits" slide.
- Deliver the whole file in a single markdown code block.

Illustrations: 4 SVG drawings, including the cover — real illustrations, not diagrams.
- Rich scenes: 25 to 40 shapes, several layers (background, middle ground, foreground), gradients (linearGradient), shadows as semi-transparent shapes, recognisable objects from the subject.
- The same 5-colour palette for all the drawings.
- Each SVG as plain text in the slide, with no blank line inside, starting with:
<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 1600 900" role="img" aria-label="description">
- A solid background, text of at least 48 px, 8 words at most per drawing.

Photos: use these free photos, one per slide, each followed by its caption on one line.
(paste your photos here, two lines per photo:
![description](https://upload.wikimedia.org/…/image.jpg)
> Caption · Author · Licence)
Do not add any other photo, except an upload.wikimedia.org address you actually found.
````

## Example: cheese fondue

````text
Create a 10-slide presentation in Markdown for the md Viewer app.

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
- At the end of each slide, add a speaker note: <!-- one sentence -->
- Do not make up any figure. End with a "Sources and credits" slide.
- Deliver the whole file in a single markdown code block.

Illustrations: 4 SVG drawings, including the cover — real illustrations, not diagrams.
- Rich scenes: 25 to 40 shapes, several layers (sky, mountains, foreground), gradients (linearGradient), shadows as semi-transparent shapes, recognisable objects (caquelon pot, burner, forks, bread, cheeses).
- The same 5-colour palette for all the drawings.
- Each SVG as plain text in the slide, with no blank line inside, starting with:
<svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 1600 900" role="img" aria-label="description">
- A solid background, text of at least 48 px, 8 words at most per drawing.

Photos: use these 4 free photos, one per slide, each followed by its caption on one line.
![Fondue served in Geneva](https://upload.wikimedia.org/wikipedia/commons/thumb/6/6a/Swiss_cheese_fondue.JPG/1280px-Swiss_cheese_fondue.JPG)
> Geneva · Brücke-Osteuropa · CC0
![Vacherin Fribourgeois AOP](https://upload.wikimedia.org/wikipedia/commons/thumb/c/c9/Vacherin_Fribourgeois_Rustic_1.JPG/1280px-Vacherin_Fribourgeois_Rustic_1.JPG)
> Vacherin Fribourgeois AOP · Guy Waterval · Apache 2.0
![Gruyères Castle](https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/12_Chateau_de_Gruy%C3%A8res_Photo_by_Giles_Laurent.jpg/1280px-12_Chateau_de_Gruy%C3%A8res_Photo_by_Giles_Laurent.jpg)
> Gruyères Castle · Giles Laurent · CC BY-SA 4.0
![The religieuse at the bottom of the caquelon](https://upload.wikimedia.org/wikipedia/commons/thumb/2/20/Religieuse_-_Fondue_au_fromage.jpg/1280px-Religieuse_-_Fondue_au_fromage.jpg)
> The religieuse · Rudolf H. Boettcher · CC BY-SA 4.0
Do not add any other photo, except an upload.wikimedia.org address you actually found.
````
