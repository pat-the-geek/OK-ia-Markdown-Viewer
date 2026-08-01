#!/usr/bin/env bash
# Publie site/mdviewer/ sur ok-ia.ch par FTP, puis vérifie la page en ligne.
#
# Identifiants dans scripts/deploy-site.env (jamais commité) ou dans l'environnement :
#   FTP_HOST        hôte FTP (sans ftp://)
#   FTP_USER        utilisateur
#   FTP_PASSWORD    mot de passe
#   FTP_REMOTE_DIR  dossier distant visé, ex. /public_html/mdviewer ou /www/mdviewer
#   FTP_ALLOW_PLAIN mettre à 1 pour autoriser le FTP en clair (déconseillé, voir plus bas)
#
# Usage :
#   scripts/deploy-site.sh              téléverse la page seule (index.html)
#   scripts/deploy-site.sh --all        téléverse tout le dossier mdviewer/
#   scripts/deploy-site.sh --dry-run    montre ce qui partirait, sans rien envoyer
#
# Deux choix de sécurité, délibérés :
#   - TLS exigé par défaut (--ssl-reqd). Le FTP nu envoie le mot de passe en clair sur le
#     réseau ; FTP_ALLOW_PLAIN=1 lève la contrainte si l'hébergeur ne sait pas faire mieux.
#   - Les identifiants passent par un fichier de configuration lu sur l'entrée standard de
#     curl, jamais par ses arguments : la ligne de commande est visible dans `ps` par tout
#     utilisateur de la machine.

set -euo pipefail
cd "$(dirname "$0")/.."

LOCAL_DIR="site/mdviewer"
PUBLIC_URL="https://ok-ia.ch/mdviewer/"

ALL=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --all)     ALL=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         printf 'argument inconnu : %s\n' "$arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# --- identifiants ---------------------------------------------------------------------
# shellcheck source=/dev/null
[ -f scripts/deploy-site.env ] && . scripts/deploy-site.env
: "${FTP_HOST:?manquant — copiez scripts/deploy-site.env.example vers scripts/deploy-site.env}"
: "${FTP_USER:?manquant — voir scripts/deploy-site.env.example}"
: "${FTP_PASSWORD:?manquant — voir scripts/deploy-site.env.example}"
: "${FTP_REMOTE_DIR:?manquant — voir scripts/deploy-site.env.example}"
FTP_ALLOW_PLAIN="${FTP_ALLOW_PLAIN:-0}"

TLS_OPT="--ssl-reqd"
if [ "$FTP_ALLOW_PLAIN" = "1" ]; then
  TLS_OPT=""
  warn "FTP en clair : le mot de passe circule non chiffré (FTP_ALLOW_PLAIN=1)"
fi

# --- fichiers à envoyer ---------------------------------------------------------------
# site/style.css n'est PAS dans site/mdviewer/ : c'est une copie locale pour la
# prévisualisation, le site a déjà la sienne. Ne téléverser que mdviewer/ suffit à l'exclure.
if [ "$ALL" = 1 ]; then
  FILES=$(cd "$LOCAL_DIR" && find . -type f ! -name '.*' | sed 's|^\./||' | sort)
else
  FILES="index.html"
fi

step "Contrôles avant envoi"
[ -f "$LOCAL_DIR/index.html" ] || die "$LOCAL_DIR/index.html introuvable"

# Une page cassée mise en ligne est pire qu'une page périmée : on vérifie la structure
# avant de l'envoyer, pas après.
python3 - "$LOCAL_DIR/index.html" <<'PY' || die "structure HTML déséquilibrée"
import html.parser, sys
VOID = {'meta','link','br','img','hr','use','rect','path','line','circle','text','input',
        'polygon','stop','tspan','ellipse','polyline','source','area','col','wbr','embed'}
class P(html.parser.HTMLParser):
    def __init__(self): super().__init__(); self.stack=[]; self.bad=[]
    def handle_starttag(self, t, a):
        if t not in VOID: self.stack.append(t)
    def handle_endtag(self, t):
        if self.stack and self.stack[-1] == t: self.stack.pop()
        elif t in self.stack: self.bad.append(t)
p = P(); p.feed(open(sys.argv[1]).read())
if p.stack or p.bad:
    print("  non fermées :", p.stack[:5], "· mal imbriquées :", p.bad[:5]); sys.exit(1)
PY
ok "structure HTML équilibrée"

grep -q 'href="#"' "$LOCAL_DIR/index.html" && die "lien href=\"#\" laissé dans la page"
ok "aucun lien de remplacement"

# Garde-fou contre l'envoi d'une page qui décrirait une version périmée : ces deux
# affirmations sont celles de la 1.1.0. À faire évoluer avec le contenu de la page.
for marker in "cinq langues" "Discuter avec le document" "five languages" "Chat with the document"; do
  grep -q "$marker" "$LOCAL_DIR/index.html" || die "la page ne mentionne pas « $marker » — contenu périmé ?"
done
ok "contenu conforme à la version courante"

step "Fichiers à téléverser vers $FTP_HOST:$FTP_REMOTE_DIR"
for f in $FILES; do
  [ -f "$LOCAL_DIR/$f" ] || die "fichier absent : $LOCAL_DIR/$f"
  printf '  %-46s %s\n' "$f" "$(du -h "$LOCAL_DIR/$f" | cut -f1)"
done

if [ "$DRY" = 1 ]; then
  printf '\n\033[1mArrêt avant envoi (--dry-run).\033[0m Rien n%s été téléversé.\n' "'a"
  exit 0
fi

# --- envoi ------------------------------------------------------------------------------
step "Envoi FTP"
for f in $FILES; do
  # -K - : les identifiants arrivent par l'entrée standard, donc hors de `ps`.
  printf 'user = "%s:%s"\n' "$FTP_USER" "$FTP_PASSWORD" \
    | curl --silent --show-error --fail -K - $TLS_OPT --ftp-create-dirs \
           -T "$LOCAL_DIR/$f" "ftp://$FTP_HOST$FTP_REMOTE_DIR/$f" \
    || die "échec du téléversement de $f"
  ok "$f"
done

# --- vérification en ligne ---------------------------------------------------------------
# Téléverser sans relire, c'est supposer. On relit la page publique.
step "Vérification de $PUBLIC_URL"
sleep 2
PAGE="$(curl --silent --show-error --fail --max-time 20 "$PUBLIC_URL")" \
  || die "la page publique est injoignable après l'envoi"

for marker in "cinq langues" "Discuter avec le document" "five languages" "Chat with the document"; do
  printf '%s' "$PAGE" | grep -q "$marker" \
    || die "« $marker » absent de la page en ligne — cache de l'hébergeur ? mauvais FTP_REMOTE_DIR ?"
done
ok "la page en ligne annonce bien les cinq langues et la discussion"

printf '\n\033[32m✓ %s est à jour.\033[0m\n' "$PUBLIC_URL"
