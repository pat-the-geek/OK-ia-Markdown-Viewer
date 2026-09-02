#!/usr/bin/env python3
"""Client App Store Connect minimal — pour les métadonnées, là où altool s'arrête.

`deploy-testflight.sh` envoie le binaire ; il ne sait rien dire de la fiche. Ce script
couvre l'autre moitié : créer une version, écrire les notes de version, rattacher un build.

Les identifiants viennent de scripts/deploy.env (non commité) ou de l'environnement, comme
pour le script de livraison :
  ASC_KEY_ID     identifiant de la clé API
  ASC_ISSUER_ID  identifiant de l'émetteur
La clé privée reste dans ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 ; elle
n'est lue que pour signer le jeton, et n'est jamais affichée.

Usage :
  scripts/asc.py GET  "/v1/apps/<id>/appStoreVersions?filter[platform]=IOS"
  scripts/asc.py POST /v1/appStoreVersions '{"data": {...}}'
  scripts/asc.py PATCH /v1/appStoreVersionLocalizations/<id> '{"data": {...}}'

La réponse est imprimée telle quelle, tronquée à 6 000 caractères : ce script est fait pour
être lu, pas pour être enchaîné dans un pipeline.
"""
import json
import os
import pathlib
import sys
import time

import jwt
import requests

BASE = "https://api.appstoreconnect.apple.com"
ENV_FILE = pathlib.Path(__file__).resolve().parent / "deploy.env"


def credentials() -> tuple[str, str]:
    """ASC_KEY_ID et ASC_ISSUER_ID, depuis l'environnement ou scripts/deploy.env."""
    values = {}
    if ENV_FILE.is_file():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip().removeprefix("export ")
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip().strip("\"'")
    key_id = os.environ.get("ASC_KEY_ID") or values.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID") or values.get("ASC_ISSUER_ID")
    if not key_id or not issuer:
        sys.exit("ASC_KEY_ID / ASC_ISSUER_ID manquants — copiez scripts/deploy.env.example "
                 "vers scripts/deploy.env")
    return key_id, issuer


def token(key_id: str, issuer: str) -> str:
    key_path = pathlib.Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{key_id}.p8"
    if not key_path.is_file():
        sys.exit(f"clé API introuvable : {key_path}")
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key_path.read_text(encoding="utf-8"),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def call(method: str, path: str, body=None):
    key_id, issuer = credentials()
    url = path if path.startswith("http") else BASE + path
    resp = requests.request(
        method,
        url,
        headers={"Authorization": f"Bearer {token(key_id, issuer)}",
                 "Content-Type": "application/json"},
        data=json.dumps(body) if body is not None else None,
        timeout=30,
    )
    payload = {}
    if resp.text.strip():
        try:
            payload = resp.json()
        except ValueError:
            payload = {"raw": resp.text[:500]}
    return resp.status_code, payload


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    method, path = sys.argv[1].upper(), sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    code, data = call(method, path, body)
    print(f"HTTP {code}")
    print(json.dumps(data, ensure_ascii=False, indent=1)[:6000])
