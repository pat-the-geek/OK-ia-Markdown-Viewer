# Confidentialité — App Store

Deux choses ici : **(1)** les réponses au questionnaire *App Privacy* d'App Store Connect, et
**(2)** un **brouillon de politique de confidentialité** à héberger (URL obligatoire).

---

## 1. Questionnaire « App Privacy » (App Store Connect)

**Réponse globale : « Données non collectées » (Data Not Collected).** ✅

Justification (faits vérifiés dans le code) :
- Aucun SDK de tracking/analytics (Firebase, Crashlytics, Facebook, etc.) — confirmé.
- Aucun compte, aucun identifiant, aucune connexion serveur propriétaire.
- Le résumé Apple Intelligence tourne **sur l'appareil** (framework *Foundation Models*) — aucun
  texte n'est envoyé à un serveur.
- Stockage **local uniquement** : fichiers récents et bookmarks security-scoped du coffre
  (UserDefaults / bookmarks), jamais transmis.

> Donc, dans le questionnaire, répondre **« Non »** à « collectez-vous des données ? ».

### Point d'attention — accès réseau tiers (à mentionner, mais ce n'est PAS de la collecte)
L'app effectue des requêtes réseau dans deux cas, **à l'initiative de l'utilisateur** :
- **Tuiles de fond de carte** (Leaflet) : `*.basemaps.cartocdn.com`, `*.tile.openstreetmap.org`.
- **Téléchargement d'un rapport** quand l'utilisateur ouvre une URL `https` (`mdviewer://open?url=…`)
  et images distantes contenues dans un document.

Ces serveurs tiers reçoivent techniquement une adresse IP (comme tout chargement web), mais
**l'app ne collecte ni ne relie ces données à l'utilisateur**, et il n'y a **aucun tracking**.
→ Cela reste compatible avec « Données non collectées ». À documenter dans la politique ci-dessous
par transparence.

### Classification « tracking »
- **Non**, l'app ne fait aucun suivi (App Tracking Transparency non requis).

---

## 2. Politique de confidentialité (brouillon à héberger)

À publier à une URL stable, p.ex. `https://ok-ia.ch/confidentialite`, puis renseigner cette URL
dans App Store Connect (champ **obligatoire**). ⚠️ Adapter le nom de l'éditeur / contact.

```markdown
# Politique de confidentialité — md Viewer (OK-ia Markdown Viewer)

Dernière mise à jour : <date>

md Viewer est un lecteur de documents Markdown. Notre principe : **vos documents restent les vôtres.**

## Données que nous collectons
**Aucune.** L'application ne crée pas de compte, n'intègre aucun outil d'analyse ou de publicité,
et ne transmet aucune donnée personnelle à OK-ia ou à des tiers à des fins de suivi.

## Données stockées sur votre appareil
- La liste de vos **fichiers récents** et la référence (bookmark) de votre **dossier de coffre**,
  afin de vous les reproposer. Ces informations restent **sur votre appareil** et ne sont pas envoyées.

## Accès réseau
L'application se connecte à Internet uniquement lorsque **vous** le déclenchez :
- pour afficher les **fonds de carte** des documents contenant une carte (fournis par
  OpenStreetMap et CARTO) ;
- pour **télécharger un rapport** ou une image lorsque vous ouvrez un lien `https`.
Ces services tiers peuvent recevoir votre adresse IP, comme pour tout chargement de page web.
Consultez leurs politiques : OpenStreetMap, CARTO.

## Intelligence artificielle
La fonction « Résumé du document » utilise **Apple Intelligence sur l'appareil**. Le contenu de
vos documents **n'est pas envoyé** à un serveur pour être résumé.

## Vos droits / contact
Comme aucune donnée personnelle n'est collectée, il n'y a rien à consulter, corriger ou supprimer
de notre côté. Pour toute question : <email de contact>.
```
