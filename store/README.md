# Publication App Store — OK-ia Markdown Viewer

Dossier de préparation à la soumission **App Store** (iOS/iPadOS **et** macOS).
Ces documents sont des **brouillons prêts à copier-coller** dans App Store Connect.
Tout ce qui demande une décision de ta part est marqué **⚠️ À DÉCIDER**.

## Fichiers

| Fichier | Contenu |
|---|---|
| [`listing-fr.md`](listing-fr.md) | Fiche produit : nom, sous-titre, description, mots-clés, nouveautés, URLs, catégorie, copyright |
| [`app-privacy.md`](app-privacy.md) | Réponses au questionnaire « App Privacy » + brouillon de politique de confidentialité à héberger |
| [`screenshots.md`](screenshots.md) | Tailles de captures requises (iPhone/iPad/Mac) + plan de capture |
| [`review-notes.md`](review-notes.md) | Notes pour l'équipe App Review (comment tester, contenu de démo, pas de login) |

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

1. Décider les points **⚠️ À DÉCIDER** (nom, catégorie, prix, URLs).
2. Héberger la **politique de confidentialité** (URL requise) — voir `app-privacy.md`.
3. Capturer les **screenshots** (iPhone, iPad, Mac) — voir `screenshots.md`.
4. Remplir la fiche dans App Store Connect — voir `listing-fr.md`.
5. Renseigner **App Privacy** — voir `app-privacy.md`.
6. Rattacher le build (iOS : `1.0.0 (3)` ; macOS : archiver le Catalyst → voir `review-notes.md`).
7. Ajouter les **notes pour la review**, puis **Submit for Review**.
