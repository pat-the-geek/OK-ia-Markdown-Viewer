# Publication App Store — OK-ia Markdown Viewer

Dossier de préparation à la soumission **App Store** (iOS/iPadOS **et** macOS).
Ces documents sont **prêts à copier-coller** dans App Store Connect. Les choix éditoriaux
(nom, catégorie, prix, URLs…) sont **actés** — voir *Décisions actées* ci-dessous.

## Fichiers

| Fichier | Contenu |
|---|---|
| [`listing-fr.md`](listing-fr.md) | Fiche produit **FR** : nom, sous-titre, description, mots-clés, nouveautés, URLs, catégorie, copyright |
| [`listing-en.md`](listing-en.md) | Fiche produit **EN** — miroir de la FR, à garder synchronisée |
| [`app-privacy.md`](app-privacy.md) | Réponses au questionnaire « App Privacy » |
| [`mdviewer-confidentialite.html`](mdviewer-confidentialite.html) | **Politique de confidentialité finalisée**, à héberger sur `ok-ia.ch/mdviewer/confidentialite.html` |
| [`screenshots.md`](screenshots.md) | Tailles de captures requises (iPhone/iPad/Mac) + plan de capture |
| [`review-notes.md`](review-notes.md) | Notes pour l'équipe App Review (comment tester, contenu de démo, pas de login) |
| [`testflight.md`](testflight.md) | Infos TestFlight : description bêta, « Que tester », notes review externe, feedback |

## Décisions actées

- **Nom** : OK-ia Markdown Viewer · **Catégorie** : Productivité · **Prix** : Gratuit
- **Langues de la fiche** : **français + anglais uniquement** (décidé le 2026-07-27).
  ⚠️ À ne pas confondre avec les langues de l'**app**, qui sont cinq depuis la 1.1.0
  (fr, en, de, es, it). App Store Connect proposera donc d'ajouter de/es/it à la fiche :
  **ne pas les remplir pour l'instant**. Un binaire multilingue avec une fiche FR/EN est
  parfaitement recevable — l'App Store affiche simplement la fiche dans la langue la plus
  proche pour les visiteurs germanophones, hispanophones et italophones.
- **Âge** : 4+ (répondre « Non » à « accès web sans restriction »)
- **URLs** : assistance & marketing `https://ok-ia.ch` · confidentialité `https://ok-ia.ch/mdviewer/confidentialite.html`
- **Copyright** : © 2026 OK-ia

## Portée des plateformes

L'app est **universelle** : `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad) **et** Mac Catalyst.
→ **iOS App Store** (iPhone + iPad) et **Mac App Store** (Catalyst) à partir de la **même fiche app**
(App Store Connect → onglets de plateforme).

## Soumission de la 1.2 — état au 2026-09-16

### Ce qui est prêt côté binaire

- ✅ **Build `1.2 (39)`**, iOS **et** Mac Catalyst, envoyé par `scripts/deploy-testflight.sh --both`.
  Vérifié sur le binaire iOS exporté : `CFBundleVersion 39`, `minos 26.4`, `sdk 26.5`, signature
  de distribution (`get-task-allow` à faux), groupe d'applications `group.ai.fornews.native`
  présent. Contrôles du script passés sur les deux plateformes : aucun harnais de debug, cinq
  langues embarquées.
- ✅ Compilé sous **Xcode 26.6, SDK 26.5**. La machine est passée depuis à **Xcode 27.0** : le 39
  ne se reconstruit plus à l'identique, et tout build suivant changera de chaîne de compilation —
  voir la feuille de route du README.
- ✅ Icône 1024×1024 sans canal alpha. Conformité export : `ITSAppUsesNonExemptEncryption = false`.
- ⚠️ **Cible minimale relevée à 26.4** (iOS, iPadOS, macOS). Les appareils plus anciens gardent la
  1.1.1. Choix irréversible une fois la 1.2 en vente.

### Ce qui est prêt côté fiche

- ✅ Notes de version 1.2, FR et EN, dans les limites d'App Store Connect (mesurées le 2026-09-16 :
  description 2 535 et 2 322 car. sur 4 000, notes 1 098 et 972 sur 4 000, texte promotionnel 160
  et 149 sur 170, mots-clés 96 et 95 sur 100).
- ✅ [`review-notes.md`](review-notes.md) récrit pour la 1.2, **version anglaise à coller** : comment
  éprouver la traduction sur le document d'exemple, et pourquoi l'app déclare un groupe
  d'applications au nom de fornews.ai.
- ✅ [`app-privacy.md`](app-privacy.md) : la réponse « Données non collectées » tient, justifiée pour
  la traduction et le dossier partagé.
- ⏳ **Politique de confidentialité mise à jour, pas encore publiée.** La page en ligne date du
  17 juin et ne dit rien de la traduction ni du dossier partagé. La correction attend sur une
  branche locale du dépôt du site (`claude/confidentialite-1-2-d455b15c`) : **à publier avant
  « Submit for Review »**, puisque l'examinateur la compare à l'app.
- ➖ **Captures d'écran inchangées** (4 septembre). Elles restent fidèles à l'app ; elles ne montrent
  ni la traduction — le simulateur iOS ne traduit pas — ni la colonne de lecture élargie du build
  38, sensible surtout sur Mac et iPad. Apple ne l'exige pas.
- ⏳ **Page produit ok-ia.ch** : décidé le 2026-09-08, elle se publie **au moment de la mise en
  vente**, pas à la soumission. Ses modifications attendent dans `site/mdviewer/index.html`.

## Ce que je ne peux pas faire à ta place

La **soumission** et tout ce qui touche à App Store Connect se fait avec **ta session Apple** :
créer la version, coller les textes, rattacher le build, répondre aux questionnaires, cliquer
**« Submit for Review »**. Les documents de ce dossier donnent exactement quoi saisir.

## Ordre conseillé pour la 1.2

1. Publier la politique de confidentialité mise à jour (merge de la branche du site).
2. App Store Connect → **+ Version** `1.2`, sur **iOS** puis sur **macOS**.
3. Coller, FR et EN, les **nouveautés** 1.2 **et la description**, qui a gagné ses lignes sur la
   traduction depuis la 1.1.1 — `listing-fr.md`, `listing-en.md`. Le texte promotionnel, lui, se
   change à tout moment sans revue.
4. Rattacher le build **`1.2 (39)`** sur chaque plateforme.
5. **App Privacy** : rien à changer, « Données non collectées » — vérifier seulement que la réponse
   n'a pas été remise à zéro.
6. **App Review Information** : coller la version **anglaise** de `review-notes.md`, cocher
   « Sign-in not required ».
7. **Submit for Review**.
8. À l'acceptation : mise en vente, puis page produit ok-ia.ch et badge « livrée » sur la feuille de
   route publique.
