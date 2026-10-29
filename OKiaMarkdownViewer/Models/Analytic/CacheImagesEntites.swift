import UIKit
import ImageIO
import CryptoKit

/// Option Analytic (1.4) — les photos des entités, gardées sur l'appareil (Patrick, 27/10/2026 :
/// « est-ce que tu as mis en œuvre un cache pour les images d'entité ? »).
///
/// Le cache des fiches (`CacheEntites`) ne garde que l'adresse de la photo ; `AsyncImage` la
/// retéléchargeait au gré du petit cache de `URLSession` — en faisant défiler la galerie, en rouvrant
/// une fiche — et hors ligne, il n'y avait plus de photo. Ici :
/// - **en mémoire** (`NSCache`), les images déjà décodées, pour le défilement ;
/// - **sur le disque**, dans les caches de l'app (`Caches/Analytic/Images`, que le système peut
///   purger : tout se retélécharge), les octets reçus de Wikimedia Commons, 60 Mo au plus — les moins
///   récemment vues s'en vont d'abord ;
/// - **une seule requête** par adresse, même si dix vignettes la demandent à la fois.
///
/// Pas d'expiration : quand la photo d'une entité change sur Wikidata, son adresse change aussi
/// (le nom du fichier de Commons). Une photo est décodée à 720 pixels au plus (la fiche, 240 points
/// en @3x) : un logo de plusieurs milliers de pixels ne coûte pas plus qu'une vignette.
final class CacheImagesEntites: @unchecked Sendable {
    static let partage = CacheImagesEntites()

    private let memoire = NSCache<NSString, UIImage>()
    private let dossier: URL
    private let plafond = 60 * 1024 * 1024
    private let verrou = NSLock()
    private var enCours: [String: Task<UIImage?, Never>] = [:]

    /// La même session que les fiches de Wikidata : Wikimedia refuse les requêtes sans User-Agent
    /// descriptif. Le cache HTTP est coupé : c'est celui-ci qui garde.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.urlCache = nil
        cfg.httpAdditionalHeaders = ["User-Agent": fornewsUserAgent]
        return URLSession(configuration: cfg)
    }()

    init() {
        dossier = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Analytic/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        memoire.countLimit = 300
        // Le ménage, une fois par lancement, hors du fil principal.
        Task.detached(priority: .background) { [self] in self.reduire() }
    }

    /// L'image déjà en mémoire, sans attendre : la vignette s'affiche d'emblée en défilant.
    func immediate(_ adresse: String) -> UIImage? {
        memoire.object(forKey: adresse as NSString)
    }

    /// L'image d'une adresse : de la mémoire, du disque, sinon de Wikimedia Commons. Nil si elle
    /// n'est pas joignable ou pas une image.
    func image(_ adresse: String) async -> UIImage? {
        if let i = memoire.object(forKey: adresse as NSString) { return i }
        let tache: Task<UIImage?, Never> = verrou.withLock {
            if let t = enCours[adresse] { return t }
            // Le cadrage avec le décodage, hors du fil principal : la vignette arrive bien cadrée.
            let t = Task.detached(priority: .userInitiated) { [self] in
                let image = await self.charger(adresse)
                if let image { await Cadrage.calculer(image, cle: adresse) }
                return image
            }
            enCours[adresse] = t
            return t
        }
        let image = await tache.value
        if let image { memoire.setObject(image, forKey: adresse as NSString) }
        verrou.withLock { enCours[adresse] = nil }
        return image
    }

    private func charger(_ adresse: String) async -> UIImage? {
        let fichier = dossier.appendingPathComponent(Self.nom(adresse))
        if let data = try? Data(contentsOf: fichier), let image = Self.decoder(data) {
            // Vue aujourd'hui : elle passe derrière les autres au prochain ménage.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fichier.path)
            return image
        }
        guard let url = URL(string: adresse),
              let (data, reponse) = try? await session.data(from: url),
              (reponse as? HTTPURLResponse)?.statusCode == 200,
              let image = Self.decoder(data) else { return nil }
        try? data.write(to: fichier, options: .atomic)
        return image
    }

    /// Décodée à 720 pixels au plus, prête à dessiner.
    private static func decoder(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Le nom du fichier : l'empreinte de l'adresse.
    private static func nom(_ adresse: String) -> String {
        SHA256.hash(data: Data(adresse.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Au-delà du plafond, les moins récemment vues s'en vont jusqu'aux trois quarts.
    private func reduire() {
        let cles: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let fichiers = try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: cles) else { return }
        var elements = fichiers.map { u -> (URL, Int, Date) in
            let v = try? u.resourceValues(forKeys: Set(cles))
            return (u, v?.fileSize ?? 0, v?.contentModificationDate ?? .distantPast)
        }
        var total = elements.reduce(0) { $0 + $1.1 }
        guard total > plafond else { return }
        elements.sort { $0.2 < $1.2 }
        for (u, taille, _) in elements where total > plafond * 3 / 4 {
            try? FileManager.default.removeItem(at: u)
            total -= taille
        }
    }

    /// Tout oublier, avec les fiches (« Oublier les fiches gardées »).
    func vider() {
        memoire.removeAllObjects()
        try? FileManager.default.removeItem(at: dossier)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }
}
