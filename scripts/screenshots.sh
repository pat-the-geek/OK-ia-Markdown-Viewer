#!/usr/bin/env bash
# Captures App Store, en headless — iPhone et iPad, une langue par passage.
#
# Le hook `#if DEBUG` de l'app lit OKIA_RENDER_CONTENT / OKIA_RENDER_NAME et rend ce
# Markdown directement dans le lecteur : aucune interaction, donc aucun clic à scripter.
# La langue passe par la clé UserDefaults « okia.language », que l'app relit au lancement.
#
# Usage :
#   scripts/screenshots.sh fr            les scènes en français, iPhone 6,9" et iPad 13"
#   scripts/screenshots.sh en            idem en anglais
#   scripts/screenshots.sh fr iphone     une seule famille d'appareils
#
# Les scènes sont les fichiers de store/scenes/<langue>/<n>-<nom>.md ; la capture prend le
# même nom. Sortie dans store/screenshots/<appareil>/<langue>/.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE="ch.ok-ia.markdownviewer"
IPHONE="iPhone 17 Pro Max"     # 1320 × 2868, le slot 6,9" demandé par App Store Connect
IPAD="iPad Pro 13-inch (M5)"   # 2064 × 2752, le slot 13"
ATTENTE=9                      # secondes : les tuiles vectorielles et Mermaid doivent être là

LANGUE="${1:-fr}"
CIBLE="${2:-tout}"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

[ -d "store/scenes/$LANGUE" ] || die "aucune scène pour « $LANGUE » (store/scenes/$LANGUE)"

udid() { xcrun simctl list devices available | grep -F "$1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'; }

capture_appareil() {
  local nom="$1" dossier="$2" dev
  dev="$(udid "$nom")"
  [ -n "$dev" ] || die "simulateur introuvable : $nom"
  step "$nom — $LANGUE"

  xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1 || xcrun simctl boot "$dev" >/dev/null 2>&1 || true
  xcrun simctl install "$dev" "$APP" >/dev/null
  xcrun simctl spawn "$dev" defaults write "$BUNDLE" okia.language -string "$LANGUE"

  # Barre d'état figée : l'usage App Store veut une heure neutre, du wifi plein et une
  # batterie pleine. Sans quoi chaque capture porte l'heure de sa génération — et, si
  # l'app a été lancée depuis une autre, un fil d'Ariane « ◀ … » qui n'a rien à y faire.
  xcrun simctl status_bar "$dev" override \
    --time "09:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode notSupported --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true

  mkdir -p "store/screenshots/$dossier/$LANGUE"
  for scene in store/scenes/"$LANGUE"/*.md; do
    local base titre
    base="$(basename "$scene" .md)"
    titre="$(head -1 "$scene" | sed 's/^# *//')"
    xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1 || true
    SIMCTL_CHILD_OKIA_RENDER_CONTENT="$(cat "$scene")" \
    SIMCTL_CHILD_OKIA_RENDER_NAME="$titre.md" \
      xcrun simctl launch "$dev" "$BUNDLE" >/dev/null
    sleep "$ATTENTE"
    xcrun simctl io "$dev" screenshot "store/screenshots/$dossier/$LANGUE/$base.png" >/dev/null 2>&1
    ok "$base.png"
  done
  xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1 || true
}

step "Construction (Debug — le hook de capture n'existe pas en Release)"
xcodebuild -project "OK-ia - md Viewer.xcodeproj" -scheme "md Viewer" \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO >/tmp/okia-shots-build.log 2>&1 \
  || { grep -E 'error:' /tmp/okia-shots-build.log | head -10; die "build échoué"; }
APP="$(xcodebuild -project "OK-ia - md Viewer.xcodeproj" -scheme "md Viewer" \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ TARGET_BUILD_DIR/{print $2}' | head -1)/md Viewer.app"
[ -d "$APP" ] || die "app introuvable après le build : $APP"
ok "$(basename "$APP")"

case "$CIBLE" in
  iphone) capture_appareil "$IPHONE" "iphone-6.9" ;;
  ipad)   capture_appareil "$IPAD"   "ipad-13" ;;
  *)      capture_appareil "$IPHONE" "iphone-6.9"; capture_appareil "$IPAD" "ipad-13" ;;
esac

printf '\n\033[32m✓ captures %s dans store/screenshots/*/%s/\033[0m\n' "$LANGUE" "$LANGUE"
