# Banc d'essai du framework `Translation`

Une petite app à part, hors de la cible livrée, qui interroge le framework `Translation`
d'Apple et écrit ce qu'elle trouve. Elle a servi à trancher la version 1.2 (traduction
automatique des documents) avant d'écrire une ligne dans le lecteur, et elle sert à
revérifier à chaque changement de SDK — les réponses ci-dessous datent du 2026-09-07,
Xcode 26.6, macOS 26.6.2, et rien ne garantit qu'elles tiennent au suivant.

## Lancer

    xcodegen generate
    xcodebuild -project TranslationBench.xcodeproj -scheme TranslationBench \
      -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build build
    BENCH_OUT=/tmp/banc.txt ./build/Build/Products/Debug-maccatalyst/TranslationBench.app/Contents/MacOS/TranslationBench

Sur simulateur (`-destination 'platform=iOS Simulator,name=…'`, puis `simctl install` et
`simctl launch`), passer les variables par `SIMCTL_CHILD_`.

Le journal s'écrit à la fois sur la sortie standard et dans `BENCH_OUT`, ligne par ligne :
une app lancée par `open -a` n'a pas de terminal, et une épreuve qui bloque ne doit pas
emporter le journal avec elle.

| Variable | Effet |
|---|---|
| `BENCH_OUT` | où écrire le journal (défaut `/tmp/banc-translation.txt`) |
| `BENCH_SANS_PREPARE` | saute l'épreuve 2 — indispensable sur simulateur, voir plus bas |
| `BENCH_DEBIT` | taille du document de l'épreuve 6, en caractères (défaut 40 000) |

## Les huit épreuves, et ce qu'elles ont répondu

1. **Couverture** — 38 langues annoncées, les cinq de l'app comprises, vingt paires
   utilisables. Attention : `supportedLanguages` renvoie ces 38 langues **même sur
   simulateur**, où plus rien ne traduit. C'est `status(from:to:)` qui fait foi, et il
   répond en 30 ms.
2. **Invite de téléchargement** — invérifiable sur une machine où tout est déjà installé
   (`isReady` vrai, `prepareTranslation()` en 0,01 s). Sur simulateur,
   `prepareTranslation()` **ne rend jamais la main** : ni invite, ni erreur, ni délai. Ne
   jamais l'appeler sans garde-fou.
3. **Diffusion** — `translate(batch:)` rend une `AsyncSequence` qui diffuse réellement au
   fil de l'eau, dans l'ordre des requêtes. Mais il n'accélère rien : 9,3 s pour douze
   blocs, contre 8,2 s pour `translations(from:)` et 8,4 s pour douze `translate()` en
   série. Il traduit en série et se contente de rendre les résultats au fur et à mesure.
4. **Syntaxe Markdown** — traduire la chaîne brute est exclu. Le gras, l'italique et les
   URL de liens survivent ; la cible d'un `[[wiki-lien]]`, le code inline entre accents
   graves, la casse de `flowchart TD`, l'indentation et les clés du frontmatter, non.
5. **`skipsTranslation`** — l'attribut d'`AttributedString` (SDK 26.4) protège une plage,
   et la réponse rend les segments avec leurs attributs. C'est la parade au point 4.
6. **Débit** — ≈ 171 caractères/seconde, linéaire : 40 141 caractères en 234 s.
7. **Les vingt paires** — toutes traduisent, 0,3 à 0,9 s la phrase.
8. **Langue non installée** — témoin destiné à faire tomber l'invite ; sans effet sur une
   machine où les 38 langues sont là.

## Deux pièges d'écriture du banc lui-même

- **Deux configurations de même paire sont égales**, et `translationTask` ne se relance que
  si la valeur change : sans `invalidate()`, la deuxième session `fr→de` n'arrive jamais et
  le banc reste suspendu. La version doit être strictement croissante, d'où le compteur.
- **Les minuteries sont des courses, pas des avertissements.** Une épreuve qui ne rend pas
  la main — c'est le cas de `prepareTranslation()` sur simulateur — doit être abandonnée,
  sa continuation libérée, et la suite exécutée quand même.
