#!/usr/bin/env bash
# Captures App Store, en headless — iPhone et iPad, une langue par passage.
#
# Le hook `#if DEBUG` de l'app lit OKIA_RENDER_CONTENT / OKIA_RENDER_NAME et rend ce
# Markdown directement dans le lecteur : aucune interaction, donc aucun clic à scripter.
# La langue passe par OKIA_UI_LANG : une app sandboxée ne voit pas les préférences écrites
# de l'extérieur, l'environnement est le seul canal qu'un lancement scripté puisse forcer.
#
# Usage :
#   scripts/screenshots.sh fr            les scènes en français, iPhone 6,9" et iPad 13"
#   scripts/screenshots.sh en            idem en anglais
#   scripts/screenshots.sh fr iphone     une seule famille d'appareils
#   scripts/screenshots.sh fr mac        le Mac (Catalyst), sur cette machine
#
# Les scènes sont les fichiers de store/scenes/<langue>/<n>-<nom>.md ; la capture prend le
# même nom. Sortie dans store/screenshots/<appareil>/<langue>/.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="OK-ia - md Viewer.xcodeproj"
SCHEME="md Viewer"
TEAM_ID="PU9BSXN2V5"
BUNDLE="ch.ok-ia.markdownviewer"
IPHONE="iPhone 17 Pro Max"     # 1320 × 2868, le slot 6,9" demandé par App Store Connect
IPAD="iPad Pro 13-inch (M5)"   # 2064 × 2752, le slot 13"
ATTENTE=9                      # secondes : les tuiles vectorielles et Mermaid doivent être là

LANGUE="${1:-fr}"
CIBLE="${2:-tout}"

# Certaines scènes ne sont pas de simples documents : elles ouvrent un écran que seul un
# geste atteindrait. La règle vit ici, une fois, pour les deux plateformes.
#   4-presentation → le diaporama          5-resume → le résumé IA
#                                          6-discussion → la discussion IA, une question posée
# Une variable par ligne — une valeur peut contenir des espaces. Deuxième argument : la
# plateforme, « mac » ou « sim », car toutes deux n'ouvrent pas le même écran d'IA.
harnais_de() {
  local question plateforme="${2:-mac}"
  echo "OKIA_UI_LANG=$LANGUE"
  case "$LANGUE" in
    en) question="Which fields have the most initiatives?" ;;
    *)  question="Quels domaines comptent le plus d'initiatives ?" ;;
  esac
  case "$1" in
    4-presentation) echo "OKIA_PRESENT=1" ;;
    5-resume)       echo "OKIA_AI=summary" ;;
    6-discussion)
      echo "OKIA_AI=chat"
      # La question n'a de sens que là où le modèle répond. En simulateur la génération
      # échoue (GenerationError -1) : on s'en tient au premier écran de la discussion, dont
      # les questions proposées sortent du document lui-même — rien de fabriqué.
      if [ "$plateforme" = mac ]; then printf 'OKIA_AI_QUESTION=%s\n' "$question"; fi
      ;;
    *)              echo "" ;;
  esac
}

# Une réponse du modèle met plus longtemps à venir qu'une page à se dessiner.
attente_de() { case "$1" in 5-resume|6-discussion) echo 30 ;; *) echo "$ATTENTE" ;; esac; }

# Le résumé demande une génération, et le simulateur en est incapable : Apple Intelligence
# s'y annonce disponible (il emprunte le modèle du Mac hôte) mais la génération échoue.
# Cette scène-là reste au Mac.
scene_reservee_au_mac() { case "$1" in 5-resume) return 0 ;; *) return 1 ;; esac; }

# Région du simulateur : le format de date suit la locale, pas seulement la langue.
locale_systeme() { case "$LANGUE" in en) echo en_US ;; *) echo "${LANGUE}_CH" ;; esac; }

# Apple accepte 2880×1800, 2560×1600, 1440×900 ou 1280×800 pour le Mac. On recadre au
# format 16:10 — quelques pixels au plus — puis on va chercher la taille acceptée la plus
# proche par le dessous : agrandir une capture la rendrait floue.
MAC_CIBLE_L=2560
MAC_CIBLE_H=1600
normaliser() {
  local f="$1" l h cl ch
  l="$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')"
  h="$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')"
  cl=$(( h * 16 / 10 )); ch="$h"
  if [ "$cl" -gt "$l" ]; then cl="$l"; ch=$(( l * 10 / 16 )); fi
  sips -c "$ch" "$cl" "$f" >/dev/null 2>&1
  sips -z "$MAC_CIBLE_H" "$MAC_CIBLE_L" "$f" >/dev/null 2>&1
}

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

  # La langue du simulateur, pas seulement celle de l'app : la barre d'état de l'iPad porte
  # la date, écrite par SpringBoard dans la langue du système — un simulateur laissé en
  # espagnol donnait « Viernes 4 de septiembre » sur une capture anglaise. Le changement ne
  # prend qu'au redémarrage de SpringBoard.
  if [ "$(xcrun simctl spawn "$dev" defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n(),"' )" != "$LANGUE" ]; then
    xcrun simctl spawn "$dev" defaults write -g AppleLanguages -array "$LANGUE" >/dev/null 2>&1 || true
    xcrun simctl spawn "$dev" defaults write -g AppleLocale -string "$(locale_systeme)" >/dev/null 2>&1 || true
    xcrun simctl shutdown "$dev" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1 || true
  fi

  xcrun simctl install "$dev" "$APP" >/dev/null

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
    if scene_reservee_au_mac "$base"; then continue; fi
    # simctl transmet à l'app ce qui est préfixé SIMCTL_CHILD_.
    local -a sim_extra=()
    while IFS= read -r paire; do
      [ -n "$paire" ] && sim_extra+=("SIMCTL_CHILD_$paire")
    done < <(harnais_de "$base" sim)
    xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1 || true
    # (l'expansion protégée : un tableau vide fait échouer set -u en bash 3.2)
    env ${sim_extra[@]+"${sim_extra[@]}"} \
      SIMCTL_CHILD_OKIA_RENDER_CONTENT="$(cat "$scene")" \
      SIMCTL_CHILD_OKIA_RENDER_NAME="$titre.md" \
      xcrun simctl launch "$dev" "$BUNDLE" >/dev/null
    sleep "$ATTENTE"
    xcrun simctl io "$dev" screenshot "store/screenshots/$dossier/$LANGUE/$base.png" >/dev/null 2>&1
    ok "$base.png"
  done
  xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1 || true
}

# Le repérage de la fenêtre Mac passe par Quartz, absent du python du système : un binaire
# Swift minuscule, compilé une fois et gardé dans build/.
HELPER="build/okia-windowid"
if [ ! -x "$HELPER" ] && { [ "$CIBLE" = "mac" ] || [ "$CIBLE" = "tout" ]; }; then
  mkdir -p build
  cat > /tmp/okia-windowid.swift <<'SWIFT'
import CoreGraphics
import Foundation
let cible = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "md Viewer"
guard let fenetres = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for f in fenetres {
    let proprietaire = f[kCGWindowOwnerName as String] as? String ?? ""
    let couche = f[kCGWindowLayer as String] as? Int ?? -1
    let bornes = f[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let l = bornes["Width"] as? Double ?? 0, h = bornes["Height"] as? Double ?? 0
    if proprietaire.contains(cible), couche == 0, l > 400, h > 300 {
        print(f[kCGWindowNumber as String] as? Int ?? 0, Int(l), Int(h)); exit(0)
    }
}
exit(2)
SWIFT
  swiftc -O /tmp/okia-windowid.swift -o "$HELPER" 2>/dev/null || true
fi

step "Construction (Debug — le hook de capture n'existe pas en Release)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO >/tmp/okia-shots-build.log 2>&1 \
  || { grep -E 'error:' /tmp/okia-shots-build.log | head -10; die "build échoué"; }
APP="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ TARGET_BUILD_DIR/{print $2}' | head -1)/md Viewer.app"
[ -d "$APP" ] || die "app introuvable après le build : $APP"
ok "$(basename "$APP")"

# --- Mac ------------------------------------------------------------------------------
# Rien à voir avec le simulateur : l'app tourne sur cette machine, et c'est la fenêtre du
# Window Server qu'on photographie.
#
# Deux contraintes apprises à la dure : `open` ne transmet PAS l'environnement (il passe par
# LaunchServices), d'où le détour par `launchctl setenv` ; et lancer le binaire directement
# ne crée aucune fenêtre. L'écran doit par ailleurs être réveillé, sinon la capture est noire.
capture_mac() {
  local bin_app dossier="mac" id largeur FENETRE
  step "Mac Catalyst — $LANGUE"

  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug \
    build CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="$TEAM_ID" >/tmp/okia-shots-mac.log 2>&1 \
    || { grep -E 'error:' /tmp/okia-shots-mac.log | head -10; die "build Catalyst échoué"; }
  bin_app="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ TARGET_BUILD_DIR/{print $2}' | head -1)/$SCHEME.app"
  [ -d "$bin_app" ] || die "app Catalyst introuvable : $bin_app"
  ok "$(basename "$bin_app")"

  # Réglages de la machine mis de côté le temps des captures, puis rendus tels quels : ce
  # sont les préférences de quelqu'un, pas des paramètres de génération. La taille de texte
  # en particulier — réglée à 1,6× ici — donnerait des captures store hors norme.
  local ancien_scale ancien_cadre ecran
  ancien_scale="$(defaults read "$BUNDLE" okia.fontScale 2>/dev/null || true)"
  ancien_cadre="$(defaults read "$BUNDLE" "NSWindow Frame MainSceneWindow" 2>/dev/null || true)"
  # Le cadre de fenêtre est le seul levier fiable : les restrictions de taille ne
  # redimensionnent pas une fenêtre restaurée, et la demande de géométrie est ignorée.
  #
  # La taille visée est la plus grande fenêtre 16:10 qui tient sous la barre des menus. Un
  # point ne vaut pas partout deux pixels — sur un écran en résolution ajustée il en vaut
  # 1,54 — donc viser « 1440 × 900 points = 2880 × 1800 pixels » était faux : la capture
  # sortait à 2094 × 1326 et sips complétait le reste en crème. La moitié de l'image était
  # du fond. On prend l'écran, et le redimensionnement final va chercher la taille d'Apple.
  ecran="$(printf '%s' "$ancien_cadre" | awk '{print $5, $6, $7, $8}')"
  [ -n "$ecran" ] || ecran="0 0 1710 1073"
  local ecran_l ecran_h fen_l fen_h
  ecran_l="$(printf '%s' "$ecran" | awk '{print $3}')"
  ecran_h="$(printf '%s' "$ecran" | awk '{print $4}')"
  fen_h=$(( ecran_h - 37 ))                 # la barre des menus
  fen_l=$(( fen_h * 16 / 10 ))
  if [ "$fen_l" -gt "$ecran_l" ]; then fen_l="$ecran_l"; fen_h=$(( fen_l * 10 / 16 )); fi
  FENETRE="${fen_l}x${fen_h}"
  defaults write "$BUNDLE" "NSWindow Frame MainSceneWindow" "0 0 $fen_l $fen_h $ecran "
  defaults write "$BUNDLE" okia.fontScale -float 1.0
  caffeinate -u -t 300 &
  local veille=$!
  mkdir -p "store/screenshots/$dossier/$LANGUE"

  for scene in store/scenes/"$LANGUE"/*.md; do
    local base titre extra
    base="$(basename "$scene" .md)"
    titre="$(head -1 "$scene" | sed 's/^# *//')"
    pkill -f "Debug-maccatalyst/$SCHEME.app" 2>/dev/null || true
    sleep 1
    launchctl setenv OKIA_RENDER_CONTENT "$(cat "$scene")"
    launchctl setenv OKIA_RENDER_NAME "$titre.md"
    launchctl setenv OKIA_SHOT_SIZE "$FENETRE"
    # Le harnais éventuel de la scène : sans lui il faudrait cliquer, ce qu'une capture
    # headless ne sait pas faire.
    for v in OKIA_PRESENT OKIA_AI OKIA_AI_QUESTION OKIA_UI_LANG; do launchctl unsetenv "$v"; done
    while IFS= read -r paire; do
      [ -n "$paire" ] && launchctl setenv "${paire%%=*}" "${paire#*=}"
    done < <(harnais_de "$base" mac)
    open -n "$bin_app"
    # Attendre la fenêtre plutôt qu'un délai fixe : selon la charge, elle apparaît en deux
    # secondes ou en douze, et un délai constant rate l'une ou l'autre. Puis laisser le
    # contenu se dessiner — tuiles vectorielles et Mermaid arrivent après la fenêtre.
    id=""
    for _ in $(seq 1 30); do
      id="$("$HELPER" "$SCHEME" 2>/dev/null | cut -d' ' -f1 || true)"
      [ -n "$id" ] && break
      sleep 1
    done
    if [ -z "$id" ]; then printf '  \033[31m✗\033[0m %s — aucune fenêtre trouvée\n' "$base"; continue; fi
    sleep "$(attente_de "$base")"
    screencapture -x -o -l"$id" "store/screenshots/$dossier/$LANGUE/$base.png"
    normaliser "store/screenshots/$dossier/$LANGUE/$base.png"
    ok "$base.png"
  done

  pkill -f "Debug-maccatalyst/$SCHEME.app" 2>/dev/null || true
  kill "$veille" 2>/dev/null || true
  for v in OKIA_RENDER_CONTENT OKIA_RENDER_NAME OKIA_SHOT_SIZE OKIA_PRESENT OKIA_AI \
           OKIA_AI_QUESTION OKIA_UI_LANG; do launchctl unsetenv "$v"; done
  # On rend la machine dans l'état où on l'a trouvée.
  [ -n "$ancien_scale" ] && defaults write "$BUNDLE" okia.fontScale -float "$ancien_scale"
  [ -n "$ancien_cadre" ] && defaults write "$BUNDLE" "NSWindow Frame MainSceneWindow" "$ancien_cadre"
  ok "réglages de la machine restaurés"
}

case "$CIBLE" in
  iphone) capture_appareil "$IPHONE" "iphone-6.9" ;;
  ipad)   capture_appareil "$IPAD"   "ipad-13" ;;
  mac)    capture_mac ;;
  *)      capture_appareil "$IPHONE" "iphone-6.9"; capture_appareil "$IPAD" "ipad-13"; capture_mac ;;
esac

printf '\n\033[32m✓ captures %s dans store/screenshots/*/%s/\033[0m\n' "$LANGUE" "$LANGUE"
