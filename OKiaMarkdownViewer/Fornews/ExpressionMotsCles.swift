// ─────────────────────────────────────────────────────────────────────────────────────────────
// Copie de fornews.ai — FornewsCore/Sources/FornewsModels/ExpressionMotsCles.swift (commit fda62384, 28/10/2026).
// Option Analytic (1.4) : le même algorithme que fornews. ⛔ Ne pas modifier ici : corriger dans
// fornews, puis relancer scripts/copier-fornews.sh.
// Seule retouche : les `import Fornews…` retirés.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

/// Arbre logique d'une règle de mots-clés (ET / OU / NON).
///
/// Value type : **jamais** persisté tel quel — sérialisé en JSON dans
/// `RegleMotsCles.expressionJSON` (voir `init(json:)` / `jsonString()`).
public indirect enum ExpressionMotsCles: Codable, Equatable, Sendable {
    case terme(String)
    case et([ExpressionMotsCles])
    case ou([ExpressionMotsCles])
    case non(ExpressionMotsCles)

    // MARK: — Peut-elle servir de règle de PÊCHE ?

    /// Nombre de termes non vides en position **positive** (hors négation).
    ///
    /// ⚠️ Sert à distinguer une expression qui SÉLECTIONNE de une qui ne fait qu'exclure. Deux
    /// pièges de la sémantique d'évaluation la rendent nécessaire :
    /// - **`.et([])` vaut `true`** (`allSatisfy` sur une liste vide) — une expression sans terme
    ///   matcherait donc TOUS les articles ;
    /// - **`non(X)` seul** attrape tout **sauf** X, ce qui est un filet à peu près aussi large.
    ///
    /// Les deux sont inoffensifs comme **filtre** derrière une entité (au pire ils ne filtrent
    /// rien), et désastreux comme **règle de pêche**, où plus aucune entité ne borne la capture.
    public var termesPositifs: Int {
        switch self {
        case .terme(let t): return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
        case .et(let xs), .ou(let xs): return xs.reduce(0) { $0 + $1.termesPositifs }
        // Ce qui est nié ne sélectionne rien : « non(guerre) » ne dit pas de quoi on parle.
        case .non: return 0
        }
    }

    /// L'expression peut-elle **pêcher** seule, sans entité pour la borner ?
    ///
    /// Il lui faut au moins un terme qui SÉLECTIONNE. Une règle qui ne fait qu'exclure décrit ce
    /// qu'on ne veut pas — elle ne dit jamais ce qu'on suit.
    public var peutPecher: Bool { termesPositifs > 0 }

    // MARK: Codable (union étiquetée : {"terme": "..."} / {"et": [...]} / ...)

    private enum CodingKeys: String, CodingKey { case terme, et, ou, non }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try c.decodeIfPresent(String.self, forKey: .terme) {
            self = .terme(t)
        } else if let e = try c.decodeIfPresent([ExpressionMotsCles].self, forKey: .et) {
            self = .et(e)
        } else if let o = try c.decodeIfPresent([ExpressionMotsCles].self, forKey: .ou) {
            self = .ou(o)
        } else if let n = try c.decodeIfPresent(ExpressionMotsCles.self, forKey: .non) {
            self = .non(n)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Nœud ExpressionMotsCles inconnu"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terme(let t): try c.encode(t, forKey: .terme)
        case .et(let e):    try c.encode(e, forKey: .et)
        case .ou(let o):    try c.encode(o, forKey: .ou)
        case .non(let n):   try c.encode(n, forKey: .non)
        }
    }

    // MARK: Sérialisation pratique

    public init(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "JSON non UTF-8"))
        }
        self = try JSONDecoder().decode(ExpressionMotsCles.self, from: data)
    }

    public func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
