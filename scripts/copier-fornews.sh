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
    # Le rapport d'analyse d'un document importé (1.4) : les consignes de fornews, section par section.
    "FornewsPipeline/ConsignesAnalyste.swift",
    "FornewsPipeline/ConsignesLocales.swift",
    # La fiche de lecture d'une page web (1.4, Safari → md Viewer) : la fiche d'article de fornews et ses gardes.
    "FornewsFeatures/Explorer/FicheArticle.swift",
    "FornewsAI/VerificateurAncrage.swift",
    "FornewsModels/AncrageLitteral.swift",
    "FornewsModels/DrapeauPays.swift",
    "FornewsAI/Apple/MoteurFM.swift",
    "FornewsFeatures/Components/LangueHelper.swift",
    "FornewsServices/Flux/CarteLeaflet.swift",
    "FornewsServices/Flux/ImageMarkdown.swift",
    "FornewsFeatures/Components/CleImage.swift",
    "FornewsModels/AvertissementIA.swift",
    # Le cache des entités que fornews a résolues par Wikidata, publié dans l'App Group (fornews 1.7.4).
    "FornewsModels/CacheEntitesFornews.swift",
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
                     if not re.match(r"^import (Fornews\w*|SwiftData)\s*(//.*)?$", l))

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

t = open(f"{src}/FornewsPipeline/GenerateurRapportAnalyste.swift").read()
a = t.index("    // MARK: - Les tics de langage")
b = t.index("    /// **Part d'un texte qui est en fait une RECOPIE d'un extrait.**")
# Les contrôles de nombres et d'années inventés, sans ce qui dépend de la chronologie d'articles.
c = t.index("    /// **Les nombres en lettres**")
d = t.index("    public static func estRecopie(")
e = t.index("    /// **Les années que le texte cite et que la matière ne contient pas.**")
f = t.index("    /// **Retire d'une section ce que les sections PRÉCÉDENTES ont déjà dit.**")
open(f"{dest}/NettoyageRapport.swift", "w").write(
    entete("FornewsPipeline/GenerateurRapportAnalyste.swift",
           "EXTRAIT : le nettoyage de la prose (tics d'ouverture, marques recopiées, redites) et les contrôles\n"
           "// des nombres et des années inventés, pour ce qu'md Viewer rédige à l'import ; le reste du\n"
           "// générateur tient au pipeline d'articles.")
    + "import Foundation\n\nenum NettoyageRapport {\n" + t[a:b].rstrip() + "\n\n" + t[c:d].rstrip()
    + "\n\n" + t[e:f].rstrip() + "\n}\n")

def horsChaines(ligne, longue):
    """La ligne sans ses chaînes ni son commentaire de fin, pour compter les accolades : les
    expressions régulières de fornews en sont pleines (`\\[[^\\]]*`). `longue` : dans une chaîne
    sur plusieurs lignes (« \"\"\" »), à l'entrée et à la sortie."""
    out = []; i = 0; n = len(ligne)
    while i < n:
        if longue:
            j = ligne.find('"""', i)
            if j < 0: return "".join(out), True
            longue = False; i = j + 3; continue
        if ligne.startswith('"""', i): longue = True; i += 3; continue
        if ligne.startswith("//", i): break
        if ligne[i] == '"':
            i += 1
            while i < n and ligne[i] != '"': i += 2 if ligne[i] == "\\" else 1
            i += 1; continue
        out.append(ligne[i]); i += 1
    return "".join(out), longue

def declarations(texte, motifs):
    """Les déclarations dont la première ligne correspond à un motif, avec leur doc au-dessus.
    Une déclaration s'arrête quand ses accolades, crochets et parenthèses se referment."""
    L = texte.split("\n"); out = []; i = 0
    while i < len(L):
        if any(re.search(m, L[i]) for m in motifs):
            j = i
            while j > 0 and (L[j-1].strip().startswith("///") or L[j-1].strip().startswith("@")): j -= 1
            prof = 0; k = i; longue = False
            while k < len(L):
                code, longue = horsChaines(L[k], longue)
                prof += sum(code.count(c) for c in "{[(") - sum(code.count(c) for c in "}])")
                k += 1
                if prof <= 0 and not longue: break
            out.append("\n".join(L[j:k])); i = k; continue
        i += 1
    return "\n\n".join(out)

t = nettoyer(open(f"{src}/FornewsFeatures/Explorer/RapportObsidian.swift").read())
open(f"{dest}/RapportObsidian.swift", "w").write(
    entete("FornewsFeatures/Explorer/RapportObsidian.swift",
           "EXTRAIT : la composition du rapport d'un article à partir de ses données (`generer(donnees:)`), avec\n"
           "// ses aides et ses libellés ; le reste du fichier lit le modèle SwiftData de fornews.")
    + "import Foundation\n\nenum RapportObsidian {\n" + declarations(t, [
        r"struct EntiteRapport\b", r"struct GeoPoint\b", r"struct DonneesRapport\b",
        r"static func generer\(donnees", r"static func retirerTitreEnTete\(", r"static func blocLeaflet\(",
        r"static func nomsUniques\(", r"static func flowchartDeterministe\(", r"static func couleurClasse\(",
        r"static func nettoyerNoeud\(", r"static func echapYAML\(", r"static func echapMD\(",
        r"static func slugTag\(", r"struct Labels\b", r"static func labels\(",
        r"static func validerDiagrammeIA\(", r"static func flowchartPropre\(", r"static func mindmapPropre\(", r"static func libelleNoeud\("]) + "\n}\n")

# Le schéma d'un article écrit par le modèle (la fiche de lecture d'une page web) : une méthode de la
# vue de partage de fornews, sortie dans une énumération — seule retouche, `private func` devient
# `static func`.
t = nettoyer(open(f"{src}/FornewsFeatures/Explorer/PartageArticleIAView.swift").read())
d = declarations(t, [r"private func genererDiagramme\("])
assert d, "genererDiagramme introuvable dans PartageArticleIAView"
open(f"{dest}/DiagrammeArticle.swift", "w").write(
    entete("FornewsFeatures/Explorer/PartageArticleIAView.swift",
           "EXTRAIT : `genererDiagramme` seul, le schéma Mermaid d'un article écrit par le modèle de l'appareil ;\n"
           "// sorti de la vue dans une énumération (`private func` → `static func`).")
    + "import Foundation\n#if canImport(FoundationModels)\nimport FoundationModels\n#endif\n\nenum DiagrammeArticle {\n"
    + d.replace("private func genererDiagramme(", "static func genererDiagramme(", 1) + "\n}\n")

t = nettoyer(open(f"{src}/FornewsModels/Article.swift").read())
open(f"{dest}/Mesure.swift", "w").write(
    entete("FornewsModels/Article.swift",
           "EXTRAIT : `Mesure` seule (une grandeur chiffrée), dont `AncrageLitteral` a besoin ; le reste est\n"
           "// le modèle SwiftData des articles.")
    + "import Foundation\n\n" + declarations(t, [r"public struct Mesure:"]) + "\n")

t = nettoyer(open(f"{src}/FornewsPipeline/RevuePresse.swift").read())
open(f"{dest}/RevuePresse.swift", "w").write(
    entete("FornewsPipeline/RevuePresse.swift",
           "EXTRAIT : la pastille d'un média et la reconnaissance des signatures, pour la fiche de lecture.")
    + "import Foundation\n\nenum RevuePresse {\n" + declarations(t, [
        r"static func estLigneDeSignature\(", r"static func estSignatureDAuteur\(", r"static let palette\b",
        r"static func teinte\(", r"static func initiales\(", r"static func pastille\(", r"static func html\("]) + "\n}\n")
EOF
ls "$DEST"
