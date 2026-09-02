# TestFlight — informations de test

À coller dans **App Store Connect → TestFlight**. Deux niveaux :
- **Test Information** (par app, partagé) — description bêta, e-mail de feedback, URLs.
- **What to Test** (par build) — ce que les testeurs doivent essayer.
- **Beta App Review Information** — requis seulement pour les **testeurs externes** (revue légère).

> ⚠️ **Build à utiliser : `1.0.0 (18)`** — inclut le résumé Apple Intelligence, les App Intents et
> le correctif Gantt. `CURRENT_PROJECT_VERSION` est déjà à 18 et le projet régénéré : Xcode →
> Archive (scheme « md Viewer », Any iOS Device) → Organizer → Distribute/Upload.

---

## Test Information (App-level)

- **Beta App Description**
```
md Viewer (OK-ia Markdown Viewer) affiche des fichiers Markdown à la charte ok-ia.ch :
diagrammes Mermaid, cartes Leaflet, callouts, coloration d'entités, résumé par Apple Intelligence.
Cette bêta sert à valider le rendu, la navigation et la stabilité sur iPhone, iPad et Mac.
```
- **Feedback Email** : `patrick@ok-ia.ch`
- **Marketing URL** : `https://ok-ia.ch`
- **Privacy Policy URL** : `https://ok-ia.ch/mdviewer/confidentialite.html`

---

## What to Test — 1.1.1 (29)

```
Merci de tester md Viewer ! Points à vérifier :

DANS CETTE VERSION — LES CARTES
• Ouvrez le document de démonstration, section « Carte géographique » : le fond
  doit être net, sans filigrane en travers, avec les noms de villes lisibles.
• Bouton des couches (en haut à droite de la carte) : basculez Clair / Sombre /
  OpenStreetMap. Les trois doivent se dessiner, et les marqueurs rester en place.
• Zoomez à fond, puis dézoomez : les noms restent nets, jamais pixelisés, et
  aucun lieu ne s'affiche deux fois dans deux alphabets.
• Bouton plein écran (⛶), en portrait ET en paysage.
• Exportez en PDF puis en Word : la carte doit y figurer entière, avec ses
  marqueurs et la mention de source en bas.
• En mode Avion : la carte annonce son indisponibilité et liste ses marqueurs,
  plutôt qu'un cadre vide.
• Sur un réseau lent (cellulaire, loin du wifi) : pendant que la carte charge, le cadre
  doit afficher « Chargement de la carte… » — et jamais rester gris et muet. Si c'est
  vraiment long, l'app bascule d'elle-même sur le fond OpenStreetMap, qui se remplit
  case par case.

OUVERTURE
• « Voir un exemple » pour charger le document de démonstration.
• Ouvrir un .md depuis Fichiers, le partage, ou un lien web.

RENDU
• Lecture fidèle (titres, tableaux, listes, citations) ; le titre du document ne doit PAS
  être coupé sous la barre d'outils.
• Diagrammes Mermaid + zoom plein écran.
• Cartes Leaflet : marqueurs, fonds de carte, bouton plein écran (portrait ET paysage).
• Callouts (note/tip/warning/bug) et coloration des entités.

RÉSUMÉ APPLE INTELLIGENCE (appareils compatibles)
• Bouton ✦ dans la barre du lecteur → « Résumé du document » : le résumé doit être structuré
  (chapitres, gras, listes). Le bouton est masqué si Apple Intelligence n'est pas disponible.

DISCUTER AVEC LE DOCUMENT (appareils compatibles)
• Bouton ✦ → « Discuter avec le document » : l'écran d'accueil propose des questions tirées
  du document lui-même, et pas seulement « Résume ce document ». Touchez-en une.
• Posez ensuite votre propre question : la réponse doit s'appuyer sur le seul contenu du
  rapport et rester structurée. Une question à laquelle le document ne répond pas doit être
  déclinée, pas inventée.
• Ouvrez un rapport rédigé dans une autre langue que l'app : les réponses doivent rester
  dans la langue de l'app.
• Changez la langue de l'app pendant une conversation : elle doit être réinitialisée, et
  l'app doit le dire.
• Bouton « Nouvelle conversation ». Enchaînez ensuite une dizaine de questions : quand
  l'historique devient trop long, l'app doit l'annoncer et poursuivre, pas se bloquer.

SIRI / SPOTLIGHT / RACCOURCIS
• « Ouvre le dernier rapport dans md Viewer », « Résume un rapport dans md Viewer » (nécessite un
  dossier de coffre configuré).

DIVERS
• Bouton « Ouvrir un fichier » (doit ouvrir le sélecteur).
• Mode sombre, rotation, export PDF, recherche, sommaire.
• iPhone, iPad et Mac.
```

---

## Beta App Review Information (testeurs externes uniquement)

- **Sign-in required** : Non.
- **Contact** : prénom/nom + e-mail + téléphone du responsable. ⚠️ à compléter.
- **Notes pour la review** (réutiliser celles de [`review-notes.md`](review-notes.md)) :
```
Aucun compte requis. Touchez « Voir un exemple » pour un document de démo couvrant toutes les
fonctionnalités. L'app fonctionne hors-ligne ; le réseau ne sert qu'aux tuiles de carte
(OpenFreeMap/OpenStreetMap) et au téléchargement d'un document via lien https. Le résumé utilise Apple
Intelligence ON-DEVICE (aucune donnée envoyée) et n'apparaît que sur appareil compatible.
```

---

## Rappels

- **Testeurs internes** (jusqu'à 100, membres de l'équipe) : aucune revue, build dispo
  immédiatement après traitement.
- **Testeurs externes** (jusqu'à 10 000, par groupe + lien public) : **revue bêta légère** requise
  une fois (puis automatique pour les builds suivants du même train).
- **Export compliance** : déjà géré (`ITSAppUsesNonExemptEncryption=false`).
- La version **macOS (Mac Catalyst)** se teste via **TestFlight pour Mac** (même fiche, archiver le
  Catalyst « My Mac »).
