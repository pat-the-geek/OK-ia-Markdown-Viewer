# Ajoute des chaînes au catalogue Localizable.xcstrings sans toucher aux autres : même ordre, même
# mise en forme qu'Xcode (indentation de 2, « clé: valeur »), la clé étant le texte français.
# Usage : python3 scripts/ajouter-traductions.py fichier.json — un objet {"clé fr": traductions}, où
# traductions est soit {"en": …, "de": …, "ja": …, …}, soit l'ancienne liste [en, de, es, it].
# Depuis la 1.4 (27/10/2026), l'app parle quinze langues : le script signale celles qui manquent
# (elles liraient l'anglais, voir `tr` dans Localization.swift).
import json, collections, sys
CAT = "OKiaMarkdownViewer/Localizable.xcstrings"
LANGUES = ["en", "de", "es", "it", "ja", "ko", "zh-Hans", "pt-BR", "nl", "ru", "uk", "tr", "vi", "hi"]
nouvelles = json.load(open(sys.argv[1]), object_pairs_hook=collections.OrderedDict)
c = json.load(open(CAT), object_pairs_hook=collections.OrderedDict)
ajout = 0
manquantes = collections.Counter()
for cle, trad in nouvelles.items():
    if cle in c["strings"]:
        continue
    if isinstance(trad, list):
        trad = dict(zip(["en", "de", "es", "it"], trad))
    loc = collections.OrderedDict([("fr", {"stringUnit": {"state": "translated", "value": cle}})])
    for langue in LANGUES:
        if langue in trad:
            loc[langue] = {"stringUnit": {"state": "translated", "value": trad[langue]}}
        else:
            manquantes[langue] += 1
    c["strings"][cle] = collections.OrderedDict([("extractionState", "manual"), ("localizations", loc)])
    ajout += 1
open(CAT, "w").write(json.dumps(c, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n")
print(f"{ajout} chaîne(s) ajoutée(s)")
if manquantes:
    print("⚠️ traductions manquantes :", ", ".join(f"{l} ({n})" for l, n in manquantes.items()))
