# Attend qu'un build soit traité (iOS et Mac), puis pose les notes « What to Test » fr-FR.
import sys, time, json
from asc import *
version, fichier = sys.argv[1], sys.argv[2]
texte = open(fichier, encoding="utf-8").read()
for plat in ["IOS", "MAC_OS"]:
    for essai in range(1, 60):
        d = req("GET", f"/v1/builds?filter[app]={APP}&filter[version]={version}&filter[preReleaseVersion.platform]={plat}&fields[builds]=processingState")
        if d["data"] and d["data"][0]["attributes"]["processingState"] == "VALID": break
        print(plat, "essai", essai, d["data"][0]["attributes"]["processingState"] if d["data"] else "absent", flush=True)
        time.sleep(60)
    bid = d["data"][0]["id"]
    locs = req("GET", f"/v1/builds/{bid}/betaBuildLocalizations")["data"]
    fr = [l for l in locs if l["attributes"]["locale"] == "fr-FR"]
    if fr:
        req("PATCH", f"/v1/betaBuildLocalizations/{fr[0]['id']}", {"data": {"type": "betaBuildLocalizations", "id": fr[0]["id"], "attributes": {"whatsNew": texte}}})
    else:
        req("POST", "/v1/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "fr-FR", "whatsNew": texte}, "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    print(plat, "notes posées", flush=True)
