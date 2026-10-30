#!/usr/bin/env python3
"""Habille les captures App Store : une légende en Nunito Black, un trait orange, la capture
au-dessous, coins arrondis et ombre douce, sur le fond crème de la charte.

Entrée : store/screenshots/<appareil>/<langue>/<scène>.png (scripts/screenshots.sh).
Sortie : store/captures-legendees-1.4/<emplacement App Store Connect>/<langue>/<scène>.png,
à la taille exacte de l'emplacement. Légendes : store/legendes.json.

Usage : scripts/legender.py [langue …]      toutes les langues si aucune n'est donnée
        OKIA_APPAREILS=iphone-duo scripts/legender.py   un seul appareil (liste séparée par des virgules)

La police vient de l'app (Web/fonts/Nunito-Black.woff2), convertie en TTF à la volée —
fontTools et brotli sont nécessaires (python3 -m pip install --user fonttools brotli pillow).
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RACINE = pathlib.Path(__file__).resolve().parent.parent
SORTIE = RACINE / "store" / "captures-legendees-1.4"
FOND = (250, 247, 241)
ENCRE = (28, 25, 23)
ORANGE = (232, 151, 46)

# Mesuré sur le jeu légendé précédent, pour que les nouvelles captures s'y fondent.
# marge, corps, interligne, trait (largeur, épaisseur, écart), haut et bas de la capture,
# rayon des coins de la capture (en pixels de la sortie).
APPAREILS = {
    "iphone-6.9": dict(emplacement="APP_IPHONE_67", marge=96, corps=98, interligne=110,
                       trait=(118, 10, 40), haut=540, bas=110, rayon=34),
    # L'emplacement « écran moyen » (6,1 et 6,3"), que la fiche met désormais en avant.
    "iphone-6.3": dict(emplacement="APP_IPHONE_61", marge=88, corps=90, interligne=100,
                       trait=(108, 9, 36), haut=494, bas=100, rayon=31),
    # L'iPhone Duo plié : son écran extérieur est moins haut que celui d'un iPhone, la légende
    # prend un peu moins de place.
    "iphone-duo": dict(emplacement="APP_IPHONE_DUO", marge=96, corps=92, interligne=104,
                       trait=(118, 10, 34), haut=470, bas=90, rayon=34,
                       prefixe="b-", scenes={"02-lecteur"}),
    # Le Duo déplié, écran intérieur 2007 × 2853 : le même emplacement, en tête. Dix captures au
    # plus par emplacement : les neuf scènes dépliées (le résumé reste au Mac), puis le lecteur plié.
    "iphone-duo-deplie": dict(emplacement="APP_IPHONE_DUO", marge=138, corps=132, interligne=150,
                              trait=(170, 13, 50), haut=660, bas=130, rayon=40, prefixe="a-"),
    # Le Duo déplié couché (2853 × 2007, jeu de la 1.4) : comme l'iPad en paysage, la légende
    # tient sur une ligne et la capture prend la place.
    "iphone-duo-deplie-paysage": dict(emplacement="APP_IPHONE_DUO", marge=150, corps=124, interligne=136,
                                      trait=(210, 9, 22), haut=350, bas=80, rayon=40, prefixe="a-"),
    "ipad-13": dict(emplacement="APP_IPAD_PRO_3GEN_129", marge=146, corps=152, interligne=172,
                    trait=(184, 9, 48), haut=630, bas=110, rayon=26),
    # L'iPad couché (conversion, discussion à côté du document) : la légende tient sur une ligne,
    # comme sur le Mac, et la capture prend la place.
    "ipad-13-paysage": dict(emplacement="APP_IPAD_PRO_3GEN_129", marge=140, corps=120, interligne=130,
                            trait=(200, 8, 20), haut=330, bas=70, rayon=26),
    "mac": dict(emplacement="APP_DESKTOP", marge=140, corps=101, interligne=110,
                trait=(230, 7, 18), haut=272, bas=55, rayon=0),
}


def police():
    from fontTools.ttLib import TTFont
    f = TTFont(RACINE / "OKiaMarkdownViewer" / "Web" / "fonts" / "Nunito-Black.woff2")
    f.flavor = None
    chemin = pathlib.Path(tempfile.gettempdir()) / "okia-Nunito-Black.ttf"
    f.save(chemin)
    global COUVERTS
    COUVERTS = set(f.getBestCmap())
    return str(chemin)


# Les caractères de la Nunito de l'app (un sous-ensemble latin). Une légende qui en sort — cyrillique,
# vietnamien, turc, japonais, chinois, coréen, hindi — passe par CoreText (scripts/legende-texte.swift) :
# la police arrondie du système, et la police de repli de l'écriture, composée comme il faut.
COUVERTS = set()
DESSINATEUR = RACINE / "build" / "legende-texte"


def hors_nunito(texte):
    return any(ord(c) not in COUVERTS for c in texte if not c.isspace())


def dessinateur():
    source = RACINE / "scripts" / "legende-texte.swift"
    if not DESSINATEUR.exists() or DESSINATEUR.stat().st_mtime < source.stat().st_mtime:
        DESSINATEUR.parent.mkdir(exist_ok=True)
        subprocess.run(["swiftc", "-O", str(source), "-o", str(DESSINATEUR)], check=True)
    return DESSINATEUR


def texte_coretext(legende, corps, largeur, interligne):
    """La légende en image transparente, et son nombre de lignes."""
    sortie = pathlib.Path(tempfile.gettempdir()) / "okia-legende.png"
    r = subprocess.run([str(dessinateur()), legende, str(corps), str(largeur), str(interligne), str(sortie)],
                       check=True, capture_output=True, text=True)
    nombre = int(r.stdout.split()[0])
    return Image.open(sortie).convert("RGBA").copy(), nombre


def lignes(texte, fonte, largeur, dessin):
    mots, courant, sortie = texte.split(), "", []
    for m in mots:
        essai = (courant + " " + m).strip()
        if dessin.textlength(essai, font=fonte) <= largeur or not courant:
            courant = essai
        else:
            sortie.append(courant)
            courant = m
    sortie.append(courant)
    return sortie


def habiller(capture, legende, p, ttf):
    brut = Image.open(capture).convert("RGB")
    paysage = brut.width > brut.height
    # La toile a la taille de l'emplacement : celle de la capture brute, dans son orientation.
    W, H = brut.size
    toile = Image.new("RGB", (W, H), FOND)
    d = ImageDraw.Draw(toile)
    corps = p["corps"]
    largeur = W - 2 * p["marge"]
    if hors_nunito(legende):
        interligne = p["interligne"]
        image_texte, nombre = texte_coretext(legende, corps, largeur, interligne)
        while nombre > 2 and corps > 60:
            corps -= 6
            interligne = round(p["interligne"] * corps / p["corps"])
            image_texte, nombre = texte_coretext(legende, corps, largeur, interligne)
        y = p["haut"] - 60 - nombre * interligne - p["trait"][2] - p["trait"][1]
        y = max(y, round(p["marge"] * 0.9))
        toile.paste(image_texte, (p["marge"], y), image_texte)
        # Le bas réel de l'encre, jambages compris.
        boite = image_texte.getchannel("A").getbbox()
        bas_texte = y + (boite[3] if boite else image_texte.height)
    else:
        fonte = ImageFont.truetype(ttf, corps)
        texte = lignes(legende, fonte, largeur, d)
        # Une légende trop longue pour deux lignes réduit son corps plutôt que de manger la capture.
        while len(texte) > 2 and corps > 60:
            corps -= 6
            fonte = ImageFont.truetype(ttf, corps)
            texte = lignes(legende, fonte, largeur, d)
        interligne = round(p["interligne"] * corps / p["corps"])
        y = p["haut"] - 60 - len(texte) * interligne - p["trait"][2] - p["trait"][1]
        y = max(y, round(p["marge"] * 0.9))
        bas_texte = y
        for l in texte:
            d.text((p["marge"], y), l, font=fonte, fill=ENCRE)
            # Le bas réel de la ligne, jambages compris : le trait se pose dessous, sans le toucher.
            bas_texte = d.textbbox((p["marge"], y), l, font=fonte)[3]
            y += interligne
    l_trait, e_trait, ecart = p["trait"]
    y_trait = bas_texte + ecart
    d.rectangle([p["marge"], y_trait, p["marge"] + l_trait, y_trait + e_trait], fill=ORANGE)

    haut = max(p["haut"], y_trait + e_trait + 50)
    dispo_h = H - haut - p["bas"]
    dispo_l = W - 2 * p["marge"]
    echelle = min(dispo_h / brut.height, dispo_l / brut.width)
    l, h = round(brut.width * echelle), round(brut.height * echelle)
    image = brut.resize((l, h), Image.LANCZOS)
    x = (W - l) // 2

    # Ombre douce, puis la capture aux coins arrondis.
    masque = Image.new("L", (l, h), 0)
    ImageDraw.Draw(masque).rounded_rectangle([0, 0, l - 1, h - 1], radius=p["rayon"], fill=255)
    flou = round(W * 0.018)
    ombre = Image.new("L", (W, H), 0)
    ombre.paste(Image.new("L", (l, h), 70), (x, haut + round(flou * 0.4)), masque)
    ombre = ombre.filter(ImageFilter.GaussianBlur(flou))
    toile = Image.composite(Image.new("RGB", (W, H), (60, 50, 40)), toile, ombre)
    toile.paste(image, (x, haut), masque)
    return toile


def main():
    legendes = json.loads((RACINE / "store" / "legendes.json").read_text(encoding="utf-8"))
    langues = sys.argv[1:] or list(legendes)
    ttf = police()
    choisis = [a for a in os.environ.get("OKIA_APPAREILS", "").split(",") if a]
    videes = set()
    for appareil, p in APPAREILS.items():
        if appareil.endswith("-paysage") or (choisis and appareil not in choisis):
            continue
        for langue in langues:
            dossier = RACINE / "store" / "screenshots" / appareil / langue
            if not dossier.is_dir():
                continue
            cible = SORTIE / p["emplacement"] / langue
            cible.mkdir(parents=True, exist_ok=True)
            # Le jeu d'une langue se remplace en entier : une scène renommée ne doit pas laisser
            # son ancienne image dans l'emplacement. Une fois par emplacement : le Duo plié et
            # le Duo déplié s'y retrouvent ensemble.
            if cible not in videes:
                for vieux in cible.glob("*.png"):
                    vieux.unlink()
                videes.add(cible)
            for capture in sorted(dossier.glob("*.png")):
                if p.get("scenes") and capture.stem not in p["scenes"]:
                    continue
                legende = legendes[langue].get(capture.stem)
                if not legende:
                    print(f"  … {appareil}/{langue}/{capture.name} : pas de légende, ignorée")
                    continue
                q = p
                with Image.open(capture) as brute:
                    if brute.width > brute.height and appareil + "-paysage" in APPAREILS:
                        q = APPAREILS[appareil + "-paysage"]
                nom = p.get("prefixe", "") + capture.name
                habiller(capture, legende, q, ttf).save(cible / nom)
                print(f"  ✓ {p['emplacement']}/{langue}/{nom}")


if __name__ == "__main__":
    main()
