#!/usr/bin/env bash
# Prépare le cache d'entités de la démonstration des captures (1.4), une langue à la fois.
#
# L'analyse du coffre n'interroge pas Wikidata : elle reprend les fiches que la lecture de chaque
# document a trouvées. Chez un utilisateur, ce cache se remplit au fil des lectures ; ici, on ouvre
# les entités de chaque rapport du coffre de démonstration au simulateur, Wikidata accepté, puis on
# garde le cache obtenu dans store/demo/<langue>/Analytic/. Les captures partent de ce cache : les
# photos et descriptions sont celles de Wikidata, déjà là.
#
# Usage : scripts/demo-cache.sh fr      (simulateur iPhone 17 Pro Max ; build Debug déjà fait par
#                                        scripts/screenshots.sh)
#         GARDER=1 scripts/demo-cache.sh fr   complète le cache existant
set -euo pipefail
cd "$(dirname "$0")/.."

LANGUE="${1:-fr}"
BUNDLE="ch.ok-ia.markdownviewer"
IPHONE="iPhone 17 Pro Max"
ATTENTE=45
[ -d "store/demo/$LANGUE" ] || { echo "aucune démonstration pour « $LANGUE »" >&2; exit 1; }

dev="$(xcrun simctl list devices available | grep -F "$IPHONE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1 || true
APP="$(xcodebuild -project "OK-ia - md Viewer.xcodeproj" -scheme "md Viewer" \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ TARGET_BUILD_DIR/{print $2}' | head -1)/md Viewer.app"
[ -d "$APP" ] || { echo "app Debug introuvable : lancer d'abord scripts/screenshots.sh" >&2; exit 1; }
xcrun simctl install "$dev" "$APP" >/dev/null

demo="$(xcrun simctl get_app_container "$dev" "$BUNDLE" data)/tmp/okia-demo"
rm -rf "$demo"; cp -R "store/demo/$LANGUE" "$demo"
# Repartir de zéro, sauf GARDER=1 : une passe de complément garde les fiches déjà obtenues et va
# chercher celles qui manquent (Wikidata refuse parfois une rafale de requêtes).
if [ -z "${GARDER:-}" ]; then rm -rf "$demo/Analytic"; fi

# Les rapports du coffre, puis le document des scènes 03 et 04.
while IFS= read -r f; do
  printf '  … %s\n' "${f#"$demo"/}"
  xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1 || true
  env SIMCTL_CHILD_OKIA_UI_LANG="$LANGUE" SIMCTL_CHILD_OKIA_CAPTURE=1 SIMCTL_CHILD_OKIA_DEMO="$demo" \
    SIMCTL_CHILD_OKIA_ACHAT=achete SIMCTL_CHILD_OKIA_WIKIDATA=oui SIMCTL_CHILD_OKIA_ANALYTIC=liste \
    SIMCTL_CHILD_OKIA_RENDER_FILE="$f" \
    xcrun simctl launch "$dev" "$BUNDLE" >/dev/null
  sleep "$ATTENTE"
done < <(find "$demo" -path '*/rapports-*' -name '*.md' | sort; \
         cp "store/scenes/$LANGUE/03-entites.md" "$demo/scene.md"; echo "$demo/scene.md")
xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1 || true

mkdir -p "store/demo/$LANGUE/Analytic"
cp "$demo/Analytic/entites-v2.json" "store/demo/$LANGUE/Analytic/entites-v2.json"
python3 - "store/demo/$LANGUE/Analytic/entites-v2.json" <<'PYTHON'
import json, sys
d = json.load(open(sys.argv[1]))
avec = [k for k, v in d.items() if v.get("qid")]
photos = [k for k, v in d.items() if v.get("image")]
sans = sorted(k for k, v in d.items() if not v.get("qid"))
print(f"  ✓ {len(d)} fiches, {len(avec)} résolues, {len(photos)} avec photo")
if sans: print("  ✗ non résolues :", ", ".join(sans))
PYTHON
