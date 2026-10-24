# Prompt pour lancer la 1.4 dans une nouvelle conversation

À coller tel quel dans une nouvelle conversation Claude Code, ouverte dans
`~/Developer/OK-ia - Markdown Viewer`.

---

```
On lance la version 1.4 de md Viewer : « l'option Analytic — vos documents prennent vie ».

Contexte
- La 1.3 est en vente depuis le 24 octobre 2026 (iOS, iPad, iPhone Duo et Mac, build 87). Elle est
  close : rien de la 1.4 ne doit la toucher rétroactivement.
- Le plan complet est dans README.md, section « 1.4 — l'option Analytic », et la liste des tâches
  dans TACHES-1.4.md. Lis les deux avant toute chose, ainsi que tes mémoires du projet
  (option-analytic-1-4, duo-reel-vs-simulateur, signing-and-release, i18n-and-site).
- L'option est payante : deux produits non consommables de 2 francs (« Analytic » sur iPhone et
  iPad, « Analytic pour Mac » avec l'import Word/PDF/PowerPoint).
- Elle reprend au maximum le code de fornews.ai (~/Developer/fornews.ai) : détection d'entités
  (FornewsCore : NLTagger, FiltreEntitesNER), achat (FornewsAchat), compte à rebours
  (CompteReboursDemandeView), générateur de rapport (GenerateurRapportAnalyste), carte
  (CarteEntitesView). Ne modifie pas fornews.ai depuis cette conversation : signale ce qu'il
  faudrait y changer (cache d'entités dans group.ai.fornews.native, route fornews://entite?qid=…).

Première étape — aucune ligne de code avant mes décisions (TACHES-1.4.md, section ⓪)
Présente-moi, une par une, les décisions à prendre, avec ta recommandation et ses conséquences :
1. Private Cloud Compute : il contredit deux engagements publiés (« pas d'IA distante, pas même
   chez Apple » sur la feuille de route ; « aucun serveur » dans la politique de confidentialité).
   Par défaut : uniquement SystemLanguageModel.default, jamais PCC.
2. Wikidata : requête réseau qui envoie des noms d'entités (jamais le document). Imposée ou
   proposée, et le texte de la politique de confidentialité.
3. Prix : confirmer deux produits à CHF 2.00 et vérifier le palier dans App Store Connect.
4. Slogan FR et EN.
Ensuite, propose un découpage en lots livrables sur TestFlight (achat, entités, galerie et carte,
import Mac), dans l'ordre que tu recommandes.

Règles de travail (les mêmes que pour la 1.3)
- Réponds-moi toujours en français ; commentaires du code en français.
- MARKETING_VERSION passe à 1.4 ; les numéros de build continuent après 87.
- Builds : scripts/deploy-testflight.sh --bump --both --no-upload, puis xcrun altool, puis les
  notes de test avec scripts/asc/notes.py (limite 4000 caractères). Je dis « B<n> et pousse ».
- Ne pousse que sur ma demande. Commits terminés par la ligne Co-Authored-By habituelle.
- Hooks de debug uniquement sous #if DEBUG, ajoutés aux canaris de deploy-testflight.sh.
- Jamais de PrivateCloudCompute sans mon accord explicite ; ne touche pas à BoiteAuxLettres.swift.
- Le site ok-ia.ch se publie par une branche claude/<desc>-<id>, une PR, puis la fusion.
- Rien ne part sur Mastodon sans mon feu vert ; rien ne peut publier sur @patcedar.
- Le Duo : la pliure se lit dans reservedRegions(kind: .division), jamais en divisant l'écran ;
  prévoir un diagnostic copiable dans les builds de test ; vérifier sur le vrai appareil, le
  simulateur ne suffit pas (ni gestes, ni postures, ni orientation).
- Vérifie au simulateur ce qui peut l'être avant de me demander un test, et dis-moi clairement
  ce qui reste à confirmer sur l'appareil.
```
