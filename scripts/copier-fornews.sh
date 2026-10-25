#!/bin/zsh
# Recopie dans OKiaMarkdownViewer/Fornews/ le code de fornews.ai que l'option Analytic (1.4)
# reprend : la détection d'entités et la résolution Wikidata. Copie MOT POUR MOT, comme
# `BoiteAuxLettres.swift` — décision de Patrick du 25/10/2026, plutôt qu'une dépendance au dépôt
# fornews. On ne corrige jamais ces fichiers ici : on corrige fornews, puis on relance ce script.
#
# Seules retouches, faites par le script et annoncées en tête de chaque fichier :
#  - les `import Fornews…` et `import SwiftData` retirés (tout vit dans le même module) ;
#  - trois fichiers EXTRAITS au lieu d'être copiés entiers, parce que le reste du fichier tient au
#    modèle SwiftData de fornews (`EntiteNER`, `ModelContext`) : `TypeEntite` (Enums.swift),
#    `QualiteEntites.motifFicheSansContenu` et `WikimediaService` sans ses fonctions d'écriture.
#  - `GardeFousIA` appelle `RelanceGarantie` (fornews quitte pour être relancé par launchd, en mode
#    serveur) : md Viewer en a son propre `RelanceGarantie`, qui ne relance jamais (Models/Analytic).
#
# Usage : scripts/copier-fornews.sh [chemin de fornews.ai]   (défaut : ~/Developer/fornews.ai)
set -euo pipefail
ICI=${0:A:h}/..
FORNEWS=${1:-$HOME/Developer/fornews.ai}
SRC=$FORNEWS/FornewsCore/Sources
DEST=$ICI/OKiaMarkdownViewer/Fornews
COMMIT=$(git -C "$FORNEWS" log -1 --format='%h, %ad' --date=format:'%d/%m/%Y')
mkdir -p "$DEST"
rm -f "$DEST"/*.swift(N)

python3 - "$SRC" "$DEST" "$COMMIT" <<'EOF'
import re, sys
src, dest, commit = sys.argv[1:4]

ENTIERS = [
    "FornewsAI/FiltreEntitesNER.swift",
    "FornewsModels/TermesGeneriquesNER.swift",
    "FornewsModels/ControlesEntites.swift",
    "FornewsModels/FormeDuNom.swift",
    "FornewsModels/LibellePromotionnel.swift",
    "FornewsModels/LibelleTronque.swift",
    "FornewsModels/NomDeCodeTech.swift",
    "FornewsModels/PaireDePays.swift",
    "FornewsModels/PatronymeLieu.swift",
    "FornewsModels/SyntagmePositionnel.swift",
    "FornewsFeatures/Components/TypeEntiteUI.swift",
    "FornewsServices/Wikimedia/URLSessionWikimediaClient.swift",
    "FornewsServices/Carte/CoordonneeTerrestre.swift",
    "FornewsServices/Flux/KeywordMatcher.swift",
    "FornewsModels/ExpressionMotsCles.swift",
    "FornewsAI/Protocols/AIProtocols.swift",
    "FornewsAI/Apple/NERFoundationModels.swift",
    "FornewsAI/Apple/GardeFousIA.swift",
    "FornewsAI/Apple/DisponibiliteAppleIntelligence.swift",
    "FornewsAI/BudgetContexteLLM.swift",
]

def entete(chemin, note):
    return ("// ─────────────────────────────────────────────────────────────────────────────────────────────\n"
            f"// Copie de fornews.ai — FornewsCore/Sources/{chemin} (commit {commit}).\n"
            "// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans\n"
            "// fornews, puis relancer scripts/copier-fornews.sh.\n"
            f"// {note}\n"
            "// ─────────────────────────────────────────────────────────────────────────────────────────────\n\n")

def nettoyer(texte):
    return "\n".join(l for l in texte.split("\n")
                     if not re.match(r"^import (Fornews\w*|SwiftData)\s*$", l))

def retirer(texte, motifs):
    """Retire les déclarations dont l'en-tête correspond à un motif, avec leur doc au-dessus."""
    L = texte.split("\n"); out = []; i = 0
    while i < len(L):
        if any(re.search(m, L[i]) for m in motifs):
            while out and (out[-1].strip().startswith("///") or out[-1].strip().startswith("@")):
                out.pop()
            prof = 0; vu = False
            while i < len(L):
                prof += L[i].count("{") - L[i].count("}")
                vu = vu or "{" in L[i]
                i += 1
                if vu and prof <= 0: break
            continue
        out.append(L[i]); i += 1
    return "\n".join(out)

def extrait(texte, debut, fin):
    a = texte.index(debut); b = texte.index(fin)
    avant = texte[:a]; d = avant.rfind("\n\n")       # garder le commentaire de doc au-dessus
    return "import Foundation\n" + texte[d:b].rstrip() + "\n"

for chemin in ENTIERS:
    t = nettoyer(open(f"{src}/{chemin}").read())
    nom = chemin.split("/")[-1]
    open(f"{dest}/{nom}", "w").write(entete(chemin, "Seule retouche : les `import Fornews…` retirés.") + t)

t = open(f"{src}/FornewsModels/Enums.swift").read()
open(f"{dest}/TypeEntite.swift", "w").write(
    entete("FornewsModels/Enums.swift", "EXTRAIT : `TypeEntite` seul (le reste du fichier tient au modèle SwiftData).")
    + extrait(t, "public enum TypeEntite", "public extension Sequence where Element == EntiteNER"))

t = open(f"{src}/FornewsServices/Purge/QualiteEntites.swift").read()
a = t.index("    /// Motifs de description trahissant une fiche sans contenu")
b = t.index("public static func motifFicheSansContenu")
b = t.index("\n    }\n", b) + len("\n    }\n")
open(f"{dest}/QualiteEntites.swift", "w").write(
    entete("FornewsServices/Purge/QualiteEntites.swift",
           "EXTRAIT : `motifFicheSansContenu` seul, dont `WikimediaService.choisir` a besoin (le reste lit le\n"
           "// modèle SwiftData).") + "import Foundation\n\npublic enum QualiteEntites {\n" + t[a:b] + "}\n")

t = nettoyer(open(f"{src}/FornewsServices/Wikimedia/WikimediaService.swift").read())
t = retirer(t, [r"public enum TemoinExecuteurEnrichissement", r"public func enrichir\(",
                r"private func enrichirInterne\(", r"public func appliquerCandidat\(",
                r"public func geolocaliser\(", r"static func fusionnerSiDoublon\(",
                r"private func coordonneesSiLeQIDDesigneVraiment\("])
open(f"{dest}/WikimediaService.swift", "w").write(
    entete("FornewsServices/Wikimedia/WikimediaService.swift",
           "EXTRAIT : sans les fonctions qui écrivent dans le modèle SwiftData (enrichir, appliquerCandidat,\n"
           "// geolocaliser, fusionnerSiDoublon) ; restent le protocole du client et les règles de choix.") + t)
EOF
ls "$DEST"
