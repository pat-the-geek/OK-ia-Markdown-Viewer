import Foundation
import CryptoKit

/// Les partages chiffrés d'ok-ia.ch (1.5.1, demandé par Patrick le 15/11/2026). Le contrat avec le
/// site est `docs/md-viewer/instructions-partage-qr.md` du dépôt fornews.
///
/// Une page `https://ok-ia.ch/p/<id>/` montre un QR code (ou un bouton) qui ouvre
/// `mdviewer://partage?id=<id>&j=<jeton>`. Le jeton vaut 60 secondes et une seule fois :
/// md Viewer l'échange aussitôt contre la clé, télécharge le conteneur chiffré et le déchiffre sur
/// l'appareil (AES-256-GCM). Trois versions du conteneur :
/// - **1** : un document Markdown, affiché comme un document sans fichier ;
/// - **2** : un FICHIER quelconque de 50 Mo au plus, d'un seul bloc ;
/// - **3** : un FICHIER jusqu'à 2 Go, découpé en morceaux authentifiés chacun avec son rang ET
///   le total — déchiffré et écrit au fil de la réception, sans tenir le fichier en mémoire. But
///   (Patrick, 15/11/2026) : envoyer de gros fichiers à des clients, qui les ouvrent dans md Viewer.
/// Un fichier ne s'ouvre pas : md Viewer propose de l'enregistrer. Son nom et son type sont dans le
/// chiffré, jamais sur la page publique.
///
/// Ce qui ne doit jamais arriver :
/// - aller chercher autre chose que `https://ok-ia.ch` : md Viewer construit lui-même les deux
///   adresses, le lien ne porte que deux identifiants contrôlés ;
/// - écrire la clé ou le lien complet quelque part (journal, documents récents, état restauré) :
///   la clé ne vit que le temps du déchiffrement, et l'on ne journalise rien ici ;
/// - garder une trace réseau : session éphémère, ni cache ni cookie ;
/// - laisser un fichier déchiffré à moitié : une erreur efface la copie temporaire.
enum PartageOKia {

    /// Un lien `mdviewer://partage?id=…&j=…`, contrôlé.
    struct Lien: Equatable {
        let id: String
        let jeton: String

        /// 16 octets en base64url sans `=` : exactement 22 caractères `[A-Za-z0-9_-]`.
        static func valide(_ s: String) -> Bool {
            s.count == 22 && s.unicodeScalars.allSatisfy {
                ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_"
            }
        }

        /// Les paramètres `id` et `j` d'un lien déjà reconnu comme `mdviewer://partage`.
        init?(composants: URLComponents) {
            let items = composants.queryItems ?? []
            guard let id = items.first(where: { $0.name == "id" })?.value,
                  let jeton = items.first(where: { $0.name == "j" })?.value,
                  Self.valide(id), Self.valide(jeton) else { return nil }
            self.id = id
            self.jeton = jeton
        }

        init?(url: URL) {
            guard url.scheme?.lowercased() == "mdviewer",
                  url.host?.lowercased() == "partage",
                  let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            self.init(composants: c)
        }
    }

    enum Erreur: Error, Equatable, LocalizedError {
        case lienInvalide
        /// 410 : jeton expiré ou déjà utilisé.
        case codeExpire
        /// 404 : partage inconnu, expiré ou retiré.
        case partageRetire
        /// 429 : trop de demandes.
        case tropDeTentatives
        /// Tout autre statut, ou pas de réseau.
        case injoignable
        /// En-tête absent ou version inconnue.
        case versionInconnue
        /// Échec de l'authentification AES-GCM, conteneur mal formé ou tronqué.
        case illisible
        /// Plus que les bornes : 50 Mo (versions 1 et 2), 2 Go (version 3).
        case tropGros
        /// Le fichier reçu n'a pas pu s'écrire sur l'appareil (place, droits).
        case ecriture

        var errorDescription: String? {
            switch self {
            case .lienInvalide: return tr("Ce lien de partage n'est pas valide.")
            case .codeExpire: return tr("Ce code a expiré. Scannez le code affiché maintenant sur la page.")
            case .partageRetire: return tr("Ce partage a expiré ou a été retiré.")
            case .tropDeTentatives: return tr("Trop de tentatives. Réessayez dans une minute.")
            case .injoignable: return tr("Impossible de joindre ok-ia.ch. Vérifiez la connexion.")
            case .versionInconnue: return tr("Ce partage demande une version plus récente de md Viewer.")
            case .illisible: return tr("Document illisible ou modifié.")
            case .tropGros: return tr("Ce partage est trop volumineux pour être ouvert.")
            case .ecriture: return tr("Impossible d'enregistrer le fichier.")
            }
        }
    }

    /// Le contenu d'un conteneur d'un seul bloc (versions 1 et 2).
    enum Contenu: Equatable {
        case document(String)
        case fichier(Fichier)
    }

    /// Un fichier de version 2 : son nom (déjà rendu sûr pour un disque), son type, ses octets.
    struct Fichier: Equatable {
        let nom: String
        let type: String
        let octets: Data
    }

    /// Ce que l'app reçoit au bout du compte : un document à lire, ou un fichier déjà déchiffré dans
    /// un dossier temporaire, à enregistrer.
    enum Recu {
        case document(String)
        case fichier(FichierRecu)
    }

    // MARK: Ouvrir

    /// Échange le jeton (tout de suite, avant toute autre chose), télécharge le partage et le
    /// déchiffre au fil de la réception. La clé n'existe que dans cette fonction. `progression`
    /// reçoit la part reçue (0…1) quand le serveur annonce la taille.
    static func ouvrir(_ lien: Lien, transport: TransportPartage,
                       progression: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Recu {
        let cle = try await transport.echanger(id: lien.id, jeton: lien.jeton)
        let flux = try await transport.telecharger(id: lien.id)
        return try await recevoir(flux, cle: cle, id: lien.id, progression: progression)
    }

    /// Lit un flux de conteneur, quelle que soit sa version.
    static func recevoir(_ flux: FluxPartage, cle: Data, id: String,
                         progression: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Recu {
        if flux.taille > Int64(tailleMax3) { throw Erreur.tropGros }
        let lecteur = LecteurPartage(cle: cle, id: id)
        var recu: Int64 = 0
        var dernier = -1
        do {
            for try await morceau in flux.morceaux {
                try lecteur.ajouter(morceau)
                recu += Int64(morceau.count)
                if flux.taille > 0 {
                    let p = min(100, Int(recu * 100 / flux.taille))
                    if p != dernier { dernier = p; progression(Double(p) / 100) }
                }
            }
            return try lecteur.terminer()
        } catch {
            lecteur.abandonner()
            throw (error as? Erreur) ?? Erreur.injoignable
        }
    }

    // MARK: Le format `document.okia`

    static let entete = Data("OKIA".utf8)
    /// 1 : le Markdown en UTF-8. 2 : une ligne JSON puis le fichier, d'un bloc. 3 : découpé.
    static let versions: Set<UInt8> = [1, 2, 3]
    /// Versions 1 et 2 : le site accepte 50 Mo de fichier ; le conteneur ajoute l'en-tête, le nonce,
    /// l'étiquette et la ligne JSON : 64 Kio de marge.
    static let tailleMax = 50 * 1024 * 1024 + 64 * 1024
    /// Version 3 : 2 Go de fichier (Patrick, 15/11/2026 : 500 Mo d'abord, puis 2 Go après un essai
    /// réussi à 400 Mo). Au-delà, ce n'est plus l'app qui coince mais l'envoi depuis la connexion
    /// domestique et le CDN.
    static let tailleMaxFichierV3 = 2 * 1024 * 1024 * 1024
    /// Version 3 : le conteneur entier, 28 octets par morceau en plus et l'en-tête — 2 Mio de marge
    /// (32 769 morceaux de 64 Kio au pire : 0,9 Mio).
    static let tailleMax3 = tailleMaxFichierV3 + 2 * 1024 * 1024
    /// Version 3 : la taille d'un morceau en clair, bornée des deux côtés (trop petits, ils
    /// multiplient les étiquettes ; trop grands, ils pèsent en mémoire).
    static let morceauMin = 64 * 1024
    static let morceauMax = 16 * 1024 * 1024
    /// La ligne JSON (version 2) ou l'en-tête chiffré (version 3) ne dépasse jamais cela.
    static let enteteMax = 4096

    /// Versions 1 et 2, d'un seul bloc : `OKIA` (4 octets), version (1), nonce (12), texte chiffré,
    /// étiquette (16). AAD : `ok-ia.ch/p/<id>` — un fichier déplacé sous un autre identifiant ne
    /// s'ouvre pas. La version est contrôlée AVANT le déchiffrement : une version inconnue n'est
    /// pas « modifiée ».
    static func dechiffrer(_ fichier: Data, cle: Data, id: String) throws -> Contenu {
        let f = Data(fichier)   // indices à partir de 0, quel que soit le découpage reçu
        guard f.count >= 5, f.prefix(4) == entete, f[4] == 1 || f[4] == 2 else { throw Erreur.versionInconnue }
        guard f.count >= 5 + 12 + 16 else { throw Erreur.illisible }
        let clair = try ouvrirBoite(f[5...], cle: cle, aad: "ok-ia.ch/p/\(id)")
        if f[4] == 2 { return .fichier(try lireFichier(clair)) }
        guard let texte = String(data: clair, encoding: .utf8) else { throw Erreur.illisible }
        return .document(texte)
    }

    /// `nonce (12) | chiffré | étiquette (16)` → le clair, ou `illisible`.
    static func ouvrirBoite(_ boite: Data, cle: Data, aad: String) throws -> Data {
        let b = Data(boite)
        guard cle.count == 32, b.count >= 12 + 16 else { throw Erreur.illisible }
        do {
            let s = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: b[0..<12]),
                                          ciphertext: b[12..<(b.count - 16)], tag: b[(b.count - 16)...])
            return try AES.GCM.open(s, using: SymmetricKey(data: cle), authenticating: Data(aad.utf8))
        } catch {
            throw Erreur.illisible
        }
    }

    /// `{"nom":"archive.zip","type":"application/zip","taille":13838}\n<octets>` : découpé au
    /// PREMIER saut de ligne, tout ce qui suit est le fichier, quoi qu'il contienne. La taille
    /// annoncée doit être celle reçue.
    static func lireFichier(_ clair: Data) throws -> Fichier {
        let c = Data(clair)
        guard let fin = c.prefix(enteteMax).firstIndex(of: 0x0A) else { throw Erreur.illisible }
        let e = try lireEntete(c[..<fin])
        let octets = c[(fin + 1)...]
        guard e.taille == octets.count else { throw Erreur.illisible }
        return Fichier(nom: e.nom, type: e.type, octets: Data(octets))
    }

    /// L'en-tête JSON d'un fichier : `nom` (rendu sûr), `type` (facultatif), `taille`.
    static func lireEntete(_ json: Data) throws -> (nom: String, type: String, taille: Int) {
        guard let objet = try? JSONSerialization.jsonObject(with: Data(json)) as? [String: Any],
              let nom = objet["nom"] as? String,
              let taille = (objet["taille"] as? NSNumber)?.intValue, taille >= 0 else { throw Erreur.illisible }
        let type = (objet["type"] as? String).map { String($0.prefix(200)) } ?? "application/octet-stream"
        return (nomSur(nom), type, taille)
    }

    /// Un nom de fichier qui ne sort pas du dossier choisi : dernier composant seulement, sans
    /// séparateur, caractère de contrôle ni point en tête ; « partage » s'il ne reste rien.
    static func nomSur(_ nom: String) -> String {
        let interdits = CharacterSet(charactersIn: "/\\:").union(.controlCharacters).union(.newlines)
        var n = String(String.UnicodeScalarView(nom.unicodeScalars.filter { !interdits.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        while n.hasPrefix(".") { n.removeFirst() }
        if n.count > 120 {
            let ext = (n as NSString).pathExtension
            let base = (n as NSString).deletingPathExtension
            n = ext.isEmpty || ext.count > 10 ? String(n.prefix(120)) : String(base.prefix(110)) + "." + ext
        }
        return n.isEmpty ? tr("partage") : n
    }

    /// Base64url sans `=` (RFC 4648 §5) vers des octets.
    static func base64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }

    /// Le titre d'un document sans fichier : son premier `#`, sinon « Partage ».
    static func titre(_ markdown: String) -> String {
        for ligne in markdown.split(separator: "\n", omittingEmptySubsequences: true).prefix(60) {
            let l = ligne.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("# ") {
                let t = l.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { return String(t.prefix(120)) }
            }
        }
        return tr("Partage")
    }
}

/// Lit un conteneur morceau par morceau, à mesure qu'il arrive.
///
/// Version 3 :
/// ```
/// OKIA (4) | 0x03 (1) | N (u32 gros-boutiste) | M (u32) | L (u32)
/// morceau 0, l'en-tête : nonce (12) | chiffré (L) | étiquette (16)
///     clair = {"nom":…,"type":…,"taille":…}, sans saut de ligne
/// morceaux 1…N, le fichier : nonce (12) | chiffré (M, sauf le dernier) | étiquette (16)
///     le dernier fait taille − (N − 1) × M
/// AAD du morceau i : « ok-ia.ch/p/<id>#<i>/<N> »
/// N = ⌈taille / M⌉ (0 pour un fichier vide), 64 Kio ≤ M ≤ 16 Mio, 1 ≤ L ≤ 4096, taille ≤ 2 Gio
/// ```
/// Le rang ET le total dans chaque AAD : on ne peut ni réordonner les morceaux, ni en retirer à
/// la fin, ni changer N en clair, sans qu'un déchiffrement échoue. Rien ne suit le morceau N.
final class LecteurPartage {
    private let cle: Data
    private let id: String
    private var tampon = Data()
    private var version: UInt8?

    private enum Etape { case prefixe, entete, morceaux, fini }
    private var etape = Etape.prefixe
    private var total = 0          // N
    private var taillePleine = 0   // M
    private var longueurEntete = 0 // L
    private var taille = 0
    private var rang = 1
    private var sortie: FileHandle?
    private var recu: FichierRecu?

    init(cle: Data, id: String) {
        self.cle = cle
        self.id = id
    }

    func ajouter(_ d: Data) throws {
        tampon.append(d)
        if version == nil {
            guard tampon.count >= 5 else { return }
            guard tampon.prefix(4) == PartageOKia.entete, PartageOKia.versions.contains(tampon[tampon.startIndex + 4]) else {
                throw PartageOKia.Erreur.versionInconnue
            }
            version = tampon[tampon.startIndex + 4]
        }
        if version == 3 {
            try avancer()
        } else if tampon.count > PartageOKia.tailleMax {
            throw PartageOKia.Erreur.tropGros
        }
    }

    /// Le flux est fini : le contenu, ou l'erreur qui dit ce qui manque.
    func terminer() throws -> PartageOKia.Recu {
        guard let version else { throw PartageOKia.Erreur.versionInconnue }
        if version == 3 {
            guard etape == .fini, tampon.isEmpty, let recu else { throw PartageOKia.Erreur.illisible }
            try fermer()
            self.recu = nil
            return .fichier(recu)
        }
        switch try PartageOKia.dechiffrer(tampon, cle: cle, id: id) {
        case .document(let texte):
            return .document(texte)
        case .fichier(let f):
            do { return .fichier(try FichierRecu.ecrire(f)) } catch { throw PartageOKia.Erreur.ecriture }
        }
    }

    /// Une erreur en route : rien de déchiffré ne reste sur le disque.
    func abandonner() {
        try? sortie?.close()
        sortie = nil
        recu?.effacer()
        recu = nil
    }

    // MARK: Version 3

    private func prendre(_ n: Int) -> Data {
        let d = Data(tampon.prefix(n))
        tampon = Data(tampon.dropFirst(n))
        return d
    }

    private static func u32(_ d: Data, _ i: Int) -> Int {
        d[i..<(i + 4)].reduce(0) { $0 << 8 | Int($1) }
    }

    private func avancer() throws {
        while true {
            switch etape {
            case .prefixe:
                guard tampon.count >= 17 else { return }
                let p = prendre(17)
                total = Self.u32(p, 5)
                taillePleine = Self.u32(p, 9)
                longueurEntete = Self.u32(p, 13)
                guard (PartageOKia.morceauMin...PartageOKia.morceauMax).contains(taillePleine),
                      (1...PartageOKia.enteteMax).contains(longueurEntete),
                      total <= PartageOKia.tailleMaxFichierV3 / PartageOKia.morceauMin + 1 else {
                    throw PartageOKia.Erreur.illisible
                }
                etape = .entete
            case .entete:
                let n = 12 + longueurEntete + 16
                guard tampon.count >= n else { return }
                let clair = try PartageOKia.ouvrirBoite(prendre(n), cle: cle, aad: "ok-ia.ch/p/\(id)#0/\(total)")
                let e = try PartageOKia.lireEntete(clair)
                guard e.taille <= PartageOKia.tailleMaxFichierV3 else { throw PartageOKia.Erreur.tropGros }
                guard total == (e.taille + taillePleine - 1) / taillePleine else { throw PartageOKia.Erreur.illisible }
                taille = e.taille
                do {
                    let r = try FichierRecu.preparer(nom: e.nom)
                    recu = r
                    sortie = try FileHandle(forWritingTo: r.url)
                } catch {
                    throw PartageOKia.Erreur.ecriture
                }
                etape = total == 0 ? .fini : .morceaux
            case .morceaux:
                let clairAttendu = rang < total ? taillePleine : taille - (total - 1) * taillePleine
                let n = 12 + clairAttendu + 16
                guard tampon.count >= n else { return }
                let clair = try PartageOKia.ouvrirBoite(prendre(n), cle: cle, aad: "ok-ia.ch/p/\(id)#\(rang)/\(total)")
                guard clair.count == clairAttendu else { throw PartageOKia.Erreur.illisible }
                do { try sortie?.write(contentsOf: clair) } catch { throw PartageOKia.Erreur.ecriture }
                rang += 1
                if rang > total { etape = .fini }
            case .fini:
                // Rien ne suit le dernier morceau.
                if !tampon.isEmpty { throw PartageOKia.Erreur.illisible }
                return
            }
        }
    }

    private func fermer() throws {
        do { try sortie?.close() } catch { throw PartageOKia.Erreur.ecriture }
        sortie = nil
    }
}

/// Un fichier de partage, déchiffré dans un dossier temporaire à lui le temps que l'utilisateur
/// choisisse où l'enregistrer ; effacé ensuite, enregistré ou non.
struct FichierRecu: Identifiable, Sendable {
    let id = UUID()
    let dossier: URL
    let url: URL

    /// Un dossier neuf et un fichier vide, protégé sur iPhone et iPad.
    static func preparer(nom: String) throws -> FichierRecu {
        purger()
        let dossier = FileManager.default.temporaryDirectory
            .appendingPathComponent("partage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let url = dossier.appendingPathComponent(nom, isDirectory: false)
        var attributs: [FileAttributeKey: Any] = [:]
        #if os(iOS) && !targetEnvironment(macCatalyst)
        attributs[.protectionKey] = FileProtectionType.complete
        #endif
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributs) else {
            try? FileManager.default.removeItem(at: dossier)
            throw CocoaError(.fileWriteUnknown)
        }
        return FichierRecu(dossier: dossier, url: url)
    }

    static func ecrire(_ f: PartageOKia.Fichier) throws -> FichierRecu {
        let r = try preparer(nom: f.nom)
        do {
            let h = try FileHandle(forWritingTo: r.url)
            try h.write(contentsOf: f.octets)
            try h.close()
        } catch {
            r.effacer()
            throw error
        }
        return r
    }

    func effacer() { try? FileManager.default.removeItem(at: dossier) }

    /// Les copies qu'une app quittée en plein enregistrement aurait laissées.
    static func purger() {
        let tmp = FileManager.default.temporaryDirectory
        for nom in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? [] where nom.hasPrefix("partage-") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(nom, isDirectory: true))
        }
    }

    /// Le dossier proposé d'abord. Sur Mac : Téléchargements (le vrai, hors du conteneur de l'app ;
    /// c'est le panneau du système qui y écrit). Sur iPhone et iPad : le dossier md Viewer de
    /// l'appareil, et non le dernier dossier de Fichiers — souvent iCloud Drive, où un document
    /// confidentiel partirait chez Apple sans que personne ne l'ait décidé.
    static var dossierPropose: URL? {
        #if targetEnvironment(macCatalyst)
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appendingPathComponent("Downloads", isDirectory: true)
        }
        return nil
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        #endif
    }
}

/// Le conteneur chiffré tel qu'il arrive : sa taille annoncée (−1 si inconnue) et ses octets, par
/// morceaux.
struct FluxPartage: Sendable {
    let taille: Int64
    let morceaux: AsyncThrowingStream<Data, Error>

    init(taille: Int64, morceaux: AsyncThrowingStream<Data, Error>) {
        self.taille = taille
        self.morceaux = morceaux
    }

    /// Des octets déjà là, servis par morceaux (banc, vecteur de test).
    init(_ d: Data, morceau: Int = 65_536) {
        taille = Int64(d.count)
        morceaux = AsyncThrowingStream { c in
            var i = 0
            while i < d.count {
                c.yield(Data(d[i..<min(d.count, i + morceau)]))
                i += morceau
            }
            c.finish()
        }
    }
}

/// La reprise d'un téléchargement coupé (Patrick, 15/11/2026 : jusqu'à 2 Go par une connexion
/// domestique). À chaque coupure, on redemande la suite à partir de l'octet atteint — `ouvrir(depuis)`
/// —, jusqu'à 5 fois de suite sans progrès, en attendant 1, 2, 4, 8 puis 15 s. Le lecteur ne voit
/// qu'un seul flux continu. La reprise ne survit pas à l'app quittée : la clé, échangée une seule
/// fois, n'est gardée nulle part.
enum Reprise {
    /// Le serveur ne sait pas reprendre ce fichier (pas de plage, ou plus le même fichier).
    struct Impossible: Error {}

    static let attentes: [UInt64] = [1, 2, 4, 8, 15]

    static func flux(attendu: Int64, essaisMax: Int = 5, plafond: Int64 = Int64(PartageOKia.tailleMax3),
                     attendre: @escaping @Sendable (Int) async -> Void = { n in
                         try? await Task.sleep(nanoseconds: Reprise.attentes[min(n, Reprise.attentes.count) - 1] * 1_000_000_000)
                     },
                     ouvrir: @escaping @Sendable (Int64) async throws -> AsyncThrowingStream<Data, Error>)
        -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { c in
            let tache = Task {
                var recu: Int64 = 0
                var echecs = 0
                while true {
                    do {
                        for try await d in try await ouvrir(recu) {
                            recu += Int64(d.count)
                            if recu > plafond { throw PartageOKia.Erreur.tropGros }
                            if !d.isEmpty { echecs = 0 }
                            c.yield(d)
                        }
                        // Une fin propre mais trop tôt est une coupure comme une autre.
                        if attendu > 0, recu < attendu { throw PartageOKia.Erreur.injoignable }
                        c.finish()
                        return
                    } catch is Impossible {
                        c.finish(throwing: PartageOKia.Erreur.injoignable)
                        return
                    } catch let e as PartageOKia.Erreur where e != .injoignable {
                        c.finish(throwing: e)
                        return
                    } catch {
                        echecs += 1
                        guard !Task.isCancelled, attendu > 0, recu < attendu, echecs <= essaisMax else {
                            c.finish(throwing: PartageOKia.Erreur.injoignable)
                            return
                        }
                        await attendre(echecs)
                    }
                }
            }
            c.onTermination = { _ in tache.cancel() }
        }
    }

    /// Ce qu'on envoie dans `If-Range`. Un ETag FAIBLE (`W/"…"`, celui d'un proxy qui compresse) n'y
    /// vaut rien : le serveur renverrait tout (200) et la reprise s'arrêterait. On prend alors la date
    /// de modification ; sans elle, pas de reprise.
    static func validateur(etag: String?, modifie: String?) -> String? {
        if let e = etag?.trimmingCharacters(in: .whitespaces), !e.isEmpty, !e.hasPrefix("W/") { return e }
        if let m = modifie?.trimmingCharacters(in: .whitespaces), !m.isEmpty { return m }
        return nil
    }

    /// `Content-Range: bytes 1234-5677/5678` → (1234, 5678).
    static func plage(_ entete: String?) -> (debut: Int64, total: Int64)? {
        guard let e = entete?.trimmingCharacters(in: .whitespaces), e.hasPrefix("bytes ") else { return nil }
        let parties = e.dropFirst(6).split(separator: "/")
        guard parties.count == 2, let total = Int64(parties[1]),
              let debut = parties[0].split(separator: "-").first.flatMap({ Int64($0) }) else { return nil }
        return (debut, total)
    }
}

/// L'accès réseau du partage, derrière un protocole pour le tester sans serveur.
protocol TransportPartage: Sendable {
    /// `POST https://ok-ia.ch/api/partage/<id>/cle` `{"jeton": …}` → la clé (32 octets).
    func echanger(id: String, jeton: String) async throws -> Data
    /// `GET https://ok-ia.ch/p/<id>/document.okia` → le conteneur chiffré, en flux.
    func telecharger(id: String) async throws -> FluxPartage
}

/// Le vrai transport : toujours `https://ok-ia.ch`, session éphémère, 30 s de silence au plus.
struct TransportOKia: TransportPartage {
    static let hote = "ok-ia.ch"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.timeoutIntervalForRequest = 30      // 30 s sans un octet
        c.timeoutIntervalForResource = 3600   // une heure par requête ; au-delà, la reprise enchaîne
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// L'adresse est bâtie ici, avec l'identifiant déjà contrôlé (22 caractères base64url) :
    /// jamais une URL reçue dans le lien.
    private static func adresse(_ chemin: String) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = hote
        c.path = chemin
        return c.url
    }

    func echanger(id: String, jeton: String) async throws -> Data {
        guard PartageOKia.Lien.valide(id), PartageOKia.Lien.valide(jeton),
              let url = Self.adresse("/api/partage/\(id)/cle") else { throw PartageOKia.Erreur.lienInvalide }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["jeton": jeton])
        let (flux, reponse) = try await Self.demander(r)
        switch reponse.statusCode {
        case 200:
            var donnees = Data()
            do {
                for try await octet in flux {
                    donnees.append(octet)
                    if donnees.count > 4096 { throw PartageOKia.Erreur.illisible }
                }
            } catch let e as PartageOKia.Erreur { throw e } catch { throw PartageOKia.Erreur.injoignable }
            guard let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
                  let texte = objet["cle"] as? String,
                  let cle = PartageOKia.base64url(texte), cle.count == 32 else { throw PartageOKia.Erreur.illisible }
            return cle
        case 410: throw PartageOKia.Erreur.codeExpire
        case 404: throw PartageOKia.Erreur.partageRetire
        case 429: throw PartageOKia.Erreur.tropDeTentatives
        default: throw PartageOKia.Erreur.injoignable
        }
    }

    func telecharger(id: String) async throws -> FluxPartage {
        guard PartageOKia.Lien.valide(id),
              let url = Self.adresse("/p/\(id)/document.okia") else { throw PartageOKia.Erreur.lienInvalide }
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        let (flux, reponse) = try await Self.demander(r)
        switch reponse.statusCode {
        case 200: break
        case 404, 410: throw PartageOKia.Erreur.partageRetire
        case 429: throw PartageOKia.Erreur.tropDeTentatives
        default: throw PartageOKia.Erreur.injoignable
        }
        let attendu = reponse.expectedContentLength
        if attendu > Int64(PartageOKia.tailleMax3) { throw PartageOKia.Erreur.tropGros }
        // Ce qui garantit qu'une reprise lit LE MÊME fichier : sans validateur, on ne reprend pas
        // (on mêlerait deux versions du conteneur — l'authentification le refuserait, mais trop tard).
        let validateur = Reprise.validateur(etag: reponse.value(forHTTPHeaderField: "ETag"),
                                            modifie: reponse.value(forHTTPHeaderField: "Last-Modified"))
        let premier = Premier(flux)
        let requete = r
        let morceaux = Reprise.flux(attendu: attendu) { depuis in
            if let f = premier.prendre() { return Self.decouper(f) }
            var r2 = requete
            if depuis > 0 {
                guard let validateur else { throw Reprise.Impossible() }
                r2.setValue("bytes=\(depuis)-", forHTTPHeaderField: "Range")
                r2.setValue(validateur, forHTTPHeaderField: "If-Range")
            }
            let (f2, rep2) = try await Self.demander(r2)
            if depuis > 0 {
                // 206 et la plage demandée, sur le même total ; un 200 renverrait tout depuis le début.
                guard rep2.statusCode == 206, let p = Reprise.plage(rep2.value(forHTTPHeaderField: "Content-Range")),
                      p.debut == depuis, p.total == attendu else { throw Reprise.Impossible() }
            } else if rep2.statusCode != 200 {
                throw Reprise.Impossible()
            }
            return Self.decouper(f2)
        }
        return FluxPartage(taille: attendu, morceaux: morceaux)
    }

    /// Le premier corps reçu, servi une seule fois.
    private final class Premier: @unchecked Sendable {
        private let verrou = NSLock()
        private var flux: URLSession.AsyncBytes?
        init(_ f: URLSession.AsyncBytes) { flux = f }
        func prendre() -> URLSession.AsyncBytes? {
            verrou.lock(); defer { verrou.unlock() }
            let f = flux
            flux = nil
            return f
        }
    }

    /// Un corps HTTP en morceaux de 256 Kio. Une coupure livre d'abord ce qui était reçu, puis
    /// l'erreur : la reprise repart de là, rien n'est perdu ni compté deux fois.
    private static func decouper(_ flux: URLSession.AsyncBytes) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { c in
            let tache = Task {
                var morceau = [UInt8]()
                morceau.reserveCapacity(262_144)
                do {
                    for try await octet in flux {
                        morceau.append(octet)
                        if morceau.count == 262_144 {
                            c.yield(Data(morceau))
                            morceau.removeAll(keepingCapacity: true)
                        }
                    }
                    if !morceau.isEmpty { c.yield(Data(morceau)) }
                    c.finish()
                } catch {
                    if !morceau.isEmpty { c.yield(Data(morceau)) }
                    c.finish(throwing: PartageOKia.Erreur.injoignable)
                }
            }
            c.onTermination = { _ in tache.cancel() }
        }
    }

    /// La requête, sans suivre une redirection hors d'ok-ia.ch : la réponse, et son corps à lire.
    private static func demander(_ r: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let flux: URLSession.AsyncBytes
        let reponse: URLResponse
        do {
            (flux, reponse) = try await session.bytes(for: r, delegate: GardeHote())
        } catch {
            throw PartageOKia.Erreur.injoignable
        }
        guard let http = reponse as? HTTPURLResponse, http.url?.host == hote, http.url?.scheme == "https" else {
            throw PartageOKia.Erreur.injoignable
        }
        return (flux, http)
    }

    /// Refuse toute redirection qui quitterait `https://ok-ia.ch`.
    private final class GardeHote: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard request.url?.scheme == "https", request.url?.host == TransportOKia.hote else { return nil }
            return request
        }
    }
}

#if DEBUG
/// OKIA_PARTAGE_VECTEUR=<dossier> (Debug seulement, refusé par le script dans un binaire livré) :
/// remplace ok-ia.ch par le vecteur de test (`partage-vecteur-test.okia` + `.json`), pour voir
/// l'ouverture de bout en bout au simulateur.
struct TransportVecteur: TransportPartage {
    let dossier: URL
    func echanger(id: String, jeton: String) async throws -> Data {
        guard let d = try? Data(contentsOf: dossier.appendingPathComponent("partage-vecteur-test.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              (o["id"] as? String) == id, let k = (o["k"] as? String).flatMap(PartageOKia.base64url) else {
            throw PartageOKia.Erreur.partageRetire
        }
        return k
    }
    func telecharger(id: String) async throws -> FluxPartage {
        guard let d = try? Data(contentsOf: dossier.appendingPathComponent("partage-vecteur-test.okia"), options: .mappedIfSafe) else {
            throw PartageOKia.Erreur.partageRetire
        }
        // Une réception lente (une vingtaine de pas d'au moins 200 ms), pour voir la progression.
        let pas = max(65_536, d.count / 20)
        let morceaux = AsyncThrowingStream<Data, Error> { c in
            let tache = Task {
                var i = 0
                while i < d.count {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    c.yield(Data(d[i..<min(d.count, i + pas)]))
                    i += pas
                }
                c.finish()
            }
            c.onTermination = { _ in tache.cancel() }
        }
        return FluxPartage(taille: Int64(d.count), morceaux: morceaux)
    }
}
#endif
