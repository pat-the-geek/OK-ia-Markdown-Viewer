// Jeton App Store Connect (ES256) : swift jeton.swift — lit ASC_KEY_ID et ASC_ISSUER_ID dans
// l'environnement (`set -a; . scripts/deploy.env; set +a`) ; la clé reste dans ~/.appstoreconnect.
import Foundation
import CryptoKit
let env = ProcessInfo.processInfo.environment
let kid = env["ASC_KEY_ID"]!, iss = env["ASC_ISSUER_ID"]!
let pem = try! String(contentsOfFile: NSHomeDirectory() + "/.appstoreconnect/private_keys/AuthKey_\(kid).p8", encoding: .utf8)
let cle = try! P256.Signing.PrivateKey(pemRepresentation: pem)
func b64(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
let now = Int(Date().timeIntervalSince1970)
let h = b64(try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": kid, "typ": "JWT"]))
let p = b64(try! JSONSerialization.data(withJSONObject: ["iss": iss, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"]))
let sig = try! cle.signature(for: Data((h + "." + p).utf8))
print(h + "." + p + "." + b64(sig.rawRepresentation))
