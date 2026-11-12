import Foundation
import MultipeerConnectivity
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Option Analytic (1.6) — l'iPhone pour télécommande (Patrick, 13/11/2026 : « Advance the slideshow
// on the Mac or iPad from your iPhone, and read your notes on it. Device to device, no server », puis
// « on doit pouvoir annoter la présentation depuis le iphone lorsqu'on pilote le mac ou le ipad :
// faire des cercles, des traits, etc. montrer un pointeur »).
//
// D'appareil à appareil par MultipeerConnectivity (Wi-Fi, Wi-Fi d'appareil à appareil, Bluetooth),
// chiffré, sans serveur. L'appareil qui présente s'annonce pendant le diaporama ; la télécommande le
// trouve, demande à le piloter, et le présentateur accepte. Elle reçoit la diapositive (son image,
// son rang, ses notes) et renvoie : suivante, précédente, des traits et un pointeur, en coordonnées
// de 0 à 1 sur la diapositive.

/// Ce qui passe entre les deux appareils.
struct PaquetTelecommande: Codable {
    var type: String
    var index: Int?
    var total: Int?
    var titre: String?
    var notes: String?
    var image: Data?
    var trait: TraitTelecommande?
    var point: [Double]?
}

struct TraitTelecommande: Codable, Identifiable, Equatable {
    var id: String
    var points: [[Double]]
    /// « crayon » (rouge, fin), « surligneur » (jaune, épais, translucide) ou « cercle » (rouge : une
    /// ellipse inscrite entre le premier et le dernier point).
    var outil: String
}

enum TelecommandeService {
    static let type = "okia-telecom"
    static var nomAppareil: String {
        UIDevice.current.name
    }
}

// MARK: - L'appareil qui présente

@MainActor
final class TelecommandeHote: NSObject, ObservableObject {
    static let partage = TelecommandeHote()

    struct Demande: Identifiable {
        let id = UUID()
        let nom: String
        let reponse: (Bool) -> Void
    }

    @Published var demande: Demande?
    @Published private(set) var connectes: [String] = []
    @Published private(set) var traits: [TraitTelecommande] = []
    @Published private(set) var pointeur: CGPoint?
    /// Suivante, précédente : le diaporama les exécute.
    var surCommande: ((String) -> Void)?
    /// Une télécommande vient de se connecter : le diaporama lui envoie la diapositive en cours.
    var surConnexion: (() -> Void)?

    private let moi = MCPeerID(displayName: TelecommandeService.nomAppareil)
    private var session: MCSession?
    private var annonceur: MCNearbyServiceAdvertiser?
    private var dernierEtat: PaquetTelecommande?

    func demarrer(titre: String) {
        guard annonceur == nil, AchatAnalytic.partage.acces else { return }
        let s = MCSession(peer: moi, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        let a = MCNearbyServiceAdvertiser(peer: moi, discoveryInfo: ["titre": String(titre.prefix(60))],
                                          serviceType: TelecommandeService.type)
        a.delegate = self
        a.startAdvertisingPeer()
        annonceur = a
    }

    func arreter() {
        annonceur?.stopAdvertisingPeer()
        annonceur = nil
        session?.disconnect()
        session = nil
        connectes = []
        traits = []
        pointeur = nil
        demande = nil
        dernierEtat = nil
    }

    /// La diapositive change : la télécommande la reçoit ; les traits de la précédente s'effacent.
    var actif: Bool { !connectes.isEmpty }

    func effacerCalque() {
        if !traits.isEmpty { traits = [] }
        if pointeur != nil { pointeur = nil }
    }

    func envoyerEtat(index: Int, total: Int, titre: String, notes: String, image: Data?) {
        traits = []
        pointeur = nil
        let p = PaquetTelecommande(type: "etat", index: index, total: total, titre: titre, notes: notes, image: image)
        dernierEtat = p
        envoyer(p)
    }

    private func envoyer(_ p: PaquetTelecommande) {
        guard let s = session, !s.connectedPeers.isEmpty, let d = try? JSONEncoder().encode(p) else { return }
        try? s.send(d, toPeers: s.connectedPeers, with: .reliable)
    }

    #if DEBUG
    /// OKIA_TELECOM_ESSAI : ce qu'une télécommande enverrait (essai sans second appareil).
    func essai(_ p: PaquetTelecommande) { recevoir(p) }
    #endif

    fileprivate func recevoir(_ p: PaquetTelecommande) {
        switch p.type {
        case "suivante": surCommande?("next")
        case "precedente": surCommande?("prev")
        case "trait":
            guard let t = p.trait else { return }
            if let i = traits.firstIndex(where: { $0.id == t.id }) { traits[i] = t } else { traits.append(t) }
        case "pointeur":
            pointeur = p.point.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        case "effacer":
            traits = []
        default: break
        }
    }

    fileprivate func connexion(_ nom: String, _ etat: MCSessionState) {
        switch etat {
        case .connected:
            if !connectes.contains(nom) { connectes.append(nom) }
            if let e = dernierEtat { envoyer(e) }
            surConnexion?()
        case .notConnected:
            connectes.removeAll { $0 == nom }
            pointeur = nil
        default: break
        }
    }
}

extension TelecommandeHote: MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let nom = peerID.displayName
        Task { @MainActor in
            // Le présentateur accepte : personne d'autre dans la salle ne pilote son diaporama.
            self.demande = Demande(nom: nom) { [weak self] oui in
                invitationHandler(oui, oui ? self?.session : nil)
                self?.demande = nil
            }
        }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let nom = peerID.displayName
        Task { @MainActor in self.connexion(nom, state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let p = try? JSONDecoder().decode(PaquetTelecommande.self, from: data) else { return }
        Task { @MainActor in self.recevoir(p) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

/// Les traits et le pointeur de la télécommande, par-dessus le diaporama et l'écran du public.
struct CalqueTelecommande: View {
    @ObservedObject var hote = TelecommandeHote.partage

    var body: some View {
        DessinTelecommande(traits: hote.traits, pointeur: hote.pointeur)
    }
}

/// Le dessin lui-même, le même sur l'écran qui présente et sur la télécommande (qui voit ce qu'elle
/// dessine). Coordonnées de 0 à 1.
struct DessinTelecommande: View {
    let traits: [TraitTelecommande]
    let pointeur: CGPoint?

    var body: some View {
        Canvas { ctx, taille in
            for t in traits {
                let pts = t.points.filter { $0.count == 2 }.map { CGPoint(x: $0[0] * taille.width, y: $0[1] * taille.height) }
                guard let premier = pts.first else { continue }
                var chemin = Path()
                if t.outil == "cercle" {
                    let dernier = pts.last ?? premier
                    chemin.addEllipse(in: CGRect(x: min(premier.x, dernier.x), y: min(premier.y, dernier.y),
                                                 width: abs(dernier.x - premier.x), height: abs(dernier.y - premier.y)))
                } else {
                    chemin.move(to: premier)
                    for p in pts.dropFirst() { chemin.addLine(to: p) }
                }
                let surligneur = t.outil == "surligneur"
                ctx.stroke(chemin, with: .color(surligneur ? Color.yellow.opacity(0.45) : Color.red),
                           style: StrokeStyle(lineWidth: (surligneur ? 0.03 : 0.006) * taille.width, lineCap: .round, lineJoin: .round))
            }
            if let p = pointeur {
                let c = CGPoint(x: p.x * taille.width, y: p.y * taille.height)
                let r = taille.width * 0.012
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.4, y: c.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                         with: .color(.red.opacity(0.25)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.red))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - La télécommande

@MainActor
final class TelecommandeClient: NSObject, ObservableObject {
    struct Presentation: Identifiable, Hashable {
        let id: MCPeerID
        let nom: String
        let titre: String
    }

    enum Etat: Equatable { case recherche, connexion(String), connecte(String), refuse }

    @Published private(set) var trouvees: [Presentation] = []
    @Published private(set) var etat: Etat = .recherche
    @Published private(set) var index = 0
    @Published private(set) var total = 0
    @Published private(set) var titre = ""
    @Published private(set) var notes = ""
    @Published private(set) var image: UIImage?
    /// Ce que la télécommande a dessiné sur la diapositive en cours, et son pointeur : elle le montre
    /// aussi sur son écran.
    @Published private(set) var traits: [TraitTelecommande] = []
    @Published private(set) var pointeur: CGPoint?

    private let moi = MCPeerID(displayName: TelecommandeService.nomAppareil)
    private var session: MCSession?
    private var chercheur: MCNearbyServiceBrowser?

    func chercher() {
        let s = MCSession(peer: moi, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        let b = MCNearbyServiceBrowser(peer: moi, serviceType: TelecommandeService.type)
        b.delegate = self
        b.startBrowsingForPeers()
        chercheur = b
        etat = .recherche
    }

    func arreter() {
        chercheur?.stopBrowsingForPeers()
        chercheur = nil
        session?.disconnect()
        session = nil
    }

    func rejoindre(_ p: Presentation) {
        guard let s = session else { return }
        etat = .connexion(p.nom)
        chercheur?.invitePeer(p.id, to: s, withContext: nil, timeout: 60)
    }

    func envoyer(_ p: PaquetTelecommande, fiable: Bool = true) {
        switch p.type {
        case "trait":
            if let t = p.trait {
                if let i = traits.firstIndex(where: { $0.id == t.id }) { traits[i] = t } else { traits.append(t) }
            }
        case "pointeur": pointeur = p.point.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        case "effacer": traits = []
        default: break
        }
        guard let s = session, !s.connectedPeers.isEmpty, let d = try? JSONEncoder().encode(p) else { return }
        try? s.send(d, toPeers: s.connectedPeers, with: fiable ? .reliable : .unreliable)
    }

    fileprivate func trouvee(_ p: Presentation) {
        trouvees.removeAll { $0.id == p.id }
        trouvees.append(p)
    }

    fileprivate func perdue(_ id: MCPeerID) { trouvees.removeAll { $0.id == id } }

    fileprivate func connexion(_ nom: String, _ e: MCSessionState) {
        switch e {
        case .connected: etat = .connecte(nom)
        case .notConnected:
            if case .connexion = etat { etat = .refuse } else { etat = .recherche }
        default: break
        }
    }

    fileprivate func recevoir(_ p: PaquetTelecommande) {
        guard p.type == "etat" else { return }
        // Une autre diapositive : les traits de la précédente s'effacent, comme sur l'écran.
        traits = []
        pointeur = nil
        index = p.index ?? 0
        total = p.total ?? 0
        titre = p.titre ?? ""
        notes = p.notes ?? ""
        image = p.image.flatMap(UIImage.init(data:))
    }
}

extension TelecommandeClient: MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let p = Presentation(id: peerID, nom: peerID.displayName, titre: info?["titre"] ?? "")
        Task { @MainActor in self.trouvee(p) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.perdue(peerID) }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let nom = peerID.displayName
        Task { @MainActor in self.connexion(nom, state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let p = try? JSONDecoder().decode(PaquetTelecommande.self, from: data) else { return }
        Task { @MainActor in self.recevoir(p) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
