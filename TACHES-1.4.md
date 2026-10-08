# 1.4 — « L'option Analytic »

Ouverte le **08/10/2026**, à la demande de Patrick. La 1.3 n'est pas encore sortie (elle attend le
Duo) : rien de la 1.4 n'entre dans la 1.3. Le détail et les raisons sont dans le README, section
« 1.4 — l'option Analytic ».

**Slogan proposé** : « md Viewer — vos documents prennent vie. » / « md Viewer — your documents
come alive. »

**Principe** : on valorise au maximum le document. Un rapport fornews donne déjà presque tout ;
Wikidata ne comble que ce qui manque.

## ⓪ Décisions de Patrick — avant toute ligne de code

- [ ] **Private Cloud Compute** : il contredit deux engagements publiés (« pas d'IA distante — pas
      même sur les serveurs d'Apple », roadmap ; « le contenu de vos documents n'est envoyé à aucun
      serveur », confidentialité). Le faire ou non ; si oui, choix explicite par document, et les
      deux pages réécrites avant la sortie.
- [ ] **Wikidata** : requête réseau qui envoie des noms d'entités à Wikimedia. Imposée ou proposée ?
      Texte de la politique de confidentialité.
- [ ] **Prix** : deux produits de 2 francs (« Analytic » sur iPhone et iPad, « Analytic pour Mac »
      avec l'import) — achat universel oblige, un seul produit serait rendu sur toutes les
      plateformes. Confirmer, et vérifier le palier CHF 2.00 dans App Store Connect.
- [ ] **Slogan** : retenir une formule, FR et EN.

## ① Achat de l'option

- [ ] Deux produits non consommables dans App Store Connect, textes en cinq langues.
- [ ] StoreKit 2 : achat, restauration, vérification au lancement — partir de `FornewsAchat`
      (`AchatModele`, `PaywallView`) dans fornews.
- [ ] Le Mac ne regarde que son produit ; iPhone et iPad le leur.
- [ ] Écran de présentation de l'option : ce qu'elle apporte, le prix, la confidentialité.

## ② Détection d'entités

- [ ] Reprendre l'algorithme de fornews (`FornewsCore` : `NLTagger`, `FiltreEntitesNER`,
      vérificateurs) — paquet partagé plutôt que copie, à décider.
- [ ] **Rapport fornews d'abord** : section `## Entités`, balises de dates et de montants, cartes
      `leaflet`, sources — ne rien redemander à Wikidata de ce que le document donne.
- [ ] **fornews d'abord, Wikidata ensuite** quand fornews est installé : rejoindre le groupe
      `group.ai.fornews.native`, lire le cache d'entités que fornews y publie (⚠️ fornews doit
      l'y publier — tâche côté fornews).
- [ ] Résolution Wikidata (QID, genre, coordonnées, image) pour le reste.
- [ ] **Cache local** des entités résolues, **partagé par iCloud** entre les appareils.

## ③ Galerie et carte

- [ ] Galerie d'entités par genre (personnes, organisations, lieux, produits…).
- [ ] Carte des entités localisées, **plein écran sur demande** (reprendre la pile carte du lecteur :
      Leaflet + MapLibre, OpenFreeMap).
- [ ] Dans **la partie de droite** quand l'écran le permet (Duo déplié, grand écran en paysage,
      Mac) : un nouveau `PanneauDuo.entites` ; ailleurs, une feuille.
- [ ] **Ouvrir une entité dans fornews par son QID** — ⚠️ fornews n'ouvre aujourd'hui qu'un
      identifiant interne (`fornews://entite/<UUID>`) : route `fornews://entite?qid=Q…` à ajouter
      côté fornews.

## ④ Import Word et PDF — Mac seulement

- [ ] Extraction du texte et des images : PDFKit pour le PDF ; pour le `.docx`, éprouver d'abord ce
      que Catalyst sait lire (AppKit le fait, UIKit pas d'office) — sinon extraction du zip XML.
- [ ] **Générer un rapport au format md Viewer**, comme fornews génère un rapport d'article :
      reprendre au maximum son code (`GenerateurRapportAnalyste`).
- [ ] **Compte à rebours** pendant l'import, inspiré de `CompteReboursDemandeView` de fornews, qui
      montre les éléments détectés au fur et à mesure.
- [ ] **Images** : `data:image/…;base64` pour quelques petites images (déjà lu par md Viewer) ;
      au-delà, le format **TextBundle / TextPack** (`.md` + `assets/`, zippé en `.textpack`) —
      md Viewer apprend à l'ouvrir.

## ⑤ Modèles plus poussés (si ⓪ dit oui)

- [ ] Private Cloud Compute, au choix explicite de l'utilisateur, document par document, jamais par
      défaut ; libellés clairs sur ce qui quitte l'appareil.

## ⑥ Publication

- [ ] Feuille de route publique (FR et EN) — après les décisions de ⓪.
- [ ] Politique de confidentialité mise à jour (Wikidata, iCloud, PCC le cas échéant).
- [ ] Fiche App Store, captures, notes de version, post Mastodon.
