import Foundation

/// 1.6 — JSON-RPC 2.0 et les types MCP, le strict nécessaire au transport « Streamable HTTP ».
///
/// Repris du cœur MCP de fornews.ai Agence (`FornewsServeurAgence/…/ProtocoleMCP.swift`), sans
/// les rôles : le serveur du coffre n'a qu'un jeton, et rien que des outils de lecture. Le
/// protocole est un standard : le recopier ne crée pas de dépendance entre les deux apps.
enum MCP {

    static let versionProtocole = "2025-03-26"

    /// Une valeur JSON quelconque : les arguments d'outil en sont.
    indirect enum Valeur: Sendable, Equatable {
        case nul
        case booleen(Bool)
        case nombre(Double)
        case texte(String)
        case tableau([Valeur])
        case objet([String: Valeur])

        var texteOuNil: String? { if case .texte(let t) = self { return t }; return nil }
        var entierOuNil: Int? {
            if case .nombre(let n) = self { return Int(n) }
            if case .texte(let t) = self { return Int(t) }
            return nil
        }
        var booleenOuNil: Bool? { if case .booleen(let b) = self { return b }; return nil }

        static func depuis(_ brut: Any) -> Valeur {
            switch brut {
            case is NSNull: return .nul
            // ⚠️ Pas de `case let b as Bool` : le pont Objective-C convertit `NSNumber(1) as? Bool`,
            //    et `limit: 1` devenait un booléen (fornews, 20/09/2026). Seul `CFGetTypeID`
            //    distingue un vrai booléen JSON d'un nombre.
            case let n as NSNumber:
                if CFGetTypeID(n) == CFBooleanGetTypeID() { return .booleen(n.boolValue) }
                return .nombre(n.doubleValue)
            case let s as String: return .texte(s)
            case let a as [Any]: return .tableau(a.map(Valeur.depuis))
            case let o as [String: Any]: return .objet(o.mapValues(Valeur.depuis))
            default: return .nul
            }
        }
    }

    /// L'identifiant d'une requête : un nombre, une chaîne, ou rien (une notification).
    enum Identifiant: Sendable, Equatable {
        case nombre(Double), texte(String), absent

        static func depuis(_ brut: Any?) -> Identifiant {
            if let n = brut as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return .nombre(n.doubleValue) }
            if let t = brut as? String { return .texte(t) }
            return .absent
        }
        var pourJSON: Any {
            switch self {
            case .nombre(let n): return n == n.rounded() ? Int(n) : n
            case .texte(let t): return t
            case .absent: return NSNull()
            }
        }
    }

    struct Requete: Sendable {
        var id: Identifiant
        var methode: String
        var parametres: [String: Valeur]

        static func depuis(_ data: Data) -> Requete? {
            guard let brut = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let methode = brut["method"] as? String else { return nil }
            let params = (brut["params"] as? [String: Any]).map { $0.mapValues(Valeur.depuis) } ?? [:]
            return Requete(id: Identifiant.depuis(brut["id"]), methode: methode, parametres: params)
        }

        /// Une notification n'attend aucune réponse : lui en envoyer une fait échouer certains
        /// clients.
        var estNotification: Bool { id == .absent }
    }

    struct Reponse {
        var id: Identifiant
        var resultat: [String: Any]?
        var erreur: (code: Int, message: String)?
        var resultatBrut: Data?

        static func succes(_ id: Identifiant, _ resultat: [String: Any]) -> Reponse {
            Reponse(id: id, resultat: resultat, erreur: nil, resultatBrut: nil)
        }
        static func succes(_ id: Identifiant, brut: Data) -> Reponse {
            Reponse(id: id, resultat: nil, erreur: nil, resultatBrut: brut)
        }
        static func echec(_ id: Identifiant, _ code: Int, _ message: String) -> Reponse {
            Reponse(id: id, resultat: nil, erreur: (code, message), resultatBrut: nil)
        }

        func serialiser() -> Data {
            if let brut = resultatBrut {
                var doc = Data(#"{"jsonrpc":"2.0","id":"#.utf8)
                doc.append((try? JSONSerialization.data(withJSONObject: [id.pourJSON], options: [.fragmentsAllowed]))
                    .map { $0.dropFirst().dropLast() } ?? Data("null".utf8))
                doc.append(Data(#","result":"#.utf8))
                doc.append(brut)
                doc.append(Data("}".utf8))
                return doc
            }
            var corps: [String: Any] = ["jsonrpc": "2.0"]
            corps["id"] = id.pourJSON
            if let erreur {
                corps["error"] = ["code": erreur.code, "message": erreur.message]
            } else {
                corps["result"] = resultat ?? [:]
            }
            return (try? JSONSerialization.data(withJSONObject: corps, options: [.sortedKeys]))
                ?? Data(#"{"jsonrpc":"2.0","error":{"code":-32603,"message":"serialisation"}}"#.utf8)
        }
    }

    enum Code {
        static let analyse = -32700, requeteInvalide = -32600
        static let methodeInconnue = -32601, parametresInvalides = -32602
        static let interne = -32603
    }

    /// La déclaration d'un outil, telle que `tools/list` la rend. Tous sont en lecture seule.
    struct Outil: Sendable {
        var nom: String
        var titre: String
        var description: String
        var proprietes: [String: Champ]
        var requis: [String]

        init(_ nom: String, _ titre: String, _ description: String,
             proprietes: [String: Champ] = [:], requis: [String] = []) {
            self.nom = nom
            self.titre = titre
            self.description = description
            self.proprietes = proprietes
            self.requis = requis
        }

        var declaration: [String: Any] {
            [
                "name": nom,
                "title": titre,
                "description": description,
                "inputSchema": ["type": "object", "properties": proprietes.mapValues(\.json), "required": requis] as [String: Any],
                // Les annotations MCP : rien ne s'écrit, rien ne s'efface, rien ne sort du coffre.
                "annotations": ["title": titre, "readOnlyHint": true, "destructiveHint": false,
                                "idempotentHint": true, "openWorldHint": false] as [String: Any],
            ]
        }
    }

    struct Champ: Sendable {
        enum Genre: String, Sendable { case texte = "string", entier = "integer", booleen = "boolean" }
        var genre: Genre
        var description: String
        var defaut: Int?

        static func texte(_ d: String) -> Champ { Champ(genre: .texte, description: d, defaut: nil) }
        static func entier(_ d: String, defaut: Int? = nil) -> Champ { Champ(genre: .entier, description: d, defaut: defaut) }
        static func booleen(_ d: String) -> Champ { Champ(genre: .booleen, description: d, defaut: nil) }

        var json: [String: Any] {
            var o: [String: Any] = ["type": genre.rawValue, "description": description]
            if let defaut { o["default"] = defaut }
            return o
        }
    }

    /// Le résultat d'un outil : un contenu textuel (le JSON de la réponse).
    static func contenu(_ objet: [String: Any]) -> Data {
        let json = (try? JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return serialiser(["content": [["type": "text", "text": json]]])
    }

    /// Une erreur d'outil n'est pas une erreur de protocole : elle se rend dans le résultat, avec
    /// `isError`, et le client garde sa session.
    static func erreurOutil(_ message: String) -> Data {
        serialiser(["content": [["type": "text", "text": message]], "isError": true])
    }

    static func serialiser(_ objet: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys, .withoutEscapingSlashes]))
            ?? Data("{}".utf8)
    }
}

/// Une requête HTTP lue sur la connexion (reprise de fornews Agence, `RequeteHTTP`).
struct RequeteHTTP: Sendable {
    let methode: String
    let chemin: String
    /// En minuscules : les noms d'en-tête sont insensibles à la casse.
    let entetes: [String: String]
    let corps: Data

    init?(data: Data) {
        let separateur = Data("\r\n\r\n".utf8)
        let enTete: Data, corpsBrut: Data
        if let plage = data.range(of: separateur) {
            enTete = data.subdata(in: data.startIndex..<plage.lowerBound)
            corpsBrut = plage.upperBound < data.endIndex ? data.subdata(in: plage.upperBound..<data.endIndex) : Data()
        } else {
            enTete = data
            corpsBrut = Data()
        }
        guard let texte = String(data: enTete, encoding: .utf8) else { return nil }
        let lignes = texte.components(separatedBy: "\r\n")
        guard let premiere = lignes.first, !premiere.isEmpty else { return nil }
        var lues: [String: String] = [:]
        for ligne in lignes.dropFirst() where !ligne.isEmpty {
            guard let sep = ligne.firstIndex(of: ":") else { continue }
            let cle = ligne[..<sep].trimmingCharacters(in: .whitespaces).lowercased()
            if !cle.isEmpty { lues[cle] = ligne[ligne.index(after: sep)...].trimmingCharacters(in: .whitespaces) }
        }
        let parties = premiere.components(separatedBy: " ")
        guard parties.count >= 2 else { return nil }
        methode = parties[0].uppercased()
        chemin = parties[1].components(separatedBy: "?").first ?? parties[1]
        entetes = lues
        corps = corpsBrut
    }

    /// Le jeton présenté (`Authorization: Bearer …`).
    var jetonPorteur: String? {
        guard let a = entetes["authorization"], a.lowercased().hasPrefix("bearer ") else { return nil }
        let j = a.dropFirst("bearer ".count).trimmingCharacters(in: .whitespaces)
        return j.isEmpty ? nil : j
    }
}
