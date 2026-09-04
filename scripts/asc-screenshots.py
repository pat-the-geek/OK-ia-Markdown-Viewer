#!/usr/bin/env python3
"""Téléverse le jeu de captures dans les fiches App Store Connect.

`asc.py` parle JSON ; les captures, elles, sont des octets — trois appels par image, dont
un PUT hors API. D'où ce script, qui fait la boucle complète : réserver l'image, envoyer
les octets, confirmer avec la somme de contrôle, puis vérifier ce qu'Apple en a fait.

Il travaille sur les versions **en préparation** (PREPARE_FOR_SUBMISSION) : une version déjà
publiée refuserait la modification.

Usage :
  scripts/asc-screenshots.py etat      ce que contiennent les fiches aujourd'hui
  scripts/asc-screenshots.py essai     ce qui serait fait, sans rien envoyer
  scripts/asc-screenshots.py envoi     remplace les jeux par ceux de store/screenshots/

« envoi » **remplace** : les captures déjà en place dans les emplacements visés sont
supprimées avant l'envoi, et les emplacements devenus sans objet (une taille d'iPhone qu'on
ne produit plus) sont supprimés aussi. Les fichiers d'origine restent dans le dépôt.
"""
import hashlib
import importlib.util
import pathlib
import sys

import requests

RACINE = pathlib.Path(__file__).resolve().parent.parent
APP = "6781039895"           # md Viewer : Markdown & Mermaid

# Dossier local → emplacement App Store Connect. Les tailles produites par
# scripts/screenshots.sh (1320×2868, 2064×2752, 2880×1800) sont celles qu'Apple accepte
# dans ces trois emplacements.
EMPLACEMENTS = {
    "iphone-6.9": "APP_IPHONE_67",
    "ipad-13": "APP_IPAD_PRO_3GEN_129",
    "mac": "APP_DESKTOP",
}
APPAREILS = {"IOS": ["iphone-6.9", "ipad-13"], "MAC_OS": ["mac"]}
LANGUES = {"fr": "fr-FR", "en": "en-US"}


def _asc():
    """asc.py comme bibliothèque : mêmes identifiants, même jeton, un seul endroit."""
    spec = importlib.util.spec_from_file_location("asc", RACINE / "scripts" / "asc.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


asc = _asc()


def appel(methode, chemin, corps=None):
    code, data = asc.call(methode, chemin, corps)
    if code >= 400:
        sys.exit(f"HTTP {code} sur {methode} {chemin}\n{data}")
    return data


def versions_en_preparation():
    """{plateforme: id de version} — seules celles qu'on a le droit de modifier."""
    data = appel("GET", f"/v1/apps/{APP}/appStoreVersions?limit=20")
    trouvees = {}
    for v in data["data"]:
        a = v["attributes"]
        if a["appStoreState"] == "PREPARE_FOR_SUBMISSION":
            trouvees[a["platform"]] = (v["id"], a["versionString"])
    return trouvees


def localisations(version_id):
    data = appel("GET", f"/v1/appStoreVersions/{version_id}"
                        f"/appStoreVersionLocalizations?limit=50")
    return {l["attributes"]["locale"]: l["id"] for l in data["data"]}


def jeux(localisation_id):
    """{type d'affichage: (id du jeu, [ids des captures])}."""
    data = appel("GET", f"/v1/appStoreVersionLocalizations/{localisation_id}"
                        f"/appScreenshotSets?include=appScreenshots&limit=50")
    inclus = {i["id"]: i for i in data.get("included", [])}
    resultat = {}
    for jeu in data.get("data", []):
        rel = jeu.get("relationships", {}).get("appScreenshots", {}).get("data") or []
        captures = [(r["id"], inclus.get(r["id"], {}).get("attributes", {}).get("fileName", "?"))
                    for r in rel]
        resultat[jeu["attributes"]["screenshotDisplayType"]] = (jeu["id"], captures)
    return resultat


def fichiers(dossier, langue):
    chemin = RACINE / "store" / "screenshots" / dossier / langue
    return sorted(chemin.glob("*.png")) if chemin.is_dir() else []


# --- envoi ------------------------------------------------------------------------------

def creer_jeu(localisation_id, type_affichage):
    data = appel("POST", "/v1/appScreenshotSets", {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": type_affichage},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": localisation_id}}},
        }
    })
    return data["data"]["id"]


def televerser(jeu_id, fichier):
    """Réserve, envoie les octets, confirme. Retourne l'id de la capture."""
    octets = fichier.read_bytes()
    data = appel("POST", "/v1/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileSize": len(octets), "fileName": fichier.name},
            "relationships": {"appScreenshotSet": {
                "data": {"type": "appScreenshotSets", "id": jeu_id}}},
        }
    })
    capture_id = data["data"]["id"]
    for op in data["data"]["attributes"]["uploadOperations"]:
        entetes = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        morceau = octets[op["offset"]:op["offset"] + op["length"]]
        reponse = requests.request(op["method"], op["url"], headers=entetes,
                                   data=morceau, timeout=300)
        if reponse.status_code >= 400:
            sys.exit(f"envoi refusé ({reponse.status_code}) pour {fichier.name}")
    appel("PATCH", f"/v1/appScreenshots/{capture_id}", {
        "data": {
            "type": "appScreenshots",
            "id": capture_id,
            "attributes": {"uploaded": True,
                           "sourceFileChecksum": hashlib.md5(octets).hexdigest()},
        }
    })
    return capture_id


def etat_capture(capture_id):
    data = appel("GET", f"/v1/appScreenshots/{capture_id}")
    livraison = data["data"]["attributes"].get("assetDeliveryState") or {}
    return livraison.get("state", "?"), livraison.get("errors") or []


# --- commandes --------------------------------------------------------------------------

def commande_etat():
    for plateforme, (version_id, numero) in versions_en_preparation().items():
        print(f"\n{plateforme} {numero}")
        for locale, loc_id in localisations(version_id).items():
            presents = jeux(loc_id)
            if not presents:
                print(f"  {locale} : aucun jeu")
            for type_affichage, (_, captures) in presents.items():
                noms = ", ".join(n for _, n in captures) or "vide"
                print(f"  {locale} : {type_affichage:24} {len(captures)} → {noms}")


def commande_envoi(essai):
    for plateforme, (version_id, numero) in versions_en_preparation().items():
        print(f"\n\033[1m{plateforme} {numero}\033[0m")
        locs = localisations(version_id)
        for langue, locale in LANGUES.items():
            loc_id = locs.get(locale)
            if not loc_id:
                print(f"  {locale} : absente de la fiche, ignorée")
                continue
            presents = jeux(loc_id)
            attendus = {EMPLACEMENTS[d] for d in APPAREILS[plateforme]}

            # Un emplacement qu'on ne produit plus garderait des captures périmées.
            for type_affichage, (jeu_id, captures) in presents.items():
                if type_affichage in attendus:
                    continue
                print(f"  {locale} : {type_affichage} — jeu supprimé ({len(captures)} capture(s))")
                if not essai:
                    appel("DELETE", f"/v1/appScreenshotSets/{jeu_id}")

            for dossier in APPAREILS[plateforme]:
                type_affichage = EMPLACEMENTS[dossier]
                sources = fichiers(dossier, langue)
                if not sources:
                    print(f"  {locale} : {type_affichage} — aucun fichier local, ignoré")
                    continue
                jeu_id, anciennes = presents.get(type_affichage, (None, []))
                if anciennes:
                    print(f"  {locale} : {type_affichage} — {len(anciennes)} ancienne(s) supprimée(s)")
                    if not essai:
                        for capture_id, _ in anciennes:
                            appel("DELETE", f"/v1/appScreenshots/{capture_id}")
                if jeu_id is None:
                    print(f"  {locale} : {type_affichage} — jeu créé")
                    if not essai:
                        jeu_id = creer_jeu(loc_id, type_affichage)
                for fichier in sources:
                    if essai:
                        print(f"  {locale} : {type_affichage} ← {fichier.name}")
                        continue
                    capture_id = televerser(jeu_id, fichier)
                    etat, erreurs = etat_capture(capture_id)
                    marque = "\033[32m✓\033[0m" if not erreurs else "\033[31m✗\033[0m"
                    print(f"  {marque} {locale} {type_affichage} ← {fichier.name} [{etat}]")
                    for e in erreurs:
                        print(f"      {e}")


if __name__ == "__main__":
    commande = sys.argv[1] if len(sys.argv) > 1 else ""
    if commande == "etat":
        commande_etat()
    elif commande in ("essai", "envoi"):
        commande_envoi(essai=commande == "essai")
    else:
        sys.exit(__doc__)
