#!/usr/bin/env bash
# TestFlight deployment for md Viewer: bump → xcodegen → archive → export → checks → upload.
#
# Credentials come from scripts/deploy.env (never committed) or from the environment:
#   ASC_KEY_ID     App Store Connect API key id (the .p8 itself stays in
#                  ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8)
#   ASC_ISSUER_ID  App Store Connect issuer id
#
# Usage:
#   scripts/deploy-testflight.sh              iOS, with the current build number
#   scripts/deploy-testflight.sh --bump       increment CURRENT_PROJECT_VERSION first
#   scripts/deploy-testflight.sh --mac        Mac Catalyst instead of iOS (.pkg)
#   scripts/deploy-testflight.sh --both       iOS then Mac, from a single build number
#   scripts/deploy-testflight.sh --no-upload  stop after the checks, keep the artefact
#
# --both exists because the two platforms are one product and forgetting the Mac is silent:
# the app shipped three weeks of iOS builds while the Mac stayed on an older one, watermarked
# map included. A single flag now covers both.
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
PLATFORMS="ios"
for arg in "$@"; do
  case "$arg" in
    --bump)      BUMP=1 ;;
    --no-upload) UPLOAD=0 ;;
    --mac)       PLATFORMS="mac" ;;
    --both)      PLATFORMS="ios mac" ;;
    -h|--help)   sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# Une plateforme, de l'archive à l'envoi. Tout ce qui diffère entre iOS et Mac tient dans
# les cinq variables ci-dessous ; les contrôles, eux, sont les mêmes des deux côtés — ils
# valent précisément parce qu'on ne les allège pas pour la plateforme qu'on livre moins
# souvent.
deliver() {
  local platform="$1" dest label out product altool_type
  local dir="$BUILD_DIR/$platform"

  case "$platform" in
    ios)
      dest='generic/platform=iOS'
      label='iOS'
      product="$dir/export/$SCHEME.ipa"
      altool_type='ios'
      ;;
    mac)
      # Catalyst exige l'équipe en clair : la signature automatique ne la devine pas ici.
      dest='generic/platform=macOS,variant=Mac Catalyst'
      label='Mac Catalyst'
      product="$dir/export/$SCHEME.pkg"
      altool_type='macos'
      ;;
    *) die "plateforme inconnue : $platform" ;;
  esac

  printf '\n\033[1m━━ %s ━━\033[0m\n' "$label"

  step "Archive (Release, $dest)"
  rm -rf "$dir"
  mkdir -p "$dir"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination "$dest" \
    -archivePath "$dir/$SCHEME.xcarchive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates archive >"$dir/archive.log" 2>&1 \
    || { grep -E 'error:' "$dir/archive.log" | head -20; die "archive échouée — log : $dir/archive.log"; }
  ok "$dir/$SCHEME.xcarchive"

  step "Export en distribution App Store"
  cat > "$dir/exportOptions.plist" <<PLIST
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
    -archivePath "$dir/$SCHEME.xcarchive" \
    -exportOptionsPlist "$dir/exportOptions.plist" \
    -exportPath "$dir/export" \
    -allowProvisioningUpdates >"$dir/export.log" 2>&1 \
    || { tail -20 "$dir/export.log"; die "export échoué — log : $dir/export.log"; }

  [ -f "$product" ] || die "artefact introuvable après l'export : $product"
  ok "$product ($(du -h "$product" | cut -f1))"

  # --- preflight ---------------------------------------------------------------------
  # Ces quatre contrôles rattrapent chacun une panne muette au build et coûteuse plus tard :
  # une signature de développement refusée par App Store Connect, un harnais de debug livré
  # aux testeurs, une localisation perdue, ou un artefact qui n'est pas la version qu'on
  # croit envoyer.
  step "Contrôles avant envoi"
  local tmp app plist resources
  tmp="$(mktemp -d)"

  case "$platform" in
    ios)
      unzip -q "$product" -d "$tmp"
      app="$tmp/Payload/$SCHEME.app"
      plist="$app/Info.plist"
      resources="$app"
      ;;
    mac)
      # Le .pkg n'est pas inspectable tel quel : on le déplie pour retrouver le .app livré,
      # celui-là même qui sera installé — pas celui de l'archive, qui n'a pas la signature
      # de distribution.
      pkgutil --expand-full "$product" "$tmp/pkg" >/dev/null
      app="$(find "$tmp/pkg" -maxdepth 3 -name "$SCHEME.app" -type d | head -1)"
      [ -n "$app" ] || die "aucun $SCHEME.app dans le paquet déplié"
      plist="$app/Contents/Info.plist"
      resources="$app/Contents/Resources"
      ;;
  esac
  [ -d "$app" ] || die "$SCHEME.app absent de l'artefact"

  # Les deux contrôles écrivent dans un fichier avant de grepper. Enchaîner un producteur
  # long dans `grep -q` le tue par SIGPIPE dès que grep trouve, et sous `set -o pipefail`
  # ce 141 devient le statut du pipeline — ce qui ferait échouer la vérification de
  # signature sur un artefact parfaitement sain et, pire, passer celle du harnais sans
  # rien avoir regardé.
  codesign -dvvv "$app" >"$tmp/codesign.txt" 2>&1 || die "codesign a échoué sur $app"
  grep -q '^Authority=Apple Distribution' "$tmp/codesign.txt" \
    || die "l'artefact n'est pas signé « Apple Distribution » — App Store Connect le refusera"
  ok "signature Apple Distribution"

  # Tous les exécutables du bundle, pas seulement le binaire principal : Xcode 16 déplace
  # déjà le code Debug dans un md\ Viewer.debug.dylib compagnon, qu'un contrôle lisant un
  # seul fichier manquerait.
  find "$app" -type f \( -perm -u+x -o -name '*.dylib' \) -print0 \
    | xargs -0 strings -a >"$tmp/strings.txt"

  # Canari. OKIA_LANG est injecté par le lecteur dans tous les builds, il DOIT être trouvé
  # ici. S'il ne l'est pas, `strings` ne voit pas les littéraux du binaire et le contrôle
  # suivant passerait sans rien inspecter — un feu vert qui ne veut rien dire.
  grep -q 'OKIA_LANG' "$tmp/strings.txt" \
    || die "contrôle inopérant : aucune chaîne connue trouvée dans le binaire (le test du harnais serait vide)"

  for marker in OKIA_FAKE_AI OKIA_RENDER_CONTENT OKIA_SHOT_SIZE; do
    # `if` plutôt que `grep ... && die` : un grep sans correspondance sortirait de la boucle
    # avec un statut non nul et `set -e` arrêterait le script sur un binaire sain.
    if grep -q "$marker" "$tmp/strings.txt"; then
      die "harnais de debug « $marker » présent dans le binaire de production"
    fi
  done
  ok "aucun harnais de debug dans le binaire"

  for lang in $LANGS; do
    [ -d "$resources/$lang.lproj" ] || die "localisation manquante : $lang.lproj"
  done
  ok "langues embarquées : $LANGS"

  local v b
  v="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  b="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
  [ "$v" = "$MARKETING" ] && [ "$b" = "$BUILD" ] \
    || die "l'artefact annonce $v ($b), project.yml dit $MARKETING ($BUILD)"
  ok "version conforme : $v ($b)"

  rm -rf "$tmp"

  # --- upload ------------------------------------------------------------------------
  if [ "$UPLOAD" = 0 ]; then
    printf '  \033[1marrêt avant envoi (--no-upload)\033[0m — artefact prêt : %s\n' "$product"
    return 0
  fi

  step "Envoi à App Store Connect ($altool_type)"
  xcrun altool --upload-app -f "$product" -t "$altool_type" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "$dir/upload.log" | tail -8

  grep -q 'UPLOAD SUCCEEDED' "$dir/upload.log" \
    || die "envoi échoué — log : $dir/upload.log"
  ok "$label envoyé"
}

for platform in $PLATFORMS; do
  deliver "$platform"
done

if [ "$UPLOAD" = 1 ]; then
  printf '\n\033[32m✓ %s (%s) envoyé — %s.\033[0m Apple traite le binaire 5 à 15 minutes\n' \
    "$MARKETING" "$BUILD" "$PLATFORMS"
  printf '  avant qu%s apparaisse dans TestFlight.\n' "'il"
fi
