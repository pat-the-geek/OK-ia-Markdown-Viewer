#!/bin/zsh
# Compile et lance le banc des partages chiffrés d'ok-ia.ch. Voir main.swift.
set -euo pipefail
ICI=${0:A:h}
APP=$ICI/../../OKiaMarkdownViewer
SORTIE=${TMPDIR:-/tmp}/banc-partage
xcrun swiftc -O -o "$SORTIE" "$APP"/Models/PartageOKia.swift "$ICI/main.swift" 2>&1 | grep -v "^$" || true
[ -x "$SORTIE" ] && "$SORTIE" "$ICI"
