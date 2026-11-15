import Foundation
import CryptoKit

/// Les partages chiffrés d'ok-ia.ch (1.5.1, demandé par Patrick le 15/11/2026). Le contrat avec le
/// site est `docs/md-viewer/instructions-partage-qr.md` du dépôt fornews.
///
/// Une page `https://ok-ia.ch/p/<id>/` montre un QR code (ou, sur iPhone et iPad, un bouton) qui
/// ouvre `mdviewer://partage?id=<id>&j=<jeton>`. Le jeton vaut 60 secondes et une seule fois :
/// md Viewer l'échange aussitôt contre la clé du document, télécharge le document chiffré, le
/// déchiffre sur l'appareil (AES-256-GCM) et l'affiche comme un document sans fichier.
///
/// Ce qui ne doit jamais arriver :
/// - aller chercher autre chose que `https://ok-ia.ch` : md Viewer construit lui-même les deux
///   adresses, le lien ne porte que deux identifiants contrôlés ;
/// - écrire la clé ou le lien complet quelque part (journal, documents récents, état restauré) :
///   la clé ne vit que le temps du déchiffrement, et l'on ne journalise rien ici ;
/// - garder une trace réseau : session éphémère, ni cache ni cookie.
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
        /// Échec de l'authentification AES-GCM, ou texte qui n'est pas de l'UTF-8.
        case illisible
        /// Plus de 20 Mo.
        case tropGros

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
            }
        }
    }

    // MARK: Ouvrir

    /// Échange le jeton (tout de suite, avant toute autre chose), télécharge le document et le
    /// déchiffre. Rend le Markdown ; la clé n'existe que dans cette fonction.
    static func ouvrir(_ lien: Lien, transport: TransportPartage) async throws -> String {
        let cle = try await transport.echanger(id: lien.id, jeton: lien.jeton)
        let fichier = try await transport.telecharger(id: lien.id)
        return try dechiffrer(fichier, cle: cle, id: lien.id)
    }

    // MARK: Le format `document.okia`, version 1

    static let entete = Data("OKIA".utf8)
    static let version: UInt8 = 1
    static let tailleMax = 20 * 1024 * 1024

    /// `OKIA` (4 octets), version (1), nonce (12), texte chiffré, étiquette (16). AAD :
    /// `ok-ia.ch/p/<id>` — un fichier déplacé sous un autre identifiant ne s'ouvre pas.
    static func dechiffrer(_ fichier: Data, cle: Data, id: String) throws -> String {
        let f = Data(fichier)   // indices à partir de 0, quel que soit le découpage reçu
        guard f.count >= 5, f.prefix(4) == entete, f[4] == version else { throw Erreur.versionInconnue }
        guard f.count >= 5 + 12 + 16, cle.count == 32 else { throw Erreur.illisible }
        do {
            let nonce = try AES.GCM.Nonce(data: f[5..<17])
            let corps = f[17...]
            let boite = try AES.GCM.SealedBox(nonce: nonce, ciphertext: corps.dropLast(16), tag: corps.suffix(16))
            let clair = try AES.GCM.open(boite, using: SymmetricKey(data: cle),
                                         authenticating: Data("ok-ia.ch/p/\(id)".utf8))
            guard let texte = String(data: clair, encoding: .utf8) else { throw Erreur.illisible }
            return texte
        } catch let e as Erreur {
            throw e
        } catch {
            throw Erreur.illisible
        }
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

/// L'accès réseau du partage, derrière un protocole pour le tester sans serveur.
protocol TransportPartage: Sendable {
    /// `POST https://ok-ia.ch/api/partage/<id>/cle` `{"jeton": …}` → la clé (32 octets).
    func echanger(id: String, jeton: String) async throws -> Data
    /// `GET https://ok-ia.ch/p/<id>/document.okia` → le fichier chiffré.
    func telecharger(id: String) async throws -> Data
}

/// Le vrai transport : toujours `https://ok-ia.ch`, session éphémère, 20 s, 20 Mo au plus.
struct TransportOKia: TransportPartage {
    static let hote = "ok-ia.ch"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 20
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
        let (donnees, reponse) = try await Self.appeler(r)
        switch reponse.statusCode {
        case 200:
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

    func telecharger(id: String) async throws -> Data {
        guard PartageOKia.Lien.valide(id),
              let url = Self.adresse("/p/\(id)/document.okia") else { throw PartageOKia.Erreur.lienInvalide }
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        let (donnees, reponse) = try await Self.appeler(r)
        switch reponse.statusCode {
        case 200:
            guard donnees.count <= PartageOKia.tailleMax else { throw PartageOKia.Erreur.tropGros }
            return donnees
        case 404, 410: throw PartageOKia.Erreur.partageRetire
        case 429: throw PartageOKia.Erreur.tropDeTentatives
        default: throw PartageOKia.Erreur.injoignable
        }
    }

    /// L'appel, sans suivre une redirection hors d'ok-ia.ch, et borné à 20 Mo avant d'être lu.
    private static func appeler(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        if http.expectedContentLength > Int64(PartageOKia.tailleMax) { throw PartageOKia.Erreur.tropGros }
        var donnees = Data()
        do {
            for try await octet in flux {
                donnees.append(octet)
                if donnees.count > PartageOKia.tailleMax { throw PartageOKia.Erreur.tropGros }
            }
        } catch let e as PartageOKia.Erreur {
            throw e
        } catch {
            throw PartageOKia.Erreur.injoignable
        }
        return (donnees, http)
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
/// l'ouverture de bout en bout au simulateur avant que le service du site soit en ligne.
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
    func telecharger(id: String) async throws -> Data {
        guard let d = try? Data(contentsOf: dossier.appendingPathComponent("partage-vecteur-test.okia")) else {
            throw PartageOKia.Erreur.partageRetire
        }
        return d
    }
}
#endif
