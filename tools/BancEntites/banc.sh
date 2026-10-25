#!/bin/zsh
# Compile et lance le banc des entités sur les documents donnés. Voir main.swift.
# CHERCHE=trump,musk (défaut) : les noms dont on suit le parcours ; TOUT=1 : toute la liste.
set -euo pipefail
ICI=${0:A:h}
APP=$ICI/../../OKiaMarkdownViewer
SORTIE=${TMPDIR:-/tmp}/banc-entites
xcrun swiftc -O -o "$SORTIE" "$APP"/Fornews/*.swift "$APP"/Models/Analytic/EntitesDocument.swift "$APP"/Models/Analytic/RelanceGarantie.swift "$ICI/main.swift"
"$SORTIE" "$@"
