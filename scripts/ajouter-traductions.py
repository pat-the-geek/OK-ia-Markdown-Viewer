# Ajoute des chaînes au catalogue Localizable.xcstrings sans toucher aux autres : même ordre, même
# mise en forme qu'Xcode (indentation de 2, « clé: valeur »), la clé étant le texte français.
# Usage : python3 scripts/ajouter-traductions.py fichier.json — un objet {"clé fr": [en, de, es, it]}.
import json, collections, sys
CAT = "OKiaMarkdownViewer/Localizable.xcstrings"
nouvelles = json.load(open(sys.argv[1]), object_pairs_hook=collections.OrderedDict)
c = json.load(open(CAT), object_pairs_hook=collections.OrderedDict)
ajout = 0
for cle, (en, de, es, it) in nouvelles.items():
    if cle in c["strings"]:
        continue
    loc = collections.OrderedDict()
    for langue, valeur in (("fr", cle), ("en", en), ("de", de), ("es", es), ("it", it)):
        loc[langue] = {"stringUnit": {"state": "translated", "value": valeur}}
    c["strings"][cle] = collections.OrderedDict([("extractionState", "manual"), ("localizations", loc)])
    ajout += 1
open(CAT, "w").write(json.dumps(c, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n")
print(f"{ajout} chaîne(s) ajoutée(s)")
