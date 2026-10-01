# Banc d'essai — convertir un rapport en présentation

Avant d'écrire la conversion dans l'app (1.3), ce banc répond par l'expérience aux questions
qui décident de son architecture. Il emploie **uniquement le modèle de l'appareil**
(`SystemLanguageModel.default`) ; le SDK 27 expose aussi `PrivateCloudComputeLanguageModel`,
exécuté sur les serveurs d'Apple, qui contredirait la promesse de l'app.

```bash
swiftc -O OKiaMarkdownViewer/Models/PresentationConverter.swift tools/ConversionBench/main.swift \
       -o build/conversion-bench
build/conversion-bench <rapport.md> <nombre de diapositives> [sortie.md]
```

**Depuis le 2026-10-01, le banc compile le moteur de l'app** (`PresentationConverter.swift`) au
lieu d'en porter une copie : ce qu'il mesure est ce que l'app livre.

## Ce qu'il fait

1. Découpe le rapport en sections `##`, met à part le **chapeau** (ce qui précède la première
   section), les **blocs visuels** (`mermaid`, `leaflet`, tableaux) et les **métadonnées**
   (séparateurs `---`, lignes « **Clé** — … », statistiques du corpus).
2. Répartit le nombre de diapositives demandé : les fixes d'abord (titre, plan dès 8, « À
   retenir », sources dès 10), puis le reste au prorata du poids des sections. Une carte n'est
   jamais sacrifiée.
3. Fait générer chaque section avec un **schéma dynamique** qui impose le nombre exact de
   diapositives (`minimumElements = maximumElements`) et 1 à 5 puces par diapositive.
4. Reprend **tels quels** les diagrammes et la carte : le modèle n'écrit jamais de coordonnées.
5. Vérifie chaque nombre des puces contre le texte d'origine de la section.

## Ce qu'il a établi — le 2026-10-01, Mac sous macOS 27.0.1

| Mesure | Résultat |
|---|---|
| Fenêtre de contexte | **8 192 jetons** (le double de la génération 26). La plus grosse section d'un rapport réel, 13 600 caractères, y tient sans troncature. |
| Nombre de diapositives | **Toujours exact** : 5/5, 6/6, 10/10, 20/20. Le schéma le garantit, la consigne seule ne le ferait pas. |
| Durée, rapport réel de 37 000 caractères | 5 diapositives : **12 s** · 10 : **25 s** · 20 : **42 à 50 s** |
| Chiffres | **0 nombre inventé** sur 20 à 65 puces, une fois la consigne « recopie les nombres tels qu'ils sont écrits » ajoutée. |
| Langue | Française, allemande, italienne : tenue, une fois la langue détectée et rappelée en dernière ligne. |

## Ce que les essais ont corrigé — et que l'app devra reprendre

- **Le chapeau n'appartient pas à la première section.** Fusionné avec elle, il remplissait la
  synthèse de statistiques (« 33 articles, 17 sources »). Il sert en revanche à la phrase
  d'ouverture : c'est le résumé de l'auteur.
- **Un `---` recopié crée une diapositive de plus.** Toute prose reprise du rapport doit en être
  purgée.
- **Toute réponse passe par un schéma.** La seule demande libre — la phrase d'ouverture — est
  revenue en liste de puces.
- **« À retenir » se nourrit du contenu des diapositives**, pas de leurs titres, sinon il répète
  les titres.
- **Les nombres en lettres.** « Plus de treize cents » devenait « 1300 » : valeur juste, nuance
  perdue, et signalé par la vérification. Consigne : recopier tel quel, en lettres et avec
  « plus de ».
- **La langue se détecte sur la prose seule, parmi les cinq de l'app.** Sur le fichier brut, un
  rapport allemand était pris pour du portugais, et les consignes françaises l'emportaient sur les
  sections presque vides.
- **Une phrase se coupe avec le tokenizer de sa langue**, pas au premier point : « vor dem
  30. Juni » s'arrêtait à « 30. ».
- **Une puce se suffit à elle-même.** Sans cette consigne, le modèle découpait une phrase en
  plusieurs puces pour tenir la limite de mots.
- **Les liens wiki se réparent.** Le modèle a rendu `[[Liebefeld]` : il faut refermer ou retirer
  les crochets orphelins avant d'afficher.
