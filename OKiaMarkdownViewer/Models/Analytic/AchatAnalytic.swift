import Foundation
import StoreKit

/// Option Analytic (1.4) — l'achat, en StoreKit 2. Repris de `AchatModele` dans fornews
/// (`FornewsAchat`), avec ses leçons, mais pas mot pour mot : md Viewer n'a ni essai de sept jours
/// ni accès libre en bêta, et son Mac est une app Catalyst.
///
/// Deux produits non consommables (décision de Patrick du 25/10/2026) : « Analytic » sur iPhone et
/// iPad, « Analytic pour Mac » avec l'import Word, PDF et PowerPoint. md Viewer est un achat
/// universel : sans cette séparation, un achat fait sur iPhone serait rendu sur le Mac.
@MainActor
final class AchatAnalytic: ObservableObject {
    static let partage = AchatAnalytic()

    /// « okia » sans tiret, contrairement au bundle (`ch.ok-ia.markdownviewer`) : un identifiant de
    /// produit n'admet que lettres, chiffres, points et soulignés (App Store Connect, 25/10/2026).
    static let produitIDiOS = "ch.okia.markdownviewer.analytic"
    static let produitIDMac = "ch.okia.markdownviewer.analytic.mac"

    /// ⚠️ `targetEnvironment(macCatalyst)`, pas `os(macOS)` comme dans fornews : sous Catalyst,
    /// `os(macOS)` est FAUX, et le Mac aurait vendu — et reconnu — le produit de l'iPhone.
    static var surMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// Le produit qu'on achète ici, et le seul qui ouvre l'option ici.
    static var produitID: String { surMac ? produitIDMac : produitIDiOS }

    /// Prix de repli, tant que l'App Store n'a pas répondu (il donne le sien, dans la devise de
    /// l'utilisateur, dès qu'il répond).
    static var prixDeRepli: String { surMac ? "CHF 5.00" : "CHF 3.00" }

    enum ResultatRestauration: Equatable {
        case restaure, aucunAchat, annule
        case echec(String)
    }

    @Published private(set) var achete = false
    @Published private(set) var produit: Product?
    @Published private(set) var chargement = false
    @Published private(set) var enAchat = false
    @Published private(set) var restauration = false

    private var ecoute: Task<Void, Never>?
    private var demarre = false

    /// L'option est-elle ouverte sur cet appareil ?
    var acces: Bool {
        #if DEBUG
        if let force = Self.forcage { return force }
        #endif
        return achete
    }

    var prix: String { produit?.displayPrice ?? Self.prixDeRepli }

    #if DEBUG
    /// Harnais : OKIA_ACHAT=achete ouvre l'option, OKIA_ACHAT=bloque la ferme, sans StoreKit (le
    /// simulateur lancé par `simctl` ne lit pas le fichier `Analytic.storekit` du schéma).
    /// OKIA_ACHAT=vitrine la ferme aussi, mais montre le bouton d'achat tel qu'en vente, actif et au
    /// prix de la Suisse : c'est la capture qu'Apple demande pour examiner l'achat intégré.
    static let forcage: Bool? = {
        switch ProcessInfo.processInfo.environment["OKIA_ACHAT"] {
        case "achete": return true
        case "bloque", "vitrine": return false
        default: return nil
        }
    }()
    #endif

    /// Vrai seulement pour la capture d'examen (voir `forcage`) ; faux dans tout build livré.
    static var vitrine: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["OKIA_ACHAT"] == "vitrine"
        #else
        return false
        #endif
    }

    /// Au lancement : lit ce qui est déjà acheté, puis écoute les transactions qui arrivent d'ailleurs
    /// — un « Demander à acheter » approuvé plus tard, un achat fait sur un autre appareil du même
    /// compte, un remboursement. fornews ne les écoutait pas : sans cela, une approbation familiale
    /// n'ouvrait l'option qu'au lancement suivant.
    func demarrer() {
        guard !demarre else { return }
        demarre = true
        ecoute = Task { [weak self] in
            for await resultat in Transaction.updates {
                guard case .verified(let t) = resultat else { continue }
                await self?.rafraichir()
                await t.finish()
            }
        }
        Task { await charger() }
    }

    func charger() async {
        chargement = true
        defer { chargement = false }
        await rafraichir()
        if produit == nil { produit = try? await Product.products(for: [Self.produitID]).first }
    }

    /// Les droits en cours, relus à chaque fois : un achat remboursé ferme l'option.
    func rafraichir() async {
        var trouve = false
        for await resultat in Transaction.currentEntitlements {
            guard case .verified(let t) = resultat else { continue }
            if t.productID == Self.produitID && t.revocationDate == nil { trouve = true }
        }
        achete = trouve
    }

    /// Lance l'achat. Rend un message à afficher, ou nil (réussite, ou annulation voulue).
    func acheter() async -> String? {
        guard let produit, !enAchat else { return nil }
        enAchat = true
        defer { enAchat = false }
        do {
            switch try await produit.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    achete = true
                    await t.finish()
                }
                return nil
            case .pending:
                // « Demander à acheter » : l'achat aboutira après approbation, `Transaction.updates`
                // ouvrira alors l'option.
                return tr("Achat en attente d’approbation.")
            case .userCancelled:
                return nil
            @unknown default:
                return nil
            }
        } catch StoreKitError.userCancelled {
            return nil
        } catch {
            return tr("Achat impossible : %@", error.localizedDescription)
        }
    }

    /// Chaque issue a son message : sur Mac, `AppStore.sync()` peut finir « annulé » sans avoir
    /// rien montré, et un bouton qui ne dit rien passe pour cassé (leçon de fornews, build 270).
    func restaurer() async -> ResultatRestauration {
        guard !restauration else { return .annule }
        restauration = true
        defer { restauration = false }
        var erreur: Error?
        do { try await AppStore.sync() } catch { erreur = error }
        // Relire même après un échec : les transactions déjà sur l'appareil peuvent suffire.
        await rafraichir()
        if achete { return .restaure }
        if case .some(StoreKitError.userCancelled) = erreur { return .annule }
        if let erreur { return .echec(erreur.localizedDescription) }
        return .aucunAchat
    }

    static func message(_ r: ResultatRestauration) -> String {
        switch r {
        case .restaure:     return tr("Achat restauré — merci !")
        case .aucunAchat:   return tr("Aucun achat de l’option à restaurer avec ce compte.")
        case .annule:       return tr("Restauration annulée.")
        case .echec(let e): return tr("Restauration impossible : %@", e)
        }
    }
}
