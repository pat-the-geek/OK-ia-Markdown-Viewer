# Petit client de l'API App Store Connect : jeton par jeton.swift, requêtes JSON.
# Usage : set -a; . scripts/deploy.env; set +a; puis python3 scripts/asc/<script>.py …
import json, os, subprocess, time, urllib.request, urllib.error
ICI = os.path.dirname(os.path.abspath(__file__))
_jeton = [None, 0]
def jeton():
    if not _jeton[0] or time.time() - _jeton[1] > 900:
        _jeton[0] = subprocess.check_output(["swift", os.path.join(ICI, "jeton.swift")]).decode().strip()
        _jeton[1] = time.time()
    return _jeton[0]
def req(methode, chemin, corps=None):
    url = chemin if chemin.startswith("http") else "https://api.appstoreconnect.apple.com" + chemin
    donnees = json.dumps(corps).encode() if corps is not None else None
    r = urllib.request.Request(url, data=donnees, method=methode,
        headers={"Authorization": "Bearer " + jeton(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r) as rep:
            texte = rep.read().decode()
            return json.loads(texte) if texte else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{methode} {chemin} → {e.code} {e.read().decode()[:800]}")
APP = "6781039895"
