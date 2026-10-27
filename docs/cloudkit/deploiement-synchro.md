# Déployer le schéma CloudKit de la synchronisation (1.4) en Production

**Préparé le :** 27/10/2026 · **Conteneur :** `iCloud.ch.ok-ia.markdownviewer` · **Équipe :** `PU9BSXN2V5`

## Pourquoi

L'option Analytic partage entre les appareils de l'utilisateur ses annotations, ses corrections
d'entités et le cache des fiches Wikidata, par CloudKit, dans sa base **privée**
(`Models/Analytic/SynchroICloud.swift`, décision de Patrick du 27/10/2026).

Les builds **TestFlight et App Store** parlent à l'environnement de **Production**, qui refuse d'écrire
un type d'enregistrement qu'il ne connaît pas. En Développement, CloudKit crée les types à la volée ;
c'est pourquoi un build Debug ne verrait jamais le problème. Même leçon que fornews (`BulletinMontre`,
16/09/2026).

## Ce qui est déployé, et rien d'autre

**Trois types d'enregistrement, mêmes trois champs** (fragment : `SynchroAnalytic.ckdb`) :

| Type | Un enregistrement par… |
|---|---|
| `Annotations` | document annoté (clé : empreinte du nom et du contenu, `IdentiteDocument`) |
| `Corrections` | utilisateur (le fichier `corrections.json`) |
| `CacheEntites` | utilisateur (le cache `entites-v2.json`, fusionné entre appareils) |

| Champ | Type CloudKit | Contenu |
|---|---|---|
| `nom` | **String** | le nom du fichier, sans extension |
| `modifie` | **Date/Time** | la date de modification du fichier sur l'appareil qui l'a envoyé |
| `contenu` | **Asset** | le fichier JSON tel que l'app l'écrit |

- **Aucun index** : l'app relève les changements de sa zone (`recordZoneChanges`), jamais par requête.
- **Aucune zone** à déclarer : la zone `Analytic` est créée par l'app, et les zones ne font pas
  partie du schéma.

⚠️ **Irréversible, mais sans risque** : un type déployé en Production ne se supprime plus ; inutile, il
resterait vide.

## ⛔ La précaution qui compte

*Deploy Schema Changes* pousse **tout l'écart** entre Développement et Production. C'est le premier
déploiement de ce conteneur : la liste doit contenir **exactement les trois types ci-dessus**, rien
d'autre. Sinon, annuler et me transmettre la liste.

## Chemin recommandé — le seed du projet (comme fornews)

Un build **Debug** du Mac écrit dans l'environnement de **Développement** une sentinelle de chaque
type, par **le même code que l'envoi** (`SynchroICloud.enregistrement`), dans une zone à part
(`Amorcage`), puis l'efface avec sa zone ; les types et leurs champs restent au schéma.

1. Build Debug **signé** — ton compte développeur connecté dans Xcode (pas la clé d'API) :

   ```bash
   xcodebuild -project "OK-ia - md Viewer.xcodeproj" -scheme "md Viewer" -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/ddmac -allowProvisioningUpdates build
   ```

2. Lancer le seed (le Mac doit être connecté à iCloud) ; l'app se ferme seule :

   ```bash
   "build/ddmac/Build/Products/Debug-maccatalyst/md Viewer.app/Contents/MacOS/md Viewer" -OKIASeedSchema YES
   ```

3. Le terminal doit afficher quatre lignes :
   - `md Viewer[seed] Annotations écrit en Development (champs nom, modifie, contenu).`
   - `md Viewer[seed] Corrections écrit en Development (champs nom, modifie, contenu).`
   - `md Viewer[seed] CacheEntites écrit en Development (champs nom, modifie, contenu).`
   - `md Viewer[seed] seed RÉUSSI (3 types).`

   « Bad Container » juste après la création du conteneur : CloudKit ne le connaît pas encore,
   réessayer quelques minutes plus tard.
4. [Console CloudKit](https://icloud.developer.apple.com/dashboard/) → conteneur
   `iCloud.ch.ok-ia.markdownviewer` → **Development** → *Record Types* : les trois types, avec
   `nom`, `modifie` et `contenu`.
5. **Deploy Schema Changes…** → ⛔ lire la liste → **Production**.

## Chemin de secours — la console seule

Development → Schema → Record Types → **+**, pour chacun des trois types : champs `nom` (String),
`modifie` (Date/Time), `contenu` (Asset). Puis l'étape 5 ci-dessus.

## Après le déploiement

Rien à reconstruire : les builds TestFlight synchronisent au lancement et à chaque retour au premier
plan. Vérification : annoter un document sur l'iPhone, ouvrir le même document sur le Mac (même nom,
même contenu) — les annotations y sont.
