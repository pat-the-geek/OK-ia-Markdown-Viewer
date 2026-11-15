# md Viewer sous Windows : le matériel et le logiciel à prévoir

*Étude préparée le 15 novembre 2026, puis recentrée le même soir sur ta demande. Les prix sont des
ordres de grandeur, à vérifier au moment d'acheter.*

**Périmètre :** un md Viewer **gratuit et limité** pour Windows, destiné en premier lieu aux
**clients** qui reçoivent un partage d'OK-ia. Il permet deux choses :
1. **consulter** des documents Markdown ;
2. **recevoir les partages chiffrés** : ouvrir un document, ou télécharger et enregistrer un
   fichier jusqu'à 500 Mo.

Il n'aurait **ni IA, ni import, ni option Analytic**.

## En bref

- **Ce périmètre réduit fait de Windows un projet raisonnable.** Ce qui coûtait le plus cher
  disparaît : l'IA sur l'appareil, qui n'a pas d'équivalent sous Windows, et les imports Word,
  PDF et PowerPoint.
- **Le rendu se réutilise tel quel.** Celui de md Viewer est déjà du JavaScript (`render.js`,
  Mermaid, Leaflet, MapLibre). Le lecteur en ligne d'ok-ia.ch le fait tourner dans Edge et Chrome.
  Sous Windows, il tournerait dans **WebView2**, le moteur d'Edge, intégré à Windows 11.
- **Il reste à écrire** une fenêtre, l'ouverture des fichiers et les **partages chiffrés**. Je
  recommande **C# avec WinUI 3**.
- **Matériel :** ton Mac avec Parallels pour développer, plus **un vrai PC Intel ou AMD** pour les
  essais, puisque c'est ce qu'auront tes clients.
- **Les comptes ne coûtent rien.** L'inscription au Microsoft Store est gratuite, et le Store signe
  l'app. C'est aussi par le Store qu'un client l'installerait le plus simplement.
- **Budget de départ :** environ **250 à 400 CHF** la première année avec ton Mac seul, ou
  **1 000 à 1 600 CHF** avec un PC d'essai.

---

## 1. Ce que fait le md Viewer pour Windows

| Fonction | Sous Windows | Effort |
|---|---|---|
| **Lire un document** : Markdown, diagrammes Mermaid, cartes, callouts, thèmes | Le dossier `Web/` de md Viewer dans WebView2, sans changement | Faible |
| **Naviguer** : sommaire, recherche, zoom | WebView2 + une barre WinUI | Faible |
| **Ouvrir** : bouton, glisser-déposer, double-clic sur un `.md`, documents récents | WinUI, associations de fichiers déclarées dans le manifeste | Moyen |
| **Recevoir un partage chiffré** : un document à lire (versions 1) ou un fichier à enregistrer (versions 2 et 3, jusqu'à 500 Mo), avec la progression et le choix du dossier | Le lien `mdviewer://partage` déclaré dans le manifeste ; `AesGcm` de .NET ; lecture en flux, comme sur Apple | Moyen |
| **15 langues** | Fichiers `.resw`, produits par un script depuis le catalogue actuel | Faible |
| *En option, peu coûteux* : le diaporama, l'impression en PDF | `presentation.js` et `PrintToPdfAsync` de WebView2 | Faible |

**Ce qui n'y est pas :**
- l'IA (résumé, discussion, traduction, conversion en diaporama) ;
- les imports et l'option Analytic ;
- l'export Word et PowerPoint ;
- le coffre, la télécommande, Siri, Spotlight et la liaison avec fornews.

**Les partages chiffrés, au cœur du projet.** Un PC n'a en général pas de quoi scanner un QR code.
Le bouton de la page, « Ouvrir sur ce Mac », deviendrait « Ouvrir sur ce PC » : il appelle le même
lien `mdviewer://`, et c'est justement le chemin qui manque aujourd'hui à un client sur PC.

Le contrat (versions 1 à 3), les vecteurs de test et les 56 cas du banc d'essai de l'app Apple se
reprennent tels quels. Ils garantissent que les deux apps déchiffrent exactement de la même façon.

---

## 2. La technique recommandée

**WinUI 3 (Windows App SDK) en C#, avec WebView2 pour le document.**

Pourquoi ce choix :
- c'est la voie native de Microsoft, empaquetée en MSIX pour le Microsoft Store ;
- le lien `mdviewer://` et l'ouverture des `.md` se déclarent dans le manifeste ;
- .NET fournit AES-GCM d'origine, et la lecture de fichiers de 500 Mo en flux y est simple ;
- WebView2 est le moteur où le lecteur en ligne fonctionne déjà ;
- C# est un langage que Claude Code maîtrise bien.

Pour mémoire :
- **Tauri** (Rust + WebView2) donnerait une app très légère et Linux presque sans effort. Il
  mérite d'être réétudié si Linux devient un objectif.
- **Electron** est trop lourd pour une visionneuse.

Le code Swift de l'app Apple ne se copie pas : SwiftUI n'existe pas sous Windows. Il sert de
cahier des charges, avec `PartageOKia.swift` comme référence pour les partages.

---

## 3. Le matériel

### A. Pour développer : ton Mac, avec Parallels

- **Windows 11 Pro ARM** dans **Parallels Desktop**. Visual Studio 2026 y fonctionne en natif
  ARM64, et l'app se compile pour x64 et ARM64 depuis la même machine.
- Pour la machine virtuelle : au moins **8 Go de mémoire** (16 Go confortables), **4 cœurs** et
  environ **100 Go** de disque.
- Côté Mac : **16 Go de mémoire au minimum**, 24 à 32 Go pour rester à l'aise.

### B. Pour essayer : un vrai PC x64 *(fortement conseillé avant de livrer à un client)*

Tes clients auront un PC **Intel ou AMD**. Une machine virtuelle ARM ne dit rien de fiable sur ce
qui compte ici :
- le **débit d'un téléchargement de 500 Mo** et l'écriture sur un disque ordinaire ;
- l'**agrandissement de l'écran** (125 %, 150 %) ;
- **SmartScreen** et l'installation par le Store, vues comme un client les verra.

Un mini-PC ou un portable récent suffit : **16 Go** de mémoire, SSD de **512 Go**, **Windows 11
Pro**, environ **700 à 1 000 CHF**. Pas besoin d'un PC Copilot+ : il n'y a pas d'IA.

---

## 4. Les logiciels et les comptes

| Élément | Rôle | Coût |
|---|---|---|
| **Parallels Desktop** (édition Standard) | Windows sur le Mac | ≈ **100 $ par an** |
| **Licence Windows 11 Pro** | Pour la machine virtuelle (le PC d'essai l'a d'origine) | ≈ **150 à 260 CHF**, selon le canal |
| **Visual Studio 2026 Community** + charge de travail WinUI | Éditeur, compilation, débogage | **Gratuit** pour un indépendant ou une petite structure (conditions Community à relire) |
| **Windows App SDK** et **SDK .NET** | Le socle de l'app | Gratuit |
| **WebView2** | Affichage du document | Gratuit, intégré à Windows 11 |
| **Git, GitHub, GitHub Actions** (machines Windows) | Dépôt, compilation automatique | Gratuit au volume prévu |
| **Claude Code** | Fonctionne sous Windows | Ton abonnement actuel |
| **Compte développeur Microsoft Store** | Publier l'app | **Gratuit** (particuliers depuis 2025, sociétés depuis mai 2026) |
| **Signature de l'app** | Le Store signe les paquets qu'il distribue | **Rien à acheter** si l'on passe par le Store |

**À éviter : la distribution hors du Store.** Elle demande de signer soi-même l'app. Le service
Microsoft (Artifact Signing) coûte environ **10 $ par mois**, mais il est réservé à certaines
organisations et à certains pays ; je n'ai pas trouvé la Suisse dans la liste. Une app non signée
déclenche l'alerte SmartScreen chez le client, ce qui ne fait pas bonne impression. Le Store règle
la question, et une app gratuite n'y paie aucune commission.

---

## 5. Le budget

| Scénario | Contenu | Première année |
|---|---|---|
| **Minimal** | Ton Mac + Parallels + licence Windows 11 Pro | ≈ **250 à 400 CHF** |
| **Recommandé** | Minimal + un PC x64 d'essai | ≈ **1 000 à 1 400 CHF** |

Les années suivantes, il ne reste guère que Parallels, environ 100 $ par an.

---

## 6. Par où commencer

1. **Le lecteur** : une fenêtre WinUI avec WebView2, qui ouvre un `.md` et l'affiche avec le
   `render.js` actuel. C'est la preuve que le rendu passe tel quel, en quelques jours.
2. **Les partages chiffrés** : le lien `mdviewer://partage`, puis les versions 1 à 3, vérifiées
   avec les vecteurs de test de l'app Apple. Ensuite un vrai partage de 500 Mo sur le PC d'essai.
3. **Le confort** : récents, glisser-déposer, associations de fichiers, 15 langues.
4. **Le Store** : fiche, captures, publication.
5. **Côté site** : le bouton « Ouvrir sur ce PC » sur la page d'un partage, à voir avec la session
   du site.

## 7. Points de vigilance

- **Deux apps à entretenir, mais peu.** Le périmètre limité garde l'app Windows petite. Il faudra
  pourtant suivre chaque évolution du format des partages, et la règle de copie du dossier `Web/`
  (md Viewer reste l'original).
- **Les engagements tiennent sous Windows aussi** : pas de compte, pas de serveur, pas de
  pistage. La clé d'un partage n'est gardée nulle part.
- **Ce qu'on annonce.** La feuille de route parle d'une **idée sans date**. Selon ta règle, une
  annonce ne décrirait que la capacité de l'app, jamais un service d'ok-ia.ch.
- **L'alternative sans app.** Apprendre les partages au lecteur en ligne (`rapport.html`) servirait
  les clients sur PC sans rien installer. Mais la clé passerait par le JavaScript d'une page, ce
  que tu as écarté. Le md Viewer pour Windows décrit ici en est la version sûre.

---

### Sources

- [Free developer registration for individual developers on Microsoft Store](https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/) — Windows Developer Blog, septembre 2025
- [Publish to Microsoft Store as a company, now with free registration](https://blogs.windows.com/windowsdeveloper/2026/05/07/publish-to-microsoft-store-as-a-company-now-with-free-registration-and-faster-onboarding/) — Windows Developer Blog, mai 2026
- [Artifact Signing (ex-Trusted Signing)](https://azure.microsoft.com/products/artifact-signing) et sa [FAQ](https://learn.microsoft.com/en-us/azure/artifact-signing/faq) — Microsoft Azure
- [Start here — développer pour Windows](https://learn.microsoft.com/en-us/windows/apps/get-started/start-here) et [notes de version de Windows App SDK 1.8](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-8) — Microsoft Learn
- [Visual Studio sur Mac en 2026 (Parallels, Windows 11 ARM)](https://gauravtiwari.org/visual-studio-on-mac/) — retour d'expérience d'un développeur
- [Parallels Desktop vs Windows laptop cost](https://www.parallels.com/blogs/parallels-desktop-vs-windows-laptop-cost/) — Parallels (prix des éditions)
