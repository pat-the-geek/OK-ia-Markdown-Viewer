#!/usr/bin/env python3
"""Illustrations de la feuille de route de md Viewer, une par version (1.5 à 2.0), en français et
en anglais (Patrick, 13/11/2026 : « on va faire une illustration pour chaque version : cela
représente les fonctions ajoutées »).

Même allure que l'illustration des quinze langues (`../post-langues/illustration.html`) :
1600 × 900, fond sombre, halo orange, le numéro à gauche, les fonctions en cartes à droite.
Icônes : Lucide (licence ISC), chargées depuis unpkg au rendu.

    python3 fabriquer.py          # écrit les HTML puis les JPEG (Chrome sans fenêtre, sips)
"""
import html, os, subprocess, sys

ICI = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# (icône Lucide, titre FR, ligne FR, titre EN, ligne EN, pour tous)
VERSIONS = [
    ("1.5", "Présenter, et le coffre partout", "Presenting, and the vault everywhere", "test", [
        ("smartphone", "L'iPhone télécommande", "avancer, dessiner, pointer", "iPhone as a remote", "advance, draw, point", False),
        ("timer", "Répéter", "chaque diapositive chronométrée", "Rehearse", "every slide timed", False),
        ("message-square-text", "Notes de l'orateur", "écrites dans l'app, proposées par l'IA", "Speaker notes", "written in the app, suggested by AI", False),
        ("file-text", "Polycopié PDF", "une à trois diapositives par page", "PDF handouts", "one to three slides per page", False),
        ("palette", "Vos couleurs", "logo, couleurs, police, PowerPoint", "Your colours", "logo, colours, font, PowerPoint", False),
        ("calendar-days", "Le point de la semaine", "ce qui est entré dans le coffre", "The week in review", "what came into the vault", False),
        ("file-spreadsheet", "Excel, CSV, Pages", "Keynote et Numbers aussi", "Excel, CSV, Pages", "Keynote and Numbers too", False),
        ("cloud", "Un coffre partout", "iCloud ou partage réseau", "One vault everywhere", "iCloud or a network share", False),
        ("highlighter", "Toutes vos annotations", "inscrites dans le fichier", "All your annotations", "written into the file", False),
    ]),
    ("1.6", "Le coffre ouvert à vos assistants", "Your vault, open to your assistants", "prevu", [
        ("file-code-2", "AGENTS.md", "un coffre qui s'explique", "AGENTS.md", "a vault that explains itself", True),
        ("plug", "Serveur MCP sur le Mac", "Claude, Codex, Copilot, ChatGPT", "MCP server on the Mac", "Claude, Codex, Copilot, ChatGPT", False),
        ("send", "Envoyer à un assistant", "documents et sources, d'un geste", "Send to an assistant", "documents and sources, in one gesture", True),
        ("search", "Interroger sur l'appareil", "sans aucune IA extérieure", "Ask on the device", "with no outside AI", False),
    ]),
    ("1.7", "Écrire", "Write", "prevu", [
        ("file-pen-line", "Un éditeur Markdown", "le Markdown et l'aperçu côte à côte", "A Markdown editor", "Markdown and preview side by side", True),
        ("presentation", "Éditeur de présentations", "plan, mises en page, notes", "Presentation editor", "outline, layouts, notes", False),
        ("sparkles", "L'IA de l'appareil", "raccourcir, clarifier, relire", "On-device AI", "shorten, clarify, proofread", False),
        ("chart-column", "Diagrammes sur demande", "depuis vos données, sans chiffre inventé", "Diagrams on request", "from your data, no invented figure", False),
        ("mic", "Parler à l'IA", "consignes et dictée à la voix", "Talk to the AI", "instructions and dictation by voice", False),
        ("bot", "Construire avec Claude", "le document se fabrique sous vos yeux", "Build with Claude", "the document builds before your eyes", False),
        ("layout-template", "Des modèles", "compte rendu, fiche, diaporama", "Templates", "minutes, notes, slideshow", False),
        ("git-compare", "Comparer deux versions", "ajouts et retraits surlignés", "Compare two versions", "additions and removals highlighted", False),
    ]),
    ("1.8", "Le coffre qui veille", "The vault keeps watch", "prevu", [
        ("tags", "Étiquettes et collections", "au format d'Obsidian", "Tags and collections", "in Obsidian's format", True),
        ("link", "Liens entre documents", "liens mdviewer:// et rétroliens", "Links between documents", "mdviewer:// links and backlinks", False),
        ("bell-ring", "Surveiller un nom", "une notification à chaque mention", "Watch a name", "a notification on every mention", False),
        ("calendar-range", "La frise", "les dates de vos documents", "The timeline", "the dates in your documents", False),
        ("network", "Le réseau des entités", "qui apparaît avec qui", "The entity network", "who appears with whom", False),
    ]),
    ("1.9", "De nouvelles sources", "New sources", "prevu", [
        ("audio-lines", "L'audio", "transcrit sur l'appareil", "Audio", "transcribed on the device", False),
        ("book-open", "Les livres EPUB", "lus dans le mode livre", "EPUB books", "read in book mode", False),
        ("mail", "Les e-mails", "avec leurs pièces jointes", "E-mails", "with their attachments", False),
    ]),
    ("2.0", "Présenter partout", "Present anywhere", "prevu", [
        ("watch", "L'Apple Watch", "télécommande au poignet", "Apple Watch", "a remote on your wrist", False),
        ("users", "SharePlay", "présenter à distance", "SharePlay", "present remotely", False),
        ("languages", "Diaporama traduit", "le public dans sa langue", "Translated slideshow", "the audience in its language", False),
        ("clapperboard", "Vidéo et page web", "votre répétition, partout", "Video and web page", "your rehearsal, anywhere", False),
    ]),
]

STATUT = {"test": ("en test · TestFlight", "in testing · TestFlight"), "prevu": ("prévu", "planned")}
POUR_TOUS = ("pour tous", "for everyone")


def page(v, langue):
    num, nom_fr, nom_en, statut, fonctions = v
    fr = langue == "fr"
    nom = nom_fr if fr else nom_en
    n = len(fonctions)
    colonnes = 3 if n >= 7 else (1 if n <= 3 else 2)
    rangees = -(-n // colonnes)
    reste = n % colonnes
    cartes = []
    for k, (icone, tfr, lfr, ten, len_, tous) in enumerate(fonctions):
        # La dernière carte prend la place qui reste : pas de case vide en bas de la grille.
        etendue = f' style="grid-column: span {colonnes - reste + 1}"' if reste and k == n - 1 else ""
        titre, ligne = (tfr, lfr) if fr else (ten, len_)
        marque = f'<span class="tous">{POUR_TOUS[0 if fr else 1]}</span>' if tous else ""
        cartes.append(f'''<div class="carte"{etendue}><i data-lucide="{icone}"></i>
      <div><div class="titre">{html.escape(titre)}{marque}</div><div class="ligne">{html.escape(ligne)}</div></div></div>''')
    taille_titre = 30 if colonnes == 3 else (40 if colonnes == 1 else 34)
    taille_ligne = 21 if colonnes == 3 else (28 if colonnes == 1 else 24)
    return f'''<!doctype html>
<html lang="{langue}">
<head>
<meta charset="utf-8">
<title>md Viewer {num}</title>
<!-- Fabriqué par fabriquer.py : ne pas modifier à la main. -->
<script src="https://unpkg.com/lucide@0.460.0/dist/umd/lucide.min.js"></script>
<style>
  *{{box-sizing:border-box;margin:0;padding:0}}
  html,body{{width:1600px;height:900px;overflow:hidden;background:#111111}}
  body{{font-family:-apple-system,"Helvetica Neue",Arial,sans-serif;color:#FAFAF8;position:relative}}
  .halo{{position:absolute;left:-220px;top:-160px;width:980px;height:980px;border-radius:50%;
    background:radial-gradient(circle,rgba(232,151,46,.30) 0%,rgba(232,151,46,.08) 45%,rgba(17,17,17,0) 70%)}}
  .gauche{{position:absolute;left:72px;top:70px;bottom:70px;width:440px;display:flex;flex-direction:column}}
  .marque{{font-size:40px;font-weight:700;letter-spacing:-.5px}}
  .marque span{{color:#E8972E}}
  .num{{font-size:250px;font-weight:800;line-height:.86;letter-spacing:-10px;color:#E8972E;margin-top:64px}}
  .nom{{font-size:42px;font-weight:700;line-height:1.15;margin-top:30px}}
  .statut{{align-self:flex-start;margin-top:24px;font-size:22px;font-weight:700;letter-spacing:.4px;
    padding:8px 18px;border-radius:999px;border:2px solid {"#E8972E" if statut == "test" else "#8f7be0"};
    color:{"#E8972E" if statut == "test" else "#b3a5f0"}}}
  .appareils{{margin-top:auto;font-size:24px;color:#a7a79c;letter-spacing:.5px}}
  .grille{{position:absolute;left:560px;right:70px;top:70px;bottom:70px;display:grid;
    grid-template-columns:repeat({colonnes},minmax(0,1fr));grid-template-rows:repeat({rangees},minmax(0,1fr));gap:18px}}
  .carte{{background:#1d1d21;border:1px solid #34343a;border-radius:22px;padding:20px 24px;
    display:flex;align-items:center;gap:20px}}
  .carte svg{{flex:none;width:{56 if colonnes == 2 else 46}px;height:{56 if colonnes == 2 else 46}px;color:#E8972E;stroke-width:1.8}}
  .titre{{font-size:{taille_titre}px;font-weight:700;line-height:1.15}}
  .ligne{{font-size:{taille_ligne}px;color:#a7a79c;line-height:1.25;margin-top:6px}}
  .tous{{display:inline-block;margin-left:10px;vertical-align:4px;font-size:15px;font-weight:700;
    letter-spacing:.4px;color:#111;background:#E8972E;border-radius:999px;padding:3px 10px}}
</style>
</head>
<body>
  <div class="halo"></div>
  <div class="gauche">
    <div class="marque">md <span>Viewer</span></div>
    <div class="num">{num}</div>
    <div class="nom">{html.escape(nom)}</div>
    <div class="statut">{STATUT[statut][0 if fr else 1]}</div>
    <div class="appareils">iPhone · iPad · iPhone Duo · Mac</div>
  </div>
  <div class="grille">
    {"".join(cartes)}
  </div>
  <script>lucide.createIcons();</script>
</body>
</html>
'''


def main():
    for v in VERSIONS:
        for langue in ("fr", "en"):
            base = os.path.join(ICI, f"version-{v[0]}-{langue}")
            with open(base + ".html", "w", encoding="utf-8") as f:
                f.write(page(v, langue))
            if "--html" in sys.argv:
                continue
            png = base + ".png"
            subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                            "--window-size=1600,900", "--virtual-time-budget=4000",
                            f"--screenshot={png}", "file://" + base + ".html"],
                           check=True, capture_output=True)
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "88", png,
                            "--out", base + ".jpg"], check=True, capture_output=True)
            os.remove(png)
            print(base + ".jpg")


if __name__ == "__main__":
    main()
