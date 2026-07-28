#!/usr/bin/env bash
# TestFlight deployment for md Viewer: bump → xcodegen → archive → export → checks → upload.
#
# Credentials come from scripts/deploy.env (never committed) or from the environment:
#   ASC_KEY_ID     App Store Connect API key id (the .p8 itself stays in
#                  ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8)
#   ASC_ISSUER_ID  App Store Connect issuer id
#
# Usage:
#   scripts/deploy-testflight.sh              archive + export + upload with the current build number
#   scripts/deploy-testflight.sh --bump       increment CURRENT_PROJECT_VERSION first
#   scripts/deploy-testflight.sh --no-upload  stop after the checks, keep the .ipa
#
# The upload goes out as STANDARD App Store distribution. This matters: builds sent from
# Xcode Organizer as "TestFlight Internal Only" come back App-Store-ineligible, which is
# what stranded builds 9-18 of this app.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="OK-ia - md Viewer.xcodeproj"
SCHEME="md Viewer"
TEAM_ID="PU9BSXN2V5"
BUILD_DIR="build/TestFlight"
LANGS="de en es fr it"

BUMP=0
UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --bump)      BUMP=1 ;;
    --no-upload) UPLOAD=0 ;;
    -h|--help)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           printf 'argument inconnu : %s\n' "$arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# --- credentials ---------------------------------------------------------------------
# shellcheck source=/dev/null
[ -f scripts/deploy.env ] && . scripts/deploy.env
: "${ASC_KEY_ID:?manquant — copiez scripts/deploy.env.example vers scripts/deploy.env}"
: "${ASC_ISSUER_ID:?manquant — copiez scripts/deploy.env.example vers scripts/deploy.env}"
KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$KEY_FILE" ] || die "clé API introuvable : $KEY_FILE"

# --- version -------------------------------------------------------------------------
read_setting() { awk -F'"' -v k="$1:" '$0 ~ k {print $2; exit}' project.yml; }

if [ "$BUMP" = 1 ]; then
  step "Numéro de build"
  current="$(read_setting CURRENT_PROJECT_VERSION)"
  [ -n "$current" ] || die "CURRENT_PROJECT_VERSION introuvable dans project.yml"
  next=$((current + 1))
  # Match the quoted form exactly so no other setting in project.yml is touched.
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"$current\"/CURRENT_PROJECT_VERSION: \"$next\"/" project.yml
  ok "build $current → $next"
fi

MARKETING="$(read_setting MARKETING_VERSION)"
BUILD="$(read_setting CURRENT_PROJECT_VERSION)"
printf '\n  version à livrer : \033[1m%s (%s)\033[0m\n' "$MARKETING" "$BUILD"

# --- build ---------------------------------------------------------------------------
step "Génération du projet Xcode"
xcodegen generate >/dev/null
ok "project.yml → $PROJECT"

step "Archive (Release, generic/platform=iOS)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$BUILD_DIR/$SCHEME.xcarchive" \
  -allowProvisioningUpdates archive >"$BUILD_DIR/archive.log" 2>&1 \
  || { grep -E 'error:' "$BUILD_DIR/archive.log" | head -20; die "archive échouée — log : $BUILD_DIR/archive.log"; }
ok "$BUILD_DIR/$SCHEME.xcarchive"

step "Export en distribution App Store"
cat > "$BUILD_DIR/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/$SCHEME.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" \
  -exportPath "$BUILD_DIR/export" \
  -allowProvisioningUpdates >"$BUILD_DIR/export.log" 2>&1 \
  || { tail -20 "$BUILD_DIR/export.log"; die "export échoué — log : $BUILD_DIR/export.log"; }

IPA="$BUILD_DIR/export/$SCHEME.ipa"
[ -f "$IPA" ] || die "IPA introuvable après l'export"
ok "$IPA ($(du -h "$IPA" | cut -f1))"

# --- preflight -----------------------------------------------------------------------
# These four checks each catch a failure that is silent at build time and expensive later:
# a Development-signed IPA rejected by App Store Connect, a Debug harness shipped to
# testers, a lost localisation, or an .ipa that isn't the version just built.
step "Contrôles avant envoi"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$IPA" -d "$TMP"
APP="$TMP/Payload/$SCHEME.app"
[ -d "$APP" ] || die "Payload/$SCHEME.app absent de l'IPA"

# Both checks write to a file before grepping. Piping a long-running producer into
# `grep -q` kills it with SIGPIPE as soon as grep matches, and under `set -o pipefail`
# that 141 becomes the pipeline's status — which would fail the signature check on a
# perfectly good IPA and, worse, make the debug-harness check pass without ever looking.
codesign -dvvv "$APP" >"$TMP/codesign.txt" 2>&1 || die "codesign a échoué sur $APP"
grep -q '^Authority=Apple Distribution' "$TMP/codesign.txt" \
  || die "l'IPA n'est pas signée « Apple Distribution » — App Store Connect la refusera"
ok "signature Apple Distribution"

# Scan every executable in the bundle, not just the main binary: Xcode 16 already moves
# Debug code into a companion md\ Viewer.debug.dylib, and a check that reads one file
# would miss it entirely.
find "$APP" -type f \( -perm -u+x -o -name '*.dylib' \) -print0 \
  | xargs -0 strings -a >"$TMP/strings.txt"

# Canary. OKIA_LANG is injected by the reader in every build, so it MUST be found here.
# If it isn't, `strings` is not seeing the binary's literals and the harness check below
# would pass without inspecting anything — a green light that means nothing.
grep -q 'OKIA_LANG' "$TMP/strings.txt" \
  || die "contrôle inopérant : aucune chaîne connue trouvée dans le binaire (le test du harnais serait vide)"

for marker in OKIA_FAKE_AI OKIA_RENDER_CONTENT OKIA_SHOT_SIZE; do
  # `if` rather than `grep ... && die`: a non-matching grep would leave the loop with a
  # non-zero status and `set -e` would abort the script on a clean binary.
  if grep -q "$marker" "$TMP/strings.txt"; then
    die "harnais de debug « $marker » présent dans le binaire de production"
  fi
done
ok "aucun harnais de debug dans le binaire"

for lang in $LANGS; do
  [ -d "$APP/$lang.lproj" ] || die "localisation manquante : $lang.lproj"
done
ok "langues embarquées : $LANGS"

ipa_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
ipa_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"
[ "$ipa_version" = "$MARKETING" ] && [ "$ipa_build" = "$BUILD" ] \
  || die "l'IPA annonce $ipa_version ($ipa_build), project.yml dit $MARKETING ($BUILD)"
ok "version conforme : $ipa_version ($ipa_build)"

# --- upload --------------------------------------------------------------------------
if [ "$UPLOAD" = 0 ]; then
  printf '\n\033[1mArrêt avant envoi (--no-upload).\033[0m IPA prête : %s\n' "$IPA"
  exit 0
fi

step "Envoi à App Store Connect"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "$BUILD_DIR/upload.log" | tail -8

grep -q 'UPLOAD SUCCEEDED' "$BUILD_DIR/upload.log" \
  || die "envoi échoué — log : $BUILD_DIR/upload.log"

printf '\n\033[32m✓ %s (%s) envoyé.\033[0m Apple traite le binaire 5 à 15 minutes\n' "$MARKETING" "$BUILD"
printf '  avant qu%s apparaisse dans TestFlight.\n' "'il"
