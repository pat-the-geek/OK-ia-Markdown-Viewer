#!/bin/zsh
# Compile et lance le banc de l'import PDF : banc.sh document.pdf [sortie.md]
set -euo pipefail
ICI=${0:A:h}
APP=$ICI/../../OKiaMarkdownViewer
SORTIE=${TMPDIR:-/tmp}/banc-pdf
SDK=$(xcrun --show-sdk-path --sdk macosx)
xcrun swiftc -O -target arm64-apple-ios26.4-macabi -sdk "$SDK" \
  -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" \
  -o "$SORTIE" "$APP"/Models/Import/ImportPDF.swift "$APP"/Models/Import/ImportCommun.swift "$APP"/Models/Import/LecteurZip.swift "$APP"/Models/Import/NoeudXML.swift "$ICI"/Doublures.swift "$ICI/main.swift"
"$SORTIE" "$@"
