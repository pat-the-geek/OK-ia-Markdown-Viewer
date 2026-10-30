#!/usr/bin/env python3
"""Pose des captures habillées dans les emplacements des fiches en préparation.

Usage (après `set -a; . scripts/deploy.env; set +a`) :
  python3 scripts/asc/captures.py [emplacement …] [--essai] [--jeu 1.3]

Source : store/captures-legendees-<jeu>/<emplacement>/<langue>/*.png (scripts/legender.py),
jeu 1.4 par défaut. Sans emplacement nommé : tous ceux du jeu. APP_DESKTOP va à la fiche
macOS, les autres à la fiche iOS. Seuls les emplacements visés sont touchés : leurs anciennes
captures sont remplacées, les autres restent tels quels. Une langue absente de la fiche est
ignorée (la fiche doit d'abord exister dans cette langue).
"""
import hashlib
import pathlib
import sys
import time

import requests

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc import req, APP  # noqa: E402

RACINE = pathlib.Path(__file__).resolve().parents[2]
# Les quinze langues de la 1.4 (29/10/2026) et leurs codes dans App Store Connect.
LANGUES = {"fr": "fr-FR", "en": "en-US", "de": "de-DE", "es": "es-ES", "it": "it",
           "nl": "nl-NL", "pt-BR": "pt-BR", "tr": "tr", "vi": "vi", "ru": "ru", "uk": "uk",
           "ja": "ja", "zh-Hans": "zh-Hans", "ko": "ko", "hi": "hi"}


def plateforme(emplacement):
    return "MAC_OS" if emplacement == "APP_DESKTOP" else "IOS"


def version(plateforme_visee):
    for v in req("GET", f"/v1/apps/{APP}/appStoreVersions?limit=20")["data"]:
        a = v["attributes"]
        if a["platform"] == plateforme_visee and a["appStoreState"] == "PREPARE_FOR_SUBMISSION":
            return v["id"], a["versionString"]
    return None


def televerser(jeu_id, fichier):
    octets = fichier.read_bytes()
    d = req("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileSize": len(octets), "fileName": fichier.name},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": jeu_id}}}}})["data"]
    for op in d["attributes"]["uploadOperations"]:
        entetes = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        r = requests.request(op["method"], op["url"], headers=entetes,
                             data=octets[op["offset"]:op["offset"] + op["length"]], timeout=300)
        if r.status_code >= 400:
            sys.exit(f"envoi refusé ({r.status_code}) : {fichier}")
    req("PATCH", f"/v1/appScreenshots/{d['id']}", {"data": {
        "type": "appScreenshots", "id": d["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(octets).hexdigest()}}})
    return d["id"]


def main():
    args = sys.argv[1:]
    essai = "--essai" in args
    jeu = args[args.index("--jeu") + 1] if "--jeu" in args else "1.4"
    source = RACINE / "store" / f"captures-legendees-{jeu}"
    if not source.is_dir():
        sys.exit(f"{source} n'existe pas")
    nommes = [a for a in args if not a.startswith("--") and a != jeu]
    emplacements = nommes or sorted(d.name for d in source.iterdir() if d.is_dir())
    envoyees = []
    for pf in ("IOS", "MAC_OS"):
        visees = [e for e in emplacements if plateforme(e) == pf]
        if not visees:
            continue
        v = version(pf)
        if not v:
            print(f"{pf} : aucune version en préparation — {', '.join(visees)} ignoré(s)")
            continue
        envoyees += envoyer(pf, v, visees, source, essai)
    if essai or not envoyees:
        return
    attendre(envoyees)


def envoyer(pf, v, emplacements, source, essai):
    version_id, numero = v
    print(f"{pf} {numero}")
    locs = {l["attributes"]["locale"]: l["id"] for l in
            req("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")["data"]}
    envoyees = []
    for langue, locale in LANGUES.items():
        loc_id = locs.get(locale)
        if not loc_id:
            print(f"  {locale} : absente, ignorée")
            continue
        jeux = {j["attributes"]["screenshotDisplayType"]: j["id"] for j in
                req("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?limit=50")["data"]}
        for emplacement in emplacements:
            fichiers = sorted((source / emplacement / langue).glob("*.png"))
            if not fichiers:
                print(f"  {locale} : {emplacement} — aucun fichier, ignoré")
                continue
            print(f"  {locale} : {emplacement} ← {len(fichiers)} capture(s)")
            if essai:
                continue
            jeu_id = jeux.get(emplacement)
            if jeu_id:
                for c in req("GET", f"/v1/appScreenshotSets/{jeu_id}/appScreenshots?limit=50")["data"]:
                    req("DELETE", f"/v1/appScreenshots/{c['id']}")
            else:
                jeu_id = req("POST", "/v1/appScreenshotSets", {"data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": emplacement},
                    "relationships": {"appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})["data"]["id"]
            for f in fichiers:
                envoyees.append((f"{locale}/{emplacement}/{f.name}", televerser(jeu_id, f)))
    return envoyees


def attendre(envoyees):
    # Apple traite les images après coup : on attend qu'elles soient toutes acceptées.
    etats = {}
    for _ in range(30):
        etats = {}
        for nom, cid in envoyees:
            e = (req("GET", f"/v1/appScreenshots/{cid}")["data"]["attributes"].get("assetDeliveryState") or {})
            etats[nom] = (e.get("state"), e.get("errors"))
        en_cours = [n for n, (s, _) in etats.items() if s not in ("COMPLETE", "FAILED")]
        if not en_cours:
            break
        time.sleep(5)
    ratees = {n: err for n, (s, err) in etats.items() if s != "COMPLETE"}
    print(f"{len(envoyees) - len(ratees)}/{len(envoyees)} acceptées")
    for n, err in ratees.items():
        print(f"  ✗ {n} : {err}")


if __name__ == "__main__":
    main()
