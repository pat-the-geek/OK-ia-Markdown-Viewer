// Banc des partages chiffrés d'ok-ia.ch (`PartageOKia.swift`), sans serveur.
// Le vecteur `partage-vecteur-test.okia` + `.json` vient du dépôt fornews (docs/md-viewer/) :
// le déchiffrement doit redonner exactement `texte_clair`.
// Lancer : tools/BancPartage/banc.sh
import Foundation
import CryptoKit

/// `tr` de l'app, sans le catalogue : la clé française suffit au banc.
func tr(_ key: String, _ args: CVarArg...) -> String { args.isEmpty ? key : String(format: key, arguments: args) }

var echecs = 0
func verifie(_ condition: Bool, _ nom: String) {
    print((condition ? "✓ " : "✗ ") + nom)
    if !condition { echecs += 1 }
}

let ici = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let fichier = try Data(contentsOf: ici.appendingPathComponent("partage-vecteur-test.okia"))
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: ici.appendingPathComponent("partage-vecteur-test.json"))) as! [String: Any]
let id = json["id"] as! String
let cle = PartageOKia.base64url(json["k"] as! String)!
let attendu = json["texte_clair"] as! String

// 1. Le vecteur.
verifie(cle.count == 32, "la clé du vecteur fait 32 octets")
guard case .document(let clair) = try PartageOKia.dechiffrer(fichier, cle: cle, id: id) else { fatalError("version 1 attendue") }
verifie(clair == attendu, "le vecteur redonne exactement texte_clair")
verifie(PartageOKia.titre(clair) == "Partage de démonstration", "le titre est le premier #")

// 2. Ce qui doit échouer au déchiffrement.
func erreur(_ bloc: () throws -> Void) -> PartageOKia.Erreur? {
    do { try bloc(); return nil } catch let e as PartageOKia.Erreur { return e } catch { return nil }
}
var autreCle = cle; autreCle[0] ^= 1
verifie(erreur { _ = try PartageOKia.dechiffrer(fichier, cle: autreCle, id: id) } == .illisible, "mauvaise clé → illisible")
verifie(erreur { _ = try PartageOKia.dechiffrer(fichier, cle: cle, id: "BBECAwQFBgcICQoLDA0ODw") } == .illisible, "autre identifiant (AAD) → illisible")
var abime = fichier; abime[abime.count - 20] ^= 1
verifie(erreur { _ = try PartageOKia.dechiffrer(abime, cle: cle, id: id) } == .illisible, "texte chiffré modifié → illisible")
var v3 = fichier; v3[4] = 3
verifie(erreur { _ = try PartageOKia.dechiffrer(v3, cle: cle, id: id) } == .versionInconnue, "version 3 → version inconnue")
var v2 = fichier; v2[4] = 2
verifie(erreur { _ = try PartageOKia.dechiffrer(v2, cle: cle, id: id) } == .illisible, "document de version 1 relu en version 2 → illisible")
verifie(erreur { _ = try PartageOKia.dechiffrer(Data("PDF-1.7".utf8), cle: cle, id: id) } == .versionInconnue, "autre en-tête → version inconnue")
verifie(erreur { _ = try PartageOKia.dechiffrer(fichier.prefix(20), cle: cle, id: id) } == .illisible, "fichier tronqué → illisible")
verifie((try? PartageOKia.dechiffrer(fichier[0...], cle: cle, id: id)) == .document(attendu), "tranche de Data (indices non nuls) acceptée")

// 2 bis. La version 2 : un fichier, avec son en-tête JSON dans le chiffré.
func conteneur(_ clair: Data, version: UInt8 = 2, id: String = id) -> Data {
    let boite = try! AES.GCM.seal(clair, using: SymmetricKey(data: cle), authenticating: Data("ok-ia.ch/p/\(id)".utf8))
    return Data("OKIA".utf8) + [version] + Data(boite.nonce) + boite.ciphertext + boite.tag
}
func v2(_ entete: String, _ octets: Data) -> Data { conteneur(Data(entete.utf8) + [0x0A] + octets) }
// Des octets qui contiennent eux-mêmes des sauts de ligne et du JSON : seul le PREMIER compte.
let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x0A, 0x0A, 0x00, 0xFF]) + Data("{\"nom\":\"x\"}\n".utf8) + Data((0..<5000).map { UInt8($0 % 251) })
let bon = v2(#"{"nom":"archive.zip","type":"application/zip","taille":\#(zip.count)}"#, zip)
if case .fichier(let f) = try PartageOKia.dechiffrer(bon, cle: cle, id: id) {
    verifie(f.octets == zip, "version 2 : les octets du fichier, intacts (sauts de ligne compris)")
    verifie(f.nom == "archive.zip" && f.type == "application/zip", "version 2 : le nom et le type de l'en-tête")
} else { verifie(false, "version 2 : un fichier") }
verifie(erreur { _ = try PartageOKia.dechiffrer(bon, cle: cle, id: "BBECAwQFBgcICQoLDA0ODw") } == .illisible, "version 2 sous un autre identifiant → illisible")
verifie(erreur { _ = try PartageOKia.dechiffrer(v2(#"{"nom":"a.zip","taille":\#(zip.count + 1)}"#, zip), cle: cle, id: id) } == .illisible, "version 2 : taille annoncée fausse → illisible")
verifie(erreur { _ = try PartageOKia.dechiffrer(conteneur(zip), cle: cle, id: id) } == .illisible, "version 2 sans en-tête JSON → illisible")
verifie(erreur { _ = try PartageOKia.dechiffrer(conteneur(Data(repeating: 0x20, count: 5000)), cle: cle, id: id) } == .illisible, "version 2 : pas de saut de ligne dans les 4 Kio → illisible")
if case .fichier(let f)? = try? PartageOKia.dechiffrer(v2(#"{"nom":"../../.ssh/id","taille":3}"#, Data("abc".utf8)), cle: cle, id: id) {
    verifie(f.nom == "sshid", "version 2 : nom avec ../ rendu sûr (\(f.nom))")
    verifie(f.type == "application/octet-stream", "version 2 : type absent → application/octet-stream")
} else { verifie(false, "version 2 : nom piégé accepté puis nettoyé") }
verifie(PartageOKia.nomSur("../../etc/passwd") == "etcpasswd", "nomSur : ni / ni .. (\(PartageOKia.nomSur("../../etc/passwd")))")
verifie(PartageOKia.nomSur(".cache") == "cache", "nomSur : pas de fichier caché")
verifie(PartageOKia.nomSur("a\u{0}b\nc:d\\e.zip") == "abcde.zip", "nomSur : contrôles, :, \\ retirés")
verifie(PartageOKia.nomSur("   ") == "partage", "nomSur : vide → partage")
verifie(PartageOKia.nomSur(String(repeating: "é", count: 300) + ".zip").hasSuffix(".zip"), "nomSur : nom trop long tronqué, extension gardée")
verifie(PartageOKia.nomSur("Rapport 2026 — été.zip") == "Rapport 2026 — été.zip", "nomSur : un nom ordinaire est gardé tel quel")

// 3. Les liens.
func lien(_ s: String) -> PartageOKia.Lien? { URL(string: s).flatMap(PartageOKia.Lien.init(url:)) }
verifie(lien(json["lien_exemple"] as! String) == lien("mdviewer://partage?id=\(id)&j=AAAAAAAAAAAAAAAAAAAAAA"), "le lien d'exemple est reconnu")
verifie(lien("mdviewer://partage?id=\(id)&j=AAAA") == nil, "jeton trop court refusé")
verifie(lien("mdviewer://partage?id=\(id)") == nil, "jeton absent refusé")
verifie(lien("mdviewer://partage?id=../../etc/passwd000000&j=AAAAAAAAAAAAAAAAAAAAAA") == nil, "identifiant avec / et . refusé")
verifie(lien("mdviewer://partage?id=AAECAwQFBgcICQoLDA0OD%2F&j=AAAAAAAAAAAAAAAAAAAAAA") == nil, "identifiant avec %2F refusé")
verifie(lien("mdviewer://partage?id=\(id)&j=AAAAAAAAAAAAAAAAAAAAAA&url=https://evil.example/x") != nil
        && lien("mdviewer://partage?id=\(id)&j=AAAAAAAAAAAAAAAAAAAAAA&url=https://evil.example/x")!.id == id,
        "un paramètre url en plus est ignoré (jamais suivi)")
verifie(lien("mdviewer://autre?id=\(id)&j=AAAAAAAAAAAAAAAAAAAAAA") == nil, "autre action refusée")

// 4. L'échange et le téléchargement, avec un faux transport.
actor Journal { var appels: [String] = []; func note(_ s: String) { appels.append(s) } }
struct Faux: TransportPartage {
    let statutCle: Int
    let fichier: Data
    let journal: Journal
    func echanger(id: String, jeton: String) async throws -> Data {
        await journal.note("cle")
        switch statutCle {
        case 200: return cle
        case 410: throw PartageOKia.Erreur.codeExpire
        case 404: throw PartageOKia.Erreur.partageRetire
        case 429: throw PartageOKia.Erreur.tropDeTentatives
        default: throw PartageOKia.Erreur.injoignable
        }
    }
    func telecharger(id: String, progression: @escaping @Sendable (Double) -> Void) async throws -> Data {
        await journal.note("document"); progression(1); return fichier
    }
}
let l = lien("mdviewer://partage?id=\(id)&j=AAAAAAAAAAAAAAAAAAAAAA")!
let j = Journal()
let md = try await PartageOKia.ouvrir(l, transport: Faux(statutCle: 200, fichier: fichier, journal: j))
verifie(md == .document(attendu), "ouvrir (200) rend le Markdown")
verifie(await j.appels == ["cle", "document"], "le jeton est échangé avant le téléchargement")
for (statut, attenduErr) in [(410, PartageOKia.Erreur.codeExpire), (404, .partageRetire), (429, .tropDeTentatives), (500, .injoignable)] {
    let jj = Journal()
    var e: PartageOKia.Erreur?
    do { _ = try await PartageOKia.ouvrir(l, transport: Faux(statutCle: statut, fichier: fichier, journal: jj)) }
    catch let x as PartageOKia.Erreur { e = x }
    verifie(e == attenduErr, "jeton → \(statut) : \(attenduErr.errorDescription ?? "")")
    verifie(await jj.appels == ["cle"], "  … et le document n'est pas demandé")
}

print(echecs == 0 ? "\nTout est bon." : "\n\(echecs) échec(s).")
exit(echecs == 0 ? 0 : 1)
