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
- ✅ **Politique de confidentialité publiée le 2026-09-16** (pat-the-geek/OK-ia#265) : traduction sur
  l'appareil, dictionnaire téléchargé par le système, dossier partagé avec fornews.ai. Vérifiée en
  ligne après le déploiement.
- ➖ **Captures d'écran inchangées** (4 septembre). Elles restent fidèles à l'app ; elles ne montrent
  ni la traduction — le simulateur iOS ne traduit pas — ni la colonne de lecture élargie du build
  38, sensible surtout sur Mac et iPad. Apple ne l'exige pas.
- ✅ **Page produit ok-ia.ch** publiée le 2026-09-18, une fois les deux plateformes en vente.

### Ce qui est déjà saisi dans App Store Connect (par l'API, le 2026-09-16)

- ✅ Version **1.2** créée sur **iOS** et sur **macOS**, état « Prepare for Submission », sortie
  **automatique après approbation** comme les versions précédentes, build **39** rattaché à chacune.
- ✅ Fiches **fr-FR** et **en-US** des deux plateformes : description, nouveautés et texte
  promotionnel écrits depuis `listing-fr.md` et `listing-en.md`, **lignes dépliées** — les fichiers
  sont repliés à 80 colonnes pour la relecture, l'App Store affiche chaque saut de ligne. Mots-clés
  inchangés, identiques à ceux en ligne.
- ✅ Notes pour l'examinateur : version **anglaise** de `review-notes.md` sur les deux versions ;
  coordonnées de contact reprises de la 1.1.1, pas de compte de démonstration.
- ✅ Contrôlé sans rien modifier : captures reprises de la 1.1.1 (iPhone 6,7″ ×5, iPad 12,9″ ×5,
  Mac ×6, en français et en anglais), copyright `© 2026 OK-ia`, URL de confidentialité renseignée.
- ✅ **Soumise en revue le 2026-09-16 à 15 h 57 UTC**, sur accord explicite de Patrick.
- ✅ **iOS approuvée le 2026-09-17, en vente depuis 16 h 33 UTC**, sortie automatique.
- ✅ **macOS approuvée ensuite**, en vente le 2026-09-18 au matin.
- ✅ Page produit et feuille de route publique **publiées le 2026-09-18** (pat-the-geek/OK-ia#273).

L'API s'utilise avec la clé de `scripts/deploy.env` (rôle App Manager, suffisant pour les métadonnées
et la soumission). Le jeton JWT ES256 se signe sans dépendance, avec CryptoKit.

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
