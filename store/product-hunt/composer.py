# -*- coding: utf-8 -*-
"""Compose les images de galerie Product Hunt de md Viewer (1270 × 760) avec Chrome sans fenêtre.

    python3 store/product-hunt/composer.py

Lit les captures App Store en anglais (store/screenshots/…/en/), la scène du lecteur
(store/scenes/en/1-lecteur.md) et l'image de la traduction publiée sur Mastodon pour la 1.2
(sources/traduction-1-2-mastodon.png). Écrit les 7 PNG à côté de ce script. À relancer après
un nouveau jeu de captures (scripts/screenshots.sh en). Chrome doit être installé ; les titres
utilisent Nunito (Google Fonts), la machine doit donc être en ligne.
Kit de lancement : dépôt OK-ia, Stratégie/product-hunt-md-viewer.md."""
import html, os, subprocess

ICI = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.dirname(ICI)
HTML = os.path.join(ICI, "html")
MAC = "../../screenshots/mac/en/"          # chemins vus depuis html/
IPHONE = "../../screenshots/iphone-6.9/en/"
IPAD = "../../screenshots/ipad-13/en/"
SRC = "../sources/"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

CSS = """
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@800;900&display=swap');
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 1270px; height: 760px; overflow: hidden; }
body { background: #FAFAF8; color: #111; font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
       position: relative; }
.marque { position: absolute; top: 34px; left: 48px; font-family: 'Nunito', sans-serif; font-weight: 900;
          font-size: 22px; letter-spacing: -0.3px; display: flex; align-items: center; gap: 7px; }
.marque .barre { display: inline-block; width: 22px; height: 6px; border-radius: 3px; background: #E8972E; }
.titre { position: absolute; left: 48px; top: 78px; right: 48px; font-family: 'Nunito', sans-serif;
         font-weight: 900; font-size: 50px; line-height: 1.05; letter-spacing: -1px; }
.titre em { font-style: normal; color: #E8972E; }
.sous { position: absolute; left: 50px; top: 140px; right: 48px; font-size: 21px; color: #6E6E66; }
.scene { position: absolute; left: 48px; right: 48px; top: 196px; bottom: 0; }
.cap { position: absolute; border-radius: 12px; overflow: hidden; background: #fff;
       box-shadow: 0 18px 50px rgba(40, 30, 10, 0.16), 0 2px 6px rgba(40, 30, 10, 0.08);
       border: 1px solid #E8E6E0; }
.cap img { display: block; width: 100%; height: auto; }
.etiquette { position: absolute; font-size: 14px; font-weight: 700; letter-spacing: 0.06em;
             text-transform: uppercase; padding: 6px 12px; border-radius: 20px; z-index: 3; }
.avant { background: #131310; color: #FBC168; }
.apres { background: #E8972E; color: #fff; }
.brut { position: absolute; background: #131310; color: #FBC168; border-radius: 12px;
        font: 15px/1.55 ui-monospace, 'SF Mono', Menlo, monospace; padding: 22px 24px; overflow: hidden;
        white-space: pre-wrap; box-shadow: 0 18px 50px rgba(40, 30, 10, 0.16); }
.pastilles { position: absolute; display: flex; gap: 14px; z-index: 3; }
.pastille { background: #fff; border: 2px solid #E8972E; color: #111; font-weight: 800; font-size: 22px;
            padding: 10px 22px; border-radius: 40px; box-shadow: 0 8px 22px rgba(40,30,10,.12); }
.gros { position: absolute; font-family: 'Nunito', sans-serif; font-weight: 900; font-size: 78px;
        line-height: 1.02; letter-spacing: -2px; }
.gros span { display: block; }
.gros span:nth-child(2) { color: #E8972E; }
.rec { overflow: hidden; background: #FAFAF8; }
.rec img { display: block; max-width: none; }
.fen { position: absolute; border-radius: 12px; overflow: hidden; background: #FAFAF8; border: 1px solid #E8E6E0;
       box-shadow: 0 18px 50px rgba(40, 30, 10, 0.16), 0 2px 6px rgba(40, 30, 10, 0.08); }
.barre-fen { height: 30px; background: #F1F2F6; border-bottom: 1px solid #E4E5EA; display: flex; align-items: center;
             gap: 7px; padding-left: 12px; font-size: 13px; color: #333; }
.barre-fen i { width: 11px; height: 11px; border-radius: 50%; background: #FF5F57; display: inline-block; }
.barre-fen i:nth-child(2) { background: #FEBC2E; } .barre-fen i:nth-child(3) { background: #28C840; }
.barre-fen b { margin-left: 8px; font-weight: 600; }
.format { display: flex; flex-direction: column; gap: 4px; background: #fff; border: 2px solid #E8972E; border-radius: 14px;
          padding: 16px 22px; box-shadow: 0 8px 22px rgba(40,30,10,.10); }
.format b { font-size: 26px; font-weight: 800; } .format span { font-size: 17px; color: #6E6E66; }
.petit { position: absolute; font-size: 21px; color: #6E6E66; line-height: 1.5; }
"""


def recadre(src, x, y, w, h, largeur, extra="", source=2560):
    """Affiche la zone (x, y, w, h) d'une capture 2560 px, mise à la largeur voulue."""
    k = largeur / w
    return (f'<div class="rec" style="width:{largeur}px;height:{round(h*k)}px;{extra}">'
            f'<img src="{src}" style="width:{round(source*k)}px;margin-left:{-round(x*k)}px;margin-top:{-round(y*k)}px"></div>')

def fenetre(contenu, titre="md Viewer", extra=""):
    return (f'<div class="fen" style="{extra}"><div class="barre-fen"><i></i><i></i><i></i><b>{titre}</b></div>{contenu}</div>')

def page(corps, titre, sous):
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>
<div class="marque">md<span class="barre"></span>Viewer</div>
<div class="titre">{titre}</div><div class="sous">{sous}</div>
<div class="scene">{corps}</div></body></html>"""

brut = html.escape("".join(open(os.path.join(STORE, "scenes/en/1-lecteur.md"), encoding="utf-8").readlines()[:22]))

IMAGES = {
"1-see-what-your-ai-wrote": page(f"""
  <div class="brut" style="left:0; top:24px; width:430px; height:520px; font-size:13.5px">{brut}</div>
  <span class="etiquette avant" style="left:16px; top:0">Before · raw .md</span>
  {fenetre(recadre(MAC + "1-lecteur.png", 480, 140, 1600, 1200, 700), extra="left:474px; top:40px")}
  <span class="etiquette apres" style="left:494px; top:16px">After · md Viewer</span>
""", "See what your AI <em>really</em> wrote", "Claude or ChatGPT answer in Markdown. md Viewer shows it as a real document."),

"2-read-in-your-language": page(f"""
  {recadre(SRC + "traduction-1-2-mastodon.png", 40, 100, 2320, 900, 1174, source=2400)}
""", "Read any report <em>in your language</em>", "New in 1.2: a report in German, Italian or Spanish translates before your eyes — on your device."),

"3-diagrams-and-maps": page(f"""
  <div class="cap" style="left:0; top:10px; width:660px"><img src="{MAC}2-mermaid.png"></div>
  <div class="cap" style="left:514px; top:64px; width:660px"><img src="{MAC}3-carte.png"></div>
""", "Diagrams and maps, <em>rendered on their own</em>", "Mermaid flowcharts, timelines, Gantt, mind maps — and interactive maps. Offline."),

"4-the-gist-in-one-tap": page(f"""
  <div class="fen" style="left:70px; top:4px; border-radius:22px">{recadre(MAC + "5-resume.png", 803, 275, 956, 1045, 500)}</div>
  <div class="fen" style="left:604px; top:30px; border-radius:22px">{recadre(MAC + "6-discussion.png", 803, 275, 956, 1045, 500)}</div>
""", "The gist <em>in one tap</em>", "A clear summary, and answers drawn from the document alone — on your device."),

"5-report-to-slideshow": page(f"""
  <div class="cap" style="left:150px; top:6px; width:874px"><img src="{MAC}4-presentation.png"></div>
""", "From report <em>to slideshow</em>", "One tap to present. Or ask your AI to turn a 30-page document into slides — the prompt is on our site."),

"6-export": page(f"""
  {fenetre(recadre(MAC + "1-lecteur.png", 480, 140, 1600, 1200, 680), extra="left:0; top:6px")}
  <div style="position:absolute; left:740px; top:40px; width:420px; display:flex; flex-direction:column; gap:18px">
    <div class="format"><b>PDF</b><span>Paginated, A4 or Letter</span></div>
    <div class="format"><b>Word</b><span>An editable .docx</span></div>
    <div class="format"><b>PowerPoint</b><span>Your slideshow as a .pptx</span></div>
  </div>
""", "Export to <em>PDF, Word and PowerPoint</em>", "Share a finished document with anyone — even without md Viewer."),

"7-offline-private-free": f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>
<div class="marque">md<span class="barre"></span>Viewer</div>
<div class="gros" style="left:48px; top:150px"><span>Offline.</span><span>Private.</span><span>Free.</span></div>
<div class="petit" style="left:50px; top:430px; width:430px">No account, no tracking, nothing uploaded.<br>
iPhone · iPad · Mac — in five languages.</div>
<div class="cap" style="left:520px; top:96px; width:500px; border-radius:18px"><img src="{IPAD}3-carte.png"></div>
<div class="cap" style="left:930px; top:210px; width:250px; border-radius:26px"><img src="{IPHONE}1-lecteur.png"></div>
</body></html>""",
}

for nom, contenu in IMAGES.items():
    os.makedirs(HTML, exist_ok=True)
    src = os.path.join(HTML, f"{nom}.html")
    open(src, "w", encoding="utf-8").write(contenu)
    sortie = os.path.join(ICI, f"{nom}.png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=1270,760",
                    "--virtual-time-budget=4000", f"--screenshot={sortie}", f"file://{src}"],
                   check=True, capture_output=True)
    print("écrit", sortie)
