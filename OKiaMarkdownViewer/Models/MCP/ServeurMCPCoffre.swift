import Foundation
import Network
import Security
import Combine

/// 1.6 — Le serveur MCP du coffre (Mac, option Analytic ; TACHES-1.6.md, point B).
///
/// Claude, Codex, Copilot ou un autre assistant lisent le coffre par ses outils : chercher,
/// lister, lire un document par sections, les entités. **Rien que de la lecture** : aucun outil
/// n'écrit, n'efface, ne déplace ni ne sort du coffre, et aucun ne fait de requête réseau.
///
/// - **Coupé par défaut**, ouvert par l'utilisateur dans les réglages.
/// - **Ce Mac seulement** : l'écoute se lie à `127.0.0.1`. Aucune autre machine ne le joint.
/// - **Un jeton** obligatoire (`Authorization: Bearer mdv_…`), gardé dans le trousseau,
///   renouvelable. `initialize` passe sans lui (un client doit pouvoir découvrir le serveur) ;
///   `tools/list` sans jeton rend une liste vide ; un jeton faux est refusé.
/// - **Pas de page web** : une requête qui porte un en-tête `Origin` (un navigateur) est refusée,
///   contre la résolution DNS détournée.
/// - Le journal « Ce que les assistants ont lu » garde l'outil, le document et l'heure, jamais ce
///   qui a été cherché.
///
/// Repris de fornews.ai Agence (`ServeurMCPAgence`) : même transport, mêmes garde-fous.
@MainActor
final class ServeurMCPCoffre: ObservableObject {
    static let partage = ServeurMCPCoffre()
    static let port: UInt16 = 5287
    static let cleReglage = "okia.mcp.actif"

    struct Lecture: Identifiable {
        let id = UUID()
        let date: Date
        let outil: String
        let document: String?
    }

    @Published private(set) var actif = false
    @Published private(set) var erreur: String?
    @Published private(set) var journal: [Lecture] = []
    @Published private(set) var jeton: String = ""

    private var listener: NWListener?
    private var suiviAchat: AnyCancellable?

    var url: String { "http://127.0.0.1:\(Self.port)/mcp" }

    /// Le serveur existe sur Mac ; au simulateur, pour l'essayer (DEBUG).
    static var possible: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #elseif DEBUG
        return ProcessInfo.processInfo.environment["OKIA_MCP"] != nil
        #else
        return false
        #endif
    }

    private init() {
        jeton = Trousseau.lire() ?? ""
    }

    /// Au lancement : le serveur suit le réglage et l'achat de l'option.
    func brancher() {
        #if DEBUG
        // OKIA_MCP : le serveur ouvert au simulateur ; OKIA_MCP_JETON=<jeton> : un jeton connu, pour
        // l'interroger depuis le terminal.
        let env = ProcessInfo.processInfo.environment
        if env["OKIA_MCP"] != nil { UserDefaults.standard.set(true, forKey: Self.cleReglage) }
        if let j = env["OKIA_MCP_JETON"], !j.isEmpty { Trousseau.ecrire(j); jeton = j }
        #endif
        suiviAchat = AchatAnalytic.partage.$achete.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.appliquerReglage() }
        }
    }

    /// Au lancement, et quand le réglage ou l'achat changent.
    func appliquerReglage() {
        let voulu = Self.possible && AchatAnalytic.partage.acces && UserDefaults.standard.bool(forKey: Self.cleReglage)
        if voulu { demarrer() } else { arreter() }
    }

    func demarrer() {
        guard listener == nil else { return }
        if jeton.isEmpty { renouvelerJeton() }
        guard let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let p = NWParameters.tcp
        p.allowLocalEndpointReuse = true
        // Ce Mac seulement : la boucle locale, invisible depuis tout réseau.
        p.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
        do {
            let l = try NWListener(using: p)
            l.stateUpdateHandler = { [weak self] etat in
                Task { @MainActor in
                    guard let self else { return }
                    switch etat {
                    case .ready: self.actif = true; self.erreur = nil
                    case .failed(let e): self.actif = false; self.erreur = "\(e)"
                    case .waiting(let e): self.actif = false; self.erreur = "\(e)"
                    case .cancelled: self.actif = false
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                Task { @MainActor in await self?.gerer(conn) }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            self.erreur = "\(error)"
        }
    }

    func arreter() {
        listener?.cancel()
        listener = nil
        actif = false
    }

    /// Un nouveau jeton : l'ancien ne vaut plus rien, chaque assistant doit recevoir le nouveau.
    func renouvelerJeton() {
        var octets = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, octets.count, &octets)
        let j = "mdv_" + Data(octets).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        Trousseau.ecrire(j)
        jeton = j
    }

    func viderJournal() { journal = [] }

    private func noter(_ outil: String, _ document: String?) {
        journal.insert(Lecture(date: Date(), outil: outil, document: document), at: 0)
        if journal.count > 300 { journal.removeLast(journal.count - 300) }
    }

    /// Comparaison à temps constant : la durée ne trahit pas où un jeton deviné diffère.
    private func jetonValide(_ presente: String?) -> Bool {
        guard let presente, !jeton.isEmpty else { return false }
        let a = Array(presente.utf8), b = Array(jeton.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<a.count { difference |= a[i] ^ b[i] }
        return difference == 0
    }

    // MARK: - Routage

    private func gerer(_ conn: NWConnection) async {
        defer { conn.cancel() }
        guard let brut = await lire(conn), let http = RequeteHTTP(data: brut) else {
            await repondre(conn, 400, MCP.Reponse.echec(.absent, MCP.Code.analyse, "Requête illisible").serialiser())
            return
        }
        if let origine = http.entetes["origin"], !origine.isEmpty {
            await repondre(conn, 403, Data(#"{"error":"origine refusée"}"#.utf8))
            return
        }
        switch (http.methode, http.chemin) {
        case ("POST", "/mcp"):
            await gererMCP(conn, http)
        case ("GET", "/sante"):
            await repondre(conn, 200, Data(#"{"service":"md Viewer — MCP du coffre","etat":"ok"}"#.utf8))
        case ("GET", "/mcp"), ("DELETE", "/mcp"):
            await repondre(conn, 405, Data(#"{"error":"POST uniquement"}"#.utf8))
        default:
            await repondre(conn, 404, Data(#"{"error":"route inconnue"}"#.utf8))
        }
    }

    private func gererMCP(_ conn: NWConnection, _ http: RequeteHTTP) async {
        guard let requete = MCP.Requete.depuis(http.corps) else {
            await repondre(conn, 400, MCP.Reponse.echec(.absent, MCP.Code.analyse, "JSON-RPC illisible").serialiser())
            return
        }
        if requete.estNotification {
            await repondre(conn, 202, Data())
            return
        }
        let reponse: MCP.Reponse
        switch requete.methode {
        case "initialize":
            reponse = .succes(requete.id, [
                "protocolVersion": MCP.versionProtocole,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "md Viewer", "title": "md Viewer — coffre", "version": Self.versionApp],
                "instructions": OutilsMCPCoffre.presentation,
            ])
        case "tools/list":
            if http.jetonPorteur == nil {
                reponse = .succes(requete.id, ["tools": []])
            } else if jetonValide(http.jetonPorteur) {
                reponse = .succes(requete.id, ["tools": OutilsMCPCoffre.catalogue.map(\.declaration)])
            } else {
                reponse = .echec(requete.id, MCP.Code.requeteInvalide, "Jeton refusé")
            }
        case "tools/call":
            guard jetonValide(http.jetonPorteur) else {
                reponse = .echec(requete.id, MCP.Code.requeteInvalide, "Jeton refusé")
                break
            }
            guard let nom = requete.parametres["name"]?.texteOuNil else {
                reponse = .echec(requete.id, MCP.Code.parametresInvalides, "Paramètre « name » manquant")
                break
            }
            guard OutilsMCPCoffre.catalogue.contains(where: { $0.nom == nom }) else {
                reponse = .echec(requete.id, MCP.Code.methodeInconnue, "Outil inconnu : \(nom)")
                break
            }
            var arguments: [String: MCP.Valeur] = [:]
            if case .objet(let o)? = requete.parametres["arguments"] { arguments = o }
            let (resultat, document) = await OutilsMCPCoffre.executer(nom, arguments)
            noter(nom, document)
            reponse = .succes(requete.id, brut: resultat)
        case "ping":
            reponse = .succes(requete.id, [:])
        default:
            reponse = .echec(requete.id, MCP.Code.methodeInconnue, "Méthode inconnue : \(requete.methode)")
        }
        await repondre(conn, 200, reponse.serialiser())
    }

    private static var versionApp: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
    }

    // MARK: - Plomberie

    private func lire(_ conn: NWConnection) async -> Data? {
        var accumule = Data()
        var attendu: Int?
        while true {
            let morceau: Data? = await withCheckedContinuation { suite in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, fini, _ in
                    suite.resume(returning: fini && (data?.isEmpty ?? true) ? nil : data)
                }
            }
            guard let morceau, !morceau.isEmpty else { return accumule.isEmpty ? nil : accumule }
            accumule.append(morceau)
            if accumule.count > 1_048_576 { return accumule }
            if attendu == nil, let fin = accumule.range(of: Data("\r\n\r\n".utf8)) {
                let entete = String(decoding: accumule[..<fin.lowerBound], as: UTF8.self).lowercased()
                let longueur = entete.components(separatedBy: "\r\n")
                    .first { $0.hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                attendu = fin.upperBound + longueur
            }
            if let attendu, accumule.count >= attendu { return accumule }
        }
    }

    private func repondre(_ conn: NWConnection, _ statut: Int, _ corps: Data) async {
        let libelle = [200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden",
                       404: "Not Found", 405: "Method Not Allowed"][statut] ?? "OK"
        var entetes = "HTTP/1.1 \(statut) \(libelle)\r\n"
        entetes += "Content-Type: application/json; charset=utf-8\r\n"
        entetes += "Content-Length: \(corps.count)\r\n"
        entetes += "Connection: close\r\n\r\n"
        var paquet = Data(entetes.utf8)
        paquet.append(corps)
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            conn.send(content: paquet, completion: .contentProcessed { _ in suite.resume() })
        }
    }
}

/// Le jeton du serveur, dans le trousseau de l'appareil (jamais synchronisé).
enum Trousseau {
    private static let service = "ch.ok-ia.markdownviewer.mcp"
    private static let compte = "jeton"

    static func lire() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: compte, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func ecrire(_ jeton: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: compte]
        SecItemDelete(q as CFDictionary)
        var a = q
        a[kSecValueData as String] = Data(jeton.utf8)
        a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(a as CFDictionary, nil)
    }
}
