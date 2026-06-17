# Publication App Store — OK-ia Markdown Viewer

Dossier de préparation à la soumission **App Store** (iOS/iPadOS **et** macOS).
Ces documents sont **prêts à copier-coller** dans App Store Connect. Les choix éditoriaux
(nom, catégorie, prix, URLs…) sont **actés** — voir *Décisions actées* ci-dessous.

## Fichiers

| Fichier | Contenu |
|---|---|
| [`listing-fr.md`](listing-fr.md) | Fiche produit : nom, sous-titre, description, mots-clés, nouveautés, URLs, catégorie, copyright |
| [`app-privacy.md`](app-privacy.md) | Réponses au questionnaire « App Privacy » |
| [`confidentialite.html`](confidentialite.html) | **Politique de confidentialité finalisée**, à héberger sur `ok-ia.ch/confidentialite` |
| [`screenshots.md`](screenshots.md) | Tailles de captures requises (iPhone/iPad/Mac) + plan de capture |
| [`review-notes.md`](review-notes.md) | Notes pour l'équipe App Review (comment tester, contenu de démo, pas de login) |

## Décisions actées

- **Nom** : OK-ia Markdown Viewer · **Catégorie** : Productivité · **Prix** : Gratuit
- **Âge** : 4+ (répondre « Non » à « accès web sans restriction »)
- **URLs** : assistance & marketing `https://ok-ia.ch` · confidentialité `https://ok-ia.ch/confidentialite`
- **Copyright** : © 2026 OK-ia

## Portée des plateformes

L'app est **universelle** : `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad) **et** Mac Catalyst.
→ **iOS App Store** (iPhone + iPad) et **Mac App Store** (Catalyst) à partir de la **même fiche app**
(App Store Connect → onglets de plateforme).

## Ce qui est déjà prêt (côté binaire)

- ✅ Icône 1024×1024 sans canal alpha (conforme).
- ✅ Conformité export : `ITSAppUsesNonExemptEncryption = false` (pas de questionnaire crypto).
- ✅ Signature : équipe payante `72NVM63N83`, signature automatique.
- ✅ Build `1.0.0 (3)` archivé (déjà sur TestFlight côté iOS).

## Ce que je ne peux pas faire à ta place

La **soumission** et tout ce qui touche à App Store Connect se fait avec **ta session Apple** :
créer/compléter la fiche, téléverser les captures, répondre au questionnaire de confidentialité,
choisir le prix, et cliquer **« Submit for Review »**. Les documents ci-dessous te donnent
exactement quoi saisir.

## Ordre conseillé

1. ~~Décider les points (nom, catégorie, prix, URLs)~~ ✅ fait — voir *Décisions actées*.
2. Héberger [`confidentialite.html`](confidentialite.html) sur `ok-ia.ch/confidentialite` (URL requise).
3. Capturer les **screenshots** (iPhone, iPad, Mac) — voir `screenshots.md`.
4. Remplir la fiche dans App Store Connect — voir `listing-fr.md`.
5. Renseigner **App Privacy** — voir `app-privacy.md`.
6. Rattacher le build (iOS : `1.0.0 (3)` ; macOS : archiver le Catalyst → voir `review-notes.md`).
7. Ajouter les **notes pour la review**, puis **Submit for Review**.
