import SwiftUI
import Vision
import CoreML

/// Le point fort d'une image, là où une vignette doit se centrer (Patrick, 29/10/2026 : « dans les
/// vignettes le focus doit être mis sur le sujet principal »). Une vignette rognée au centre coupait
/// la tête d'un portrait en pied ou ne gardait que la barbe d'un buste.
///
/// Vision cherche d'abord les visages — un portrait se centre sur eux —, sinon ce qui attire l'œil
/// (saillance). Sans rien de net, un peu au-dessus du milieu : le sujet d'une photo en hauteur y est
/// plus souvent qu'en bas. Calculé une fois par image, à son chargement, hors du fil principal, et
/// gardé en mémoire : la vignette s'affiche d'emblée bien cadrée.
enum Cadrage {
    private static let connus = NSCache<NSString, NSValue>()
    static let parDefaut = CGPoint(x: 0.5, y: 0.4)

    /// Le point déjà calculé pour cette clé (l'adresse de la photo, le chemin du document).
    static func connu(_ cle: String) -> CGPoint? {
        connus.object(forKey: cle as NSString)?.cgPointValue
    }

    /// Vision travaille sur ses propres fils, jamais sur ceux de Swift Concurrency : son appel
    /// synchrone attend un travail qu'il confie lui-même à ces fils. Vingt vignettes de l'analyse du
    /// coffre (iPad, 29/10/2026) en occupaient tous les fils : Vision attendait à jamais, et avec lui
    /// toutes les photos — plus aucune ne s'affichait. Quatre à la fois au plus.
    private static let file: OperationQueue = {
        let f = OperationQueue()
        f.name = "Cadrage"
        f.qualityOfService = .userInitiated
        f.maxConcurrentOperationCount = 4
        return f
    }()

    /// Calcule et garde le point fort ; en coordonnées de l'image, de 0 à 1, depuis le haut à gauche.
    /// Au-delà de trois secondes, la vignette n'attend plus : elle se centre par défaut, et le point
    /// calculé ensuite servira à son prochain affichage.
    @discardableResult
    static func calculer(_ image: UIImage, cle: String) async -> CGPoint {
        if let p = connu(cle) { return p }
        return await withCheckedContinuation { (suite: CheckedContinuation<CGPoint, Never>) in
            let reponse = UneReponse(suite)
            file.addOperation {
                let p = connu(cle) ?? image.cgImage.flatMap(pointFort) ?? parDefaut
                connus.setObject(NSValue(cgPoint: p), forKey: cle as NSString)
                reponse.donner(p)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { reponse.donner(parDefaut) }
        }
    }

    /// Reprend une attente une seule fois : du calcul ou du délai, le premier qui répond.
    private final class UneReponse: @unchecked Sendable {
        private var suite: CheckedContinuation<CGPoint, Never>?
        private let verrou = NSLock()
        init(_ suite: CheckedContinuation<CGPoint, Never>) { self.suite = suite }
        func donner(_ p: CGPoint) {
            verrou.lock(); let s = suite; suite = nil; verrou.unlock()
            s?.resume(returning: p)
        }
    }

    private static func pointFort(_ cg: CGImage) -> CGPoint? {
        let gestionnaire = VNImageRequestHandler(cgImage: cg, options: [:])
        let visages = VNDetectFaceRectanglesRequest()
        let saillance = VNGenerateAttentionBasedSaliencyImageRequest()
        #if targetEnvironment(simulator)
        // Le simulateur n'a ni GPU ni moteur neuronal pour Vision (« Failed to create espresso
        // context ») : sans le processeur, aucune image n'y était cadrée — ni les captures App Store.
        if let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) {
            for requete in [visages, saillance] as [VNRequest] {
                for etape in (try? requete.supportedComputeStageDevices)?.keys.map({ $0 }) ?? [VNComputeStage.main] {
                    requete.setComputeDevice(cpu, for: etape)
                }
            }
        }
        #endif
        try? gestionnaire.perform([visages, saillance])
        // Les visages assez grands pour compter : un passant au fond ne déplace pas le cadre.
        let grands = (visages.results ?? []).map(\.boundingBox).filter { $0.width >= 0.04 }
        if let union = grands.dropFirst().reduce(grands.first, { $0?.union($1) }) {
            // Le cadre de Vision va des sourcils au menton : on remonte d'un cinquième de sa hauteur
            // pour garder le front et les cheveux.
            return CGPoint(x: union.midX, y: 1 - (union.midY + union.height * 0.2))
        }
        let zones = (saillance.results?.first?.salientObjects ?? []).map(\.boundingBox)
        if let union = zones.dropFirst().reduce(zones.first, { $0?.union($1) }) {
            // Vision part du bas ; un sujet en hauteur (statue, personne debout) est cadré sur son
            // haut plutôt que son milieu.
            let y = union.height > 0.6 ? union.maxY - union.height * 0.3 : union.midY
            return CGPoint(x: union.midX, y: 1 - y)
        }
        return nil
    }
}

/// Une image qui remplit son cadre en restant centrée, autant que les bords le permettent, sur son
/// point fort (`Cadrage`) — à la place de `.scaledToFill()`, qui centre toujours.
struct ImageRecadree: View {
    let image: UIImage
    let cle: String

    var body: some View {
        GeometryReader { g in
            let f = Cadrage.connu(cle) ?? Cadrage.parDefaut
            let k = max(g.size.width / max(image.size.width, 1), g.size.height / max(image.size.height, 1))
            let w = image.size.width * k, h = image.size.height * k
            Image(uiImage: image)
                .resizable()
                .frame(width: w, height: h)
                .offset(x: min(0, max(g.size.width - w, g.size.width / 2 - f.x * w)),
                        y: min(0, max(g.size.height - h, g.size.height / 2 - f.y * h)))
        }
    }
}
