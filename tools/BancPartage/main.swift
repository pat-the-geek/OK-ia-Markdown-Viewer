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
var v4 = fichier; v4[4] = 4
verifie(erreur { _ = try PartageOKia.dechiffrer(v4, cle: cle, id: id) } == .versionInconnue, "version 4 → version inconnue")
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
    func telecharger(id: String) async throws -> FluxPartage {
        await journal.note("document"); return FluxPartage(fichier)
    }
}
let l = lien("mdviewer://partage?id=\(id)&j=AAAAAAAAAAAAAAAAAAAAAA")!
let j = Journal()
let md = try await PartageOKia.ouvrir(l, transport: Faux(statutCle: 200, fichier: fichier, journal: j))
if case .document(let t) = md { verifie(t == attendu, "ouvrir (200) rend le Markdown") } else { verifie(false, "ouvrir (200) rend le Markdown") }
verifie(await j.appels == ["cle", "document"], "le jeton est échangé avant le téléchargement")
for (statut, attenduErr) in [(410, PartageOKia.Erreur.codeExpire), (404, .partageRetire), (429, .tropDeTentatives), (500, .injoignable)] {
    let jj = Journal()
    var e: PartageOKia.Erreur?
    do { _ = try await PartageOKia.ouvrir(l, transport: Faux(statutCle: statut, fichier: fichier, journal: jj)) }
    catch let x as PartageOKia.Erreur { e = x }
    verifie(e == attenduErr, "jeton → \(statut) : \(attenduErr.errorDescription ?? "")")
    verifie(await jj.appels == ["cle"], "  … et le document n'est pas demandé")
}

// 5. La version 3 : découpée, déchiffrée au fil de l'eau.
func u32(_ v: Int) -> Data { Data([UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)]) }
func boite(_ clair: Data, _ aad: String) -> Data {
    let b = try! AES.GCM.seal(clair, using: SymmetricKey(data: cle), authenticating: Data(aad.utf8))
    return Data(b.nonce) + b.ciphertext + b.tag
}
/// Un conteneur v3 ; `retouche` modifie la liste des morceaux (0 = l'en-tête) avant l'assemblage.
func v3(_ octets: Data, nom: String = "gros.zip", M: Int = 65_536, Nclair: Int? = nil, taille: Int? = nil,
        retouche: (inout [Data]) -> Void = { _ in }) -> Data {
    let N = octets.isEmpty ? 0 : (octets.count + M - 1) / M
    let entete = Data(#"{"nom":"\#(nom)","type":"application/zip","taille":\#(taille ?? octets.count)}"#.utf8)
    var morceaux = [boite(entete, "ok-ia.ch/p/\(id)#0/\(N)")]
    for i in 0..<N {
        morceaux.append(boite(octets[(i * M)..<min(octets.count, (i + 1) * M)], "ok-ia.ch/p/\(id)#\(i + 1)/\(N)"))
    }
    retouche(&morceaux)
    return Data("OKIA".utf8) + [3] + u32(Nclair ?? N) + u32(M) + u32(entete.count) + morceaux.reduce(Data(), +)
}
func recevoir(_ d: Data, morceau: Int = 65_536) async -> Result<PartageOKia.Recu, PartageOKia.Erreur> {
    do { return .success(try await PartageOKia.recevoir(FluxPartage(d, morceau: morceau), cle: cle, id: id)) }
    catch let e as PartageOKia.Erreur { return .failure(e) } catch { return .failure(.injoignable) }
}
func temporaires() -> Int {
    ((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
        .filter { $0.hasPrefix("partage-") }.count
}
func erreurV3(_ d: Data, morceau: Int = 65_536) async -> PartageOKia.Erreur? {
    if case .failure(let e) = await recevoir(d, morceau: morceau) { return e }
    if case .success(.fichier(let f)) = await recevoir(d, morceau: morceau) { f.effacer() }
    return nil
}
let petit = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })
if case .success(.fichier(let f)) = await recevoir(v3(petit), morceau: 7) {
    verifie((try? Data(contentsOf: f.url)) == petit, "v3 : 200 Ko en 4 morceaux, reçus 7 octets à la fois, intacts")
    verifie(f.url.lastPathComponent == "gros.zip", "v3 : le nom de l'en-tête chiffré")
    f.effacer()
} else { verifie(false, "v3 : 200 Ko reçus") }
if case .success(.fichier(let f)) = await recevoir(v3(Data())) {
    verifie((try? Data(contentsOf: f.url)) == Data(), "v3 : un fichier vide (N = 0)")
    f.effacer()
} else { verifie(false, "v3 : un fichier vide") }
let avant = temporaires()
verifie(await erreurV3(v3(petit).dropLast(100)) == .illisible, "v3 : tronqué → illisible")
verifie(await erreurV3(v3(petit) { m in m.removeLast() }) == .illisible, "v3 : dernier morceau retiré → illisible")
verifie(await erreurV3(v3(petit) { m in m.swapAt(1, 2) }) == .illisible, "v3 : deux morceaux échangés → illisible")
verifie(await erreurV3(v3(petit, Nclair: 3)) == .illisible, "v3 : N changé en clair → illisible")
verifie(await erreurV3(v3(petit) + Data([0])) == .illisible, "v3 : un octet après le dernier morceau → illisible")
verifie(await erreurV3(v3(petit, taille: 199_999)) == .illisible, "v3 : taille annoncée fausse → illisible")
verifie(await erreurV3(v3(petit, M: 4096)) == .illisible, "v3 : morceaux de moins de 64 Kio → illisible")
verifie(await erreurV3(v3(Data(), taille: 600 * 1024 * 1024)) == .tropGros, "v3 : 600 Mo annoncés → trop volumineux")
verifie(await erreurV3(v3(petit) { m in m[3][20] ^= 1 }) == .illisible, "v3 : un morceau modifié → illisible")
verifie(temporaires() == avant, "v3 : aucune copie déchiffrée ne reste après une erreur")
// Plus de 50 Mo : la borne des versions 1 et 2 ne s'applique pas à la version 3.
let gros = Data(count: 60 * 1024 * 1024)
let debut = Date()
if case .success(.fichier(let f)) = await recevoir(v3(gros, M: 4 * 1024 * 1024), morceau: 262_144) {
    let t = (try? FileManager.default.attributesOfItem(atPath: f.url.path)[.size] as? Int) ?? -1
    verifie(t == gros.count, String(format: "v3 : 60 Mo en morceaux de 4 Mio, écrits au fil de l'eau (%.1f s)", Date().timeIntervalSince(debut)))
    f.effacer()
} else { verifie(false, "v3 : 60 Mo reçus") }

print(echecs == 0 ? "\nTout est bon." : "\n\(echecs) échec(s).")
exit(echecs == 0 ? 0 : 1)
