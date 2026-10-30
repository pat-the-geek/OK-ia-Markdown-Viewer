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
#   scripts/screenshots.sh fr duo        l'iPhone Duo plié (écran extérieur)
#   scripts/screenshots.sh fr moyen      l'iPhone 6,3" (iPhone 17 Pro)
#   scripts/screenshots.sh fr deplie     l'iPhone Duo déplié (écran intérieur) — le déplier
#                                        d'abord dans Device Hub, qui ne se pilote pas
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
IPHONE_MOYEN="iPhone 17 Pro" # 1206 × 2622, l'emplacement « écran moyen » (6,1 et 6,3") mis en avant
DUO="iPhone Duo"               # plié : écran extérieur 1398 × 2034, l'emplacement « iPhone Duo »
ATTENTE=9                      # secondes : les tuiles vectorielles et Mermaid doivent être là

LANGUE="${1:-fr}"
CIBLE="${2:-tout}"

# Certaines scènes ne sont pas de simples documents : elles ouvrent un écran que seul un
# geste atteindrait. La règle vit ici, une fois, pour les deux plateformes.
#   01-accueil     → l'accueil en cartes, sur la démonstration (store/demo/<langue>, OKIA_DEMO)
#   03-entites     → les entités du document, en galerie   04-carte-entites → en carte
#   06-coffre      → l'analyse du coffre de démonstration
#   07-conversion  → la conversion en présentation, rejouée (voir rejeu_de)
#   08-diaporama   → le diaporama
#   09-resume      → le résumé IA          10-discussion → la discussion IA, une question posée
# Jeu de la 1.4 (28/10/2026) : dix scènes ; thèmes, Mermaid et carte d'une adresse sont sortis.
# Sur grand écran (Mac, iPad en paysage), la conversion, le résumé et la discussion s'ouvrent à
# côté du document ; sur l'iPhone, dans une feuille — l'app en décide, comme pour un lecteur.
# Une variable par ligne — une valeur peut contenir des espaces. Deuxième argument : la
# plateforme, « mac » ou « sim », car toutes deux n'ouvrent pas le même écran d'IA.
harnais_de() {
  local question plateforme="${2:-mac}"
  echo "OKIA_UI_LANG=$LANGUE"
  # Ni diagnostic de test ni réglage de l'utilisateur : la démonstration a son coffre, ses
  # documents analysés et son cache d'entités (OKIA_DEMO, posé par l'appelant).
  echo "OKIA_CAPTURE=1"
  # Le Mac garde l'apparence de son réglage (Patrick est en sombre) : l'app se met en clair
  # elle-même le temps de la capture, comme les simulateurs.
  [ "$plateforme" = mac ] && echo "OKIA_CLAIR=1"
  # Le thème est retenu d'un lancement à l'autre : chaque scène dit le sien, sans quoi celle des
  # thèmes déteindrait sur les suivantes.
  echo "OKIA_THEME=okia"
  case "$LANGUE" in
    en) question="Which fields have the most initiatives?" ;;
    de) question="Welche Bereiche haben die meisten Initiativen?" ;;
    es) question="¿Qué ámbitos tienen más iniciativas?" ;;
    it) question="Quali ambiti hanno più iniziative?" ;;
    nl) question="Welke domeinen hebben de meeste initiatieven?" ;;
    pt-BR) question="Quais áreas têm mais iniciativas?" ;;
    tr) question="En çok girişim hangi alanlarda?" ;;
    vi) question="Lĩnh vực nào có nhiều sáng kiến nhất?" ;;
    ru) question="В каких сферах больше всего инициатив?" ;;
    uk) question="У яких сферах найбільше ініціатив?" ;;
    ja) question="取り組みが最も多いのはどの分野ですか？" ;;
    zh-Hans) question="哪些领域的举措最多？" ;;
    ko) question="이니셔티브가 가장 많은 분야는 어디인가요?" ;;
    hi) question="किन क्षेत्रों में सबसे अधिक पहलें हैं?" ;;
    *)  question="Quels domaines comptent le plus d'initiatives ?" ;;
  esac
  case "$1" in
    01-accueil)     echo "OKIA_ACHAT=achete" ;;
    03-entites)     echo "OKIA_ACHAT=achete"; echo "OKIA_WIKIDATA=oui"; echo "OKIA_ANALYTIC=galerie" ;;
    04-carte-entites) echo "OKIA_ACHAT=achete"; echo "OKIA_WIKIDATA=oui"; echo "OKIA_ANALYTIC=carte" ;;
    06-coffre)      echo "OKIA_ACHAT=achete"; echo "OKIA_WIKIDATA=oui"; echo "OKIA_ANALYSE_COFFRE=1" ;;
    07-conversion)
      echo "OKIA_AI=convert"; echo "OKIA_AI_DELAY=2"
      # Figée à 7 diapositives sur 10 : la présentation est en train de se construire.
      echo "OKIA_CONVERSION_ARRET=7"
      ;;
    08-diaporama)   echo "OKIA_OPEN_SLIDES=1" ;;
    09-resume)      echo "OKIA_AI=summary"; echo "OKIA_AI_DELAY=1" ;;
    10-discussion)
      echo "OKIA_AI=chat"; echo "OKIA_AI_DELAY=1"
      # La question n'a de sens que là où le modèle répond. En simulateur la génération
      # échoue (GenerationError -1) : on s'en tient au premier écran de la discussion, dont
      # les questions proposées sortent du document lui-même — rien de fabriqué.
      if [ "$plateforme" = mac ]; then printf 'OKIA_AI_QUESTION=%s\n' "$question"; fi
      ;;
    *)              echo "" ;;
  esac
}

# Une réponse du modèle met plus longtemps à venir qu'une page à se dessiner ; le rejeu de la
# conversion, lui, livre une diapositive toutes les 0,8 s après l'ouverture.
# Les photos et descriptions des entités viennent de Wikidata, les vignettes de l'accueil de
# Wikimedia Commons : le réseau décide, on leur laisse le temps.
attente_de() { case "$1" in 09-resume|10-discussion) echo 30 ;; 07-conversion) echo 18 ;; 03-entites|04-carte-entites) echo 45 ;; 06-coffre) echo 60 ;; 01-accueil) echo 20 ;; *) echo "$ATTENTE" ;; esac; }

# Un document aux images embarquées (un import) dépasse ce qu'une variable d'environnement
# transmet : il passe par un fichier de la démonstration (OKIA_RENDER_FILE).
trop_gros() { [ "$(wc -c < "$1")" -gt 200000 ]; }

# Les scènes sans document : l'accueil et l'analyse du coffre, sur la démonstration.
sans_document() { case "$1" in 01-accueil|06-coffre) return 0 ;; *) return 1 ;; esac; }

# Le titre d'une scène : son premier titre, ou le `title:` de son en-tête YAML (un import).
titre_de() {
  if [ "$(head -1 "$1")" = "---" ]; then
    sed -n 's/^title: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$1" | head -1
  else
    head -1 "$1" | sed 's/^# *//'
  fi
}

# La conversion ne se capture pas en direct : le simulateur ne génère pas, et le modèle du Mac
# met un temps variable. Elle rejoue la présentation que le vrai modèle a écrite pour cette
# langue (tools/ConversionBench, sur le Mac) et qui sert aussi la scène du diaporama. Le contenu
# vient du modèle ; seul le rythme est simulé. Une valeur sur plusieurs lignes : elle ne passe
# pas par harnais_de.
rejeu_de() { case "$1" in 07-conversion) cat "store/scenes/$LANGUE/08-diaporama.md" ;; *) ;; esac; }

# Le résumé demande une génération, et le simulateur en est incapable : Apple Intelligence
# s'y annonce disponible (il emprunte le modèle du Mac hôte) mais la génération échoue.
# Cette scène-là reste au Mac.
scene_reservee_au_mac() { case "$1" in 09-resume) return 0 ;; *) return 1 ;; esac; }

# L'iPad couché ouvre le mode livre : bon pour ce qui s'ouvre à côté du document, mais un
# document court y laisse la page de droite vide, et le livre cache la barre. Lecteur, thèmes,
# Mermaid et carte se prennent donc en portrait ; conversion, diaporama et discussion en paysage
# (Patrick, 09/10/2026). Une passe par orientation : IPAD_PAYSAGE=1 ne prend que les secondes.
ipad_en_paysage() { case "$1" in 07-conversion|08-diaporama|10-discussion) return 0 ;; *) return 1 ;; esac; }

# Région du simulateur : le format de date suit la locale, pas seulement la langue.
locale_systeme() {
  case "$LANGUE" in
    en) echo en_US ;; es) echo es_ES ;;   # es_CH n'existe pas
    fr|de|it) echo "${LANGUE}_CH" ;;
    ja) echo ja_JP ;; ko) echo ko_KR ;; zh-Hans) echo zh_CN ;; pt-BR) echo pt_BR ;; nl) echo nl_NL ;;
    ru) echo ru_RU ;; uk) echo uk_UA ;; tr) echo tr_TR ;; vi) echo vi_VN ;; hi) echo hi_IN ;;
    *) echo "${LANGUE}" ;;
  esac
}

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
  aplatir "$f"
}

# Apple refuse la transparence, et les coins arrondis de la fenêtre en laissent : sips ne
# sait pas aplatir (« padToHeightWidth » garde le canal alpha), d'où ce passage par Pillow.
aplatir() {
  python3 - "$1" <<'PYTHON' || die "aplatissement impossible — Pillow manquant ? (python3 -m pip install pillow)"
import sys
from PIL import Image
chemin = sys.argv[1]
im = Image.open(chemin)
if im.mode in ("RGBA", "LA", "P"):
    im = im.convert("RGBA")
    fond = Image.new("RGB", im.size, (0xFA, 0xFA, 0xF8))
    fond.paste(im, mask=im.getchannel("A"))
    fond.save(chemin)
PYTHON
}

# Les rapports du coffre de démonstration portent une date d'en-tête, comptée depuis le
# 28/10/2026 : la veille, une semaine avant… Leur fichier prend le même écart depuis le jour de la
# capture, pour que l'accueil les range toujours sous les mêmes intitulés (« Hier », « 7 derniers
# jours »). Les documents analysés, copiés à l'instant, sont « d'aujourd'hui ».
dater_demo() {
  python3 - "$1" <<'PYTHON'
import datetime, os, pathlib, re, sys, time
reference = datetime.date(2026, 10, 28)
for f in pathlib.Path(sys.argv[1]).rglob("*.md"):
    # Seuls les rapports du coffre : le dossier des documents analysés change de nom avec la langue.
    if "/rapports-" not in "/" + str(f.relative_to(sys.argv[1])):
        continue
    m = re.search(r"^date: *(\d{4})-(\d{2})-(\d{2})", f.read_text(encoding="utf-8"), re.M)
    if not m:
        continue
    ecart = (reference - datetime.date(*map(int, m.groups()))).days
    jour = datetime.datetime.combine(datetime.date.today() - datetime.timedelta(days=ecart), datetime.time(10))
    os.utime(f, (time.mktime(jour.timetuple()),) * 2)
PYTHON
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
  # Le Duo déplié n'y passe pas : le redémarrage le replie (Device Hub seul le déplie), et sa
  # barre d'état ne montre que l'heure — la langue de l'app passe par OKIA_UI_LANG.
  if [ "$dossier" != "iphone-duo-deplie" ] && \
     [ "$(xcrun simctl spawn "$dev" defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n(),"' )" != "$LANGUE" ]; then
    xcrun simctl spawn "$dev" defaults write -g AppleLanguages -array "$LANGUE" >/dev/null 2>&1 || true
    xcrun simctl spawn "$dev" defaults write -g AppleLocale -string "$(locale_systeme)" >/dev/null 2>&1 || true
    # Le redémarrage remet l'iPad en portrait, et le paysage ne se rétablit qu'à la main, dans
    # Device Hub (redémarrer SpringBoard seul n'y suffit pas : l'orientation ne lui parvient
    # plus). En paysage, la langue se règle donc avant, simulateur tourné ensuite.
    if [ -n "${IPAD_PAYSAGE:-}" ] && [ "$dossier" = "ipad-13" ]; then
      die "iPad en paysage : régler d'abord la langue « $LANGUE », redémarrer, tourner, puis relancer"
    fi
    xcrun simctl shutdown "$dev" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1 || true
  fi

  xcrun simctl install "$dev" "$APP" >/dev/null
  # La démonstration (coffre, documents analysés) dans le conteneur de l'app, neuve à chaque
  # passe : son cache d'entités repart de zéro, comme chez un nouvel utilisateur.
  local demo
  demo="$(xcrun simctl get_app_container "$dev" "$BUNDLE" data)/tmp/okia-demo"
  rm -rf "$demo"; cp -R "store/demo/$LANGUE" "$demo"
  dater_demo "$demo"
  # Les captures sont en clair, quel que soit l'état où un essai a laissé le simulateur.
  xcrun simctl ui "$dev" appearance light >/dev/null 2>&1 || true

  # Barre d'état figée : l'usage App Store veut une heure neutre, du wifi plein et une
  # batterie pleine. Sans quoi chaque capture porte l'heure de sa génération — et, si
  # l'app a été lancée depuis une autre, un fil d'Ariane « ◀ … » qui n'a rien à y faire.
  xcrun simctl status_bar "$dev" override \
    --time "09:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode notSupported --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true

  # Les captures d'une passe précédente ne survivent pas : une scène renommée laisserait
  # l'ancienne image en place, prête à partir avec les autres.
  # Sur l'iPad, chaque passe ne remplace que ses scènes : l'autre orientation garde les siennes.
  if [ "$dossier" != "ipad-13" ]; then rm -f "store/screenshots/$dossier/$LANGUE"/*.png; fi
  mkdir -p "store/screenshots/$dossier/$LANGUE"
  for scene in store/scenes/"$LANGUE"/*.md; do
    local base titre
    base="$(basename "$scene" .md)"
    titre="$(titre_de "$scene")"
    if scene_reservee_au_mac "$base"; then continue; fi
    if [ "$dossier" = "ipad-13" ]; then
      if [ -n "${IPAD_PAYSAGE:-}" ]; then ipad_en_paysage "$base" || continue
      else ipad_en_paysage "$base" && continue; fi
    fi
    # simctl transmet à l'app ce qui est préfixé SIMCTL_CHILD_.
    local -a sim_extra=()
    while IFS= read -r paire; do
      [ -n "$paire" ] && sim_extra+=("SIMCTL_CHILD_$paire")
    done < <(harnais_de "$base" sim)
    # L'orientation est dite à chaque lancement : un simulateur garde celle du dernier essai.
    if [ "$dossier" = "ipad-13" ] && [ -n "${IPAD_PAYSAGE:-}" ]; then
      sim_extra+=("SIMCTL_CHILD_OKIA_ORIENTATION=paysage")
    else
      sim_extra+=("SIMCTL_CHILD_OKIA_ORIENTATION=portrait")
    fi
    local rejeu; rejeu="$(rejeu_de "$base")"
    [ -n "$rejeu" ] && sim_extra+=("SIMCTL_CHILD_OKIA_CONVERSION_REJEU=$rejeu")
    sim_extra+=("SIMCTL_CHILD_OKIA_DEMO=$demo")
    if sans_document "$base"; then :
    elif trop_gros "$scene"; then
      cp "$scene" "$demo/scene.md"
      sim_extra+=("SIMCTL_CHILD_OKIA_RENDER_FILE=$demo/scene.md" "SIMCTL_CHILD_OKIA_RENDER_NAME=$titre.md")
    else
      sim_extra+=("SIMCTL_CHILD_OKIA_RENDER_CONTENT=$(cat "$scene")" "SIMCTL_CHILD_OKIA_RENDER_NAME=$titre.md")
    fi
    xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1 || true
    # (l'expansion protégée : un tableau vide fait échouer set -u en bash 3.2)
    env ${sim_extra[@]+"${sim_extra[@]}"} xcrun simctl launch "$dev" "$BUNDLE" >/dev/null
    sleep "$(attente_de "$base")"
    # Le Duo plié n'allume que son écran extérieur ; la capture par défaut prend l'intérieur,
    # noir. « --display=1 » vise l'extérieur, borné : un écran éteint fait attendre sans fin.
    local ecran=()
    [ "$dossier" = "iphone-duo" ] && ecran=(--display=1)
    # Déplié, l'écran intérieur (2007 × 2853) : son identifiant change d'un démarrage à
    # l'autre, on le cherche à sa taille.
    if [ "$dossier" = "iphone-duo-deplie" ]; then
      local interieur
      interieur="$(xcrun simctl io "$dev" enumerate 2>/dev/null | awk '/UUID/{u=$2} /Default width: 2007/{print u; exit}')"
      [ -n "$interieur" ] && ecran=(--display="$interieur")
    fi
    perl -e 'alarm 25; exec @ARGV' xcrun simctl io "$dev" screenshot ${ecran[@]+"${ecran[@]}"} \
      "store/screenshots/$dossier/$LANGUE/$base.png" >/dev/null 2>&1
    # Le framebuffer du simulateur est opaque mais garde un canal alpha, qu'Apple ne veut pas.
    aplatir "store/screenshots/$dossier/$LANGUE/$base.png"
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
  # ⚠️ Ces réglages vivent dans le conteneur de l'app, que macOS protège (« données d'autres
  # apps ») : un terminal sans cette autorisation se voit refuser l'écriture — constaté le
  # 19/09/2026. On continue alors : la taille passe aussi par OKIA_SHOT_SIZE, que l'app
  # applique à sa fenêtre en mode capture ; seule une taille de texte réglée à la main
  # resterait en place (vérifier les captures).
  if ! defaults write "$BUNDLE" "NSWindow Frame MainSceneWindow" "0 0 $fen_l $fen_h $ecran " 2>/dev/null \
     || ! defaults write "$BUNDLE" okia.fontScale -float 1.0 2>/dev/null; then
    printf '  \033[33m…\033[0m conteneur protégé : réglages non écrits, taille via OKIA_SHOT_SIZE\n'
  fi
  # Le réveil doit tenir toute la passe, pas cinq minutes : à l'expiration, l'écran
  # s'éteignait au milieu du travail et l'app n'ouvrait plus aucune fenêtre — les scènes
  # restantes échouaient sur « aucune fenêtre trouvée », sans rapport avec elles. Sans
  # limite ici : la boucle tue le processus en sortant, y compris en cas d'erreur.
  # Écran éteint = aucune fenêtre : l'app se lance, tourne, et n'affiche rien. Deux gestes
  # distincts sont nécessaires — « -u -t 1 » réveille l'écran s'il dort déjà, « -d » l'empêche
  # de se rendormir. Sans le premier, une passe lancée sur une machine au repos échouait sur
  # toutes ses scènes ; sans le second, elle échouait à partir de la cinquième minute.
  caffeinate -u -t 5
  caffeinate -d -u &
  local veille=$!
  trap 'kill "$veille" 2>/dev/null || true' RETURN
  # SOLO=<scène> ne refait que celle-là (une réponse du modèle à reprendre) : les autres restent.
  [ -n "${SOLO:-}" ] || rm -f "store/screenshots/$dossier/$LANGUE"/*.png
  mkdir -p "store/screenshots/$dossier/$LANGUE"
  # La démonstration, copiée hors du dépôt : l'app de capture n'est pas signée, donc hors du bac
  # à sable, et lit ce dossier directement ; neuve à chaque passe, comme au simulateur.
  local demo_mac="${TMPDIR:-/tmp}okia-demo-$LANGUE"
  rm -rf "$demo_mac"; cp -R "store/demo/$LANGUE" "$demo_mac"
  dater_demo "$demo_mac"

  for scene in store/scenes/"$LANGUE"/*.md; do
    local base titre extra
    base="$(basename "$scene" .md)"
    if [ -n "${SOLO:-}" ] && [ "$base" != "$SOLO" ]; then continue; fi
    titre="$(titre_de "$scene")"
    pkill -f "Debug-maccatalyst/$SCHEME.app" 2>/dev/null || true
    sleep 1
    launchctl unsetenv OKIA_RENDER_CONTENT; launchctl unsetenv OKIA_RENDER_FILE; launchctl unsetenv OKIA_RENDER_NAME
    if sans_document "$base"; then :
    elif trop_gros "$scene"; then
      cp "$scene" "$demo_mac/scene.md"
      launchctl setenv OKIA_RENDER_FILE "$demo_mac/scene.md"
      launchctl setenv OKIA_RENDER_NAME "$titre.md"
    else
      launchctl setenv OKIA_RENDER_CONTENT "$(cat "$scene")"
      launchctl setenv OKIA_RENDER_NAME "$titre.md"
    fi
    launchctl setenv OKIA_DEMO "$demo_mac"
    launchctl setenv OKIA_SHOT_SIZE "$FENETRE"
    launchctl setenv OKIA_FONT_SCALE 1.0
    # Le harnais éventuel de la scène : sans lui il faudrait cliquer, ce qu'une capture
    # headless ne sait pas faire.
    for v in OKIA_OPEN_SLIDES OKIA_AI OKIA_AI_QUESTION OKIA_UI_LANG OKIA_AI_DELAY OKIA_THEME \
             OKIA_APPARENCE OKIA_CONVERSION_REJEU OKIA_CONVERSION_ARRET OKIA_CLAIR OKIA_CAPTURE \
             OKIA_ACHAT OKIA_WIKIDATA OKIA_ANALYTIC OKIA_ANALYSE_COFFRE; do launchctl unsetenv "$v"; done
    while IFS= read -r paire; do
      [ -n "$paire" ] && launchctl setenv "${paire%%=*}" "${paire#*=}"
    done < <(harnais_de "$base" mac)
    [ -n "$(rejeu_de "$base")" ] && launchctl setenv OKIA_CONVERSION_REJEU "$(rejeu_de "$base")"
    # Attendre la fenêtre plutôt qu'un délai fixe : selon la charge, elle apparaît en deux
    # secondes ou en douze, et un délai constant rate l'une ou l'autre. Puis laisser le
    # contenu se dessiner — tuiles vectorielles et Mermaid arrivent après la fenêtre.
    #
    # Deux tentatives : une fois sur six environ, « open -n » rend la main sans qu'aucune
    # fenêtre n'apparaisse — l'instance précédente n'a pas fini de rendre l'âme. Le second
    # essai passe toujours, et laisser tomber la scène coûtait une passe entière.
    id=""
    for essai in 1 2; do
      open -n "$bin_app"
      for _ in $(seq 1 30); do
        id="$("$HELPER" "$SCHEME" 2>/dev/null | cut -d' ' -f1 || true)"
        [ -n "$id" ] && break
        sleep 1
      done
      [ -n "$id" ] && break
      printf '  \033[33m…\033[0m %s — pas de fenêtre, seconde tentative\n' "$base"
      pkill -f "Debug-maccatalyst/$SCHEME.app" 2>/dev/null || true
      sleep 3
    done
    if [ -z "$id" ]; then printf '  \033[31m✗\033[0m %s — aucune fenêtre trouvée\n' "$base"; continue; fi
    sleep "$(attente_de "$base")"
    screencapture -x -o -l"$id" "store/screenshots/$dossier/$LANGUE/$base.png"
    normaliser "store/screenshots/$dossier/$LANGUE/$base.png"
    ok "$base.png"
  done

  pkill -f "Debug-maccatalyst/$SCHEME.app" 2>/dev/null || true
  # La taille de texte de l'utilisateur lui est rendue par l'app elle-même (OKIA_FONT_SCALE).
  for v in OKIA_RENDER_CONTENT OKIA_RENDER_NAME OKIA_OPEN_SLIDES OKIA_AI OKIA_AI_QUESTION \
           OKIA_AI_DELAY OKIA_THEME OKIA_APPARENCE OKIA_CONVERSION_REJEU OKIA_CONVERSION_ARRET \
           OKIA_CAPTURE OKIA_ACHAT OKIA_WIKIDATA OKIA_ANALYTIC OKIA_ANALYSE_COFFRE OKIA_DEMO OKIA_RENDER_FILE; do
    launchctl unsetenv "$v"
  done
  launchctl setenv OKIA_FONT_SCALE restaurer
  open -n "$bin_app"; sleep 8
  pkill -f "Debug-maccatalyst/$SCHEME.app" 2>/dev/null || true
  launchctl unsetenv OKIA_FONT_SCALE
  kill "$veille" 2>/dev/null || true
  for v in OKIA_RENDER_CONTENT OKIA_RENDER_NAME OKIA_SHOT_SIZE OKIA_OPEN_SLIDES OKIA_AI \
           OKIA_AI_QUESTION OKIA_UI_LANG OKIA_AI_DELAY OKIA_THEME OKIA_APPARENCE \
           OKIA_CONVERSION_REJEU OKIA_CONVERSION_ARRET OKIA_CLAIR OKIA_CAPTURE OKIA_ACHAT \
           OKIA_WIKIDATA OKIA_ANALYTIC OKIA_ANALYSE_COFFRE OKIA_DEMO OKIA_RENDER_FILE; do launchctl unsetenv "$v"; done
  # On rend la machine dans l'état où on l'a trouvée.
  [ -n "$ancien_scale" ] && { defaults write "$BUNDLE" okia.fontScale -float "$ancien_scale" 2>/dev/null || true; }
  [ -n "$ancien_cadre" ] && { defaults write "$BUNDLE" "NSWindow Frame MainSceneWindow" "$ancien_cadre" 2>/dev/null || true; }
  ok "réglages de la machine restaurés"
}

case "$CIBLE" in
  iphone) capture_appareil "$IPHONE" "iphone-6.9" ;;
  duo)    capture_appareil "$DUO"    "iphone-duo" ;;
  moyen)  capture_appareil "$IPHONE_MOYEN" "iphone-6.3" ;;
  deplie) capture_appareil "$DUO"    "iphone-duo-deplie" ;;
  ipad)   capture_appareil "$IPAD"   "ipad-13" ;;
  mac)    capture_mac ;;
  *)      capture_appareil "$IPHONE" "iphone-6.9"; capture_appareil "$IPAD" "ipad-13"; capture_mac ;;
esac

printf '\n\033[32m✓ captures %s dans store/screenshots/*/%s/\033[0m\n' "$LANGUE" "$LANGUE"
