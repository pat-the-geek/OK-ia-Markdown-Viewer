import Foundation
import CloudKit

/// Option Analytic (1.4) — le partage entre les appareils de l'utilisateur, par CloudKit (Patrick,
/// 27/10/2026 : « le partage se fera par CloudKit ») : les annotations de chaque document, les
/// corrections d'entités et le cache des fiches Wikidata.
///
/// La base PRIVÉE de l'utilisateur, dans son iCloud : rien ne passe par un serveur à nous. Un
/// enregistrement par fichier (zone « Analytic ») : le JSON tel que l'app l'écrit, en pièce jointe,
/// et sa date de modification. Les fichiers locaux restent la référence : la synchronisation les
/// envoie après chaque écriture (par salve), et relève les changements des autres appareils au
/// lancement et à chaque retour au premier plan.
///
/// Conflits : la version la plus récente l'emporte, fichier par fichier — deux appareils qui
/// annotent le même document hors ligne gardent celui qui a écrit le dernier. Le cache, lui, se
/// fusionne (une fiche de plus ne gêne jamais).
///
/// Sans compte iCloud (simulateur, iCloud coupé), rien ne se passe et rien ne le dit : tout reste
/// sur l'appareil, comme avant.
///
/// ⚠️ Les builds TestFlight et App Store parlent à l'environnement de PRODUCTION de CloudKit : les
/// types d'enregistrement créés en développement doivent y être déployés (CloudKit Console, « Deploy
/// Schema Changes ») — TACHES-1.4.md.
@MainActor
final class SynchroICloud {
    static let partage = SynchroICloud()
    static let conteneur = "iCloud.ch.ok-ia.markdownviewer"

    /// Ce qui se partage, et où ça vit sur l'appareil.
    enum Genre: String, CaseIterable {
        case annotations = "Annotations"
        case corrections = "Corrections"
        case cache = "CacheEntites"

        /// Le dossier local (Application Support).
        var dossier: URL {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            switch self {
            case .annotations: return base.appendingPathComponent("Annotations")
            case .corrections, .cache: return base.appendingPathComponent("Analytic")
            }
        }

        /// Les fichiers de ce genre, par nom (sans extension).
        func fichiers() -> [String] {
            switch self {
            case .annotations:
                let liste = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? []
                return liste.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }
            case .corrections: return ["corrections"]
            case .cache: return ["entites-v2"]
            }
        }

        func url(_ nom: String) -> URL { dossier.appendingPathComponent(nom + ".json") }
    }

    /// Un fichier reçu d'un autre appareil : le lecteur recharge ce qui le concerne.
    static let recu = Notification.Name("ch.ok-ia.markdownviewer.synchro.recu")

    private lazy var base = CKContainer(identifier: Self.conteneur).privateCloudDatabase
    private let zone = CKRecordZone.ID(zoneName: "Analytic", ownerName: CKCurrentUserDefaultName)
    private var attente: Task<Void, Never>?
    private var enCours = false
    private let defauts = UserDefaults.standard

    // MARK: L'état — ce qui a été envoyé ou reçu, fichier par fichier

    /// La date de modification du fichier local au dernier échange (envoi ou réception). Un
    /// fichier plus récent est à envoyer ; un fichier absent qui figure ici a été effacé.
    private var echanges: [String: Date] {
        get { (defauts.dictionary(forKey: "okia.synchro.echanges") as? [String: Date]) ?? [:] }
        set { defauts.set(newValue, forKey: "okia.synchro.echanges") }
    }

    private static func cle(_ genre: Genre, _ nom: String) -> String { genre.rawValue + "-" + nom }

    private func identifiant(_ genre: Genre, _ nom: String) -> CKRecord.ID {
        CKRecord.ID(recordName: Self.cle(genre, nom), zoneID: zone)
    }

    private static func dateModification(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: Envoyer

    /// Un fichier vient d'être écrit (ou effacé) : il partira avec la prochaine salve.
    func signaler() {
        attente?.cancel()
        attente = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.synchroniser()
        }
    }

    /// Relève les changements des autres appareils, puis envoie ce qui a changé ici.
    func synchroniser() async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }
        guard (try? await CKContainer(identifier: Self.conteneur).accountStatus()) == .available else { return }
        do {
            try await preparerZone()
            try await relever()
            try await envoyer()
        } catch let e as CKError where e.code == .zoneNotFound || e.code == .userDeletedZone {
            // La zone a disparu (iCloud vidé par l'utilisateur) : on la recrée à la prochaine fois,
            // et tout repartira.
            defauts.removeObject(forKey: "okia.synchro.zone")
            defauts.removeObject(forKey: "okia.synchro.jeton")
            echanges = [:]
        } catch {
            // Réseau absent, quota, iCloud coupé en route : on réessaiera au prochain passage.
        }
    }

    private func preparerZone() async throws {
        guard !defauts.bool(forKey: "okia.synchro.zone") else { return }
        _ = try await base.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
        defauts.set(true, forKey: "okia.synchro.zone")
    }

    /// Les fichiers plus récents que leur dernier échange partent ; ceux qui ont disparu sont
    /// effacés d'iCloud.
    private func envoyer() async throws {
        var etat = echanges
        var aEnvoyer: [(CKRecord, String, Date)] = []
        var aEffacer: [(CKRecord.ID, String)] = []
        for genre in Genre.allCases {
            let presents = Set(genre.fichiers())
            for nom in presents {
                let url = genre.url(nom), cle = Self.cle(genre, nom)
                guard let date = Self.dateModification(url) else { continue }
                if let connu = etat[cle], connu >= date { continue }
                aEnvoyer.append((Self.enregistrement(genre, nom: nom, fichier: url, date: date,
                                                     id: identifiant(genre, nom)), cle, date))
            }
            // Effacés ici depuis le dernier échange.
            for cle in etat.keys where cle.hasPrefix(genre.rawValue + "-") {
                let nom = String(cle.dropFirst(genre.rawValue.count + 1))
                if !presents.contains(nom) { aEffacer.append((identifiant(genre, nom), cle)) }
            }
        }
        guard !aEnvoyer.isEmpty || !aEffacer.isEmpty else { return }
        // La version de l'appareil l'emporte : les changements des autres viennent d'être relevés.
        let (sauves, effaces) = try await base.modifyRecords(saving: aEnvoyer.map(\.0),
                                                             deleting: aEffacer.map(\.0),
                                                             savePolicy: .allKeys)
        for (r, cle, date) in aEnvoyer where (try? sauves[r.recordID]?.get()) != nil { etat[cle] = date }
        for (id, cle) in aEffacer where (try? effaces[id]?.get()) != nil { etat[cle] = nil }
        echanges = etat
    }

    /// L'enregistrement d'un fichier — la forme du schéma : `nom` (chaîne), `modifie` (date),
    /// `contenu` (pièce jointe). Le seed passe par ici, comme l'envoi.
    private static func enregistrement(_ genre: Genre, nom: String, fichier: URL, date: Date,
                                       id: CKRecord.ID) -> CKRecord {
        let r = CKRecord(recordType: genre.rawValue, recordID: id)
        r["nom"] = nom as CKRecordValue
        r["modifie"] = date as CKRecordValue
        r["contenu"] = CKAsset(fileURL: fichier)
        return r
    }

    // MARK: Recevoir

    /// Les changements des autres appareils depuis la dernière relève.
    private func relever() async throws {
        var jeton = (defauts.data(forKey: "okia.synchro.jeton"))
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
        var encore = true
        while encore {
            let r = try await base.recordZoneChanges(inZoneWith: zone, since: jeton)
            for (_, resultat) in r.modificationResultsByID {
                if let modif = try? resultat.get() { recevoir(modif.record) }
            }
            for effacement in r.deletions { effacer(effacement.recordID) }
            jeton = r.changeToken
            encore = r.moreComing
            if let j = try? NSKeyedArchiver.archivedData(withRootObject: r.changeToken, requiringSecureCoding: true) {
                defauts.set(j, forKey: "okia.synchro.jeton")
            }
        }
    }

    private func genreEtNom(_ id: CKRecord.ID) -> (Genre, String)? {
        for genre in Genre.allCases where id.recordName.hasPrefix(genre.rawValue + "-") {
            return (genre, String(id.recordName.dropFirst(genre.rawValue.count + 1)))
        }
        return nil
    }

    private func recevoir(_ r: CKRecord) {
        guard let (genre, nom) = genreEtNom(r.recordID),
              let asset = r["contenu"] as? CKAsset, let source = asset.fileURL,
              let distant = try? Data(contentsOf: source) else { return }
        let date = (r["modifie"] as? Date) ?? Date()
        let url = genre.url(nom), cle = Self.cle(genre, nom)
        var etat = echanges
        if genre == .cache {
            // Le cache se fusionne, quelle que soit la date. S'il avait ici des fiches que l'autre
            // appareil n'a pas, il repartira ; sinon, rien ne repart (sans quoi deux appareils se
            // renverraient le même cache sans fin).
            let ajoutsLocaux = CacheEntites.partage.fusionner(distant)
            etat[cle] = ajoutsLocaux ? date : (Self.dateModification(url) ?? date)
        } else {
            // Plus récent ici : le fichier local partira au prochain envoi.
            if let local = Self.dateModification(url), local > date { return }
            try? FileManager.default.createDirectory(at: genre.dossier, withIntermediateDirectories: true)
            guard (try? distant.write(to: url, options: .atomic)) != nil else { return }
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            etat[cle] = date
            if genre == .corrections { CorrectionsEntites.partage.recharger() }
        }
        echanges = etat
        NotificationCenter.default.post(name: Self.recu, object: nil, userInfo: ["genre": genre.rawValue, "nom": nom])
    }

    #if DEBUG
    // MARK: Le seed du schéma

    /// **Amorçage du schéma CloudKit de Développement** (`-OKIASeedSchema YES`, build Debug du Mac
    /// signé), comme le seed de fornews : une sentinelle de chaque type, écrite par le même code que
    /// l'envoi (`enregistrement`), dans une zone à part (« Amorcage »), puis effacée avec sa zone —
    /// le schéma, lui, reste. Ensuite : CloudKit Console → Deploy Schema Changes → Production
    /// (docs/cloudkit/deploiement-synchro.md). Rend vrai si le seed a été demandé : l'app se ferme.
    static func amorcerSchemaSiDemande() async -> Bool {
        guard UserDefaults.standard.bool(forKey: "OKIASeedSchema") else { return false }
        let activite = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                             reason: "Seed du schéma CloudKit")
        defer { ProcessInfo.processInfo.endActivity(activite) }
        func dire(_ s: String) { print("md Viewer[seed] " + s); fflush(stdout) }
        let conteneur = CKContainer(identifier: conteneur)
        let base = conteneur.privateCloudDatabase
        let zone = CKRecordZone.ID(zoneName: "Amorcage", ownerName: CKCurrentUserDefaultName)
        do {
            let statut = try await conteneur.accountStatus()
            guard statut == .available else { dire("ÉCHEC : pas de compte iCloud sur ce Mac (\(statut.rawValue))."); return true }
            _ = try await base.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
            let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("okia-seed", isDirectory: true)
            try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            var ids: [CKRecord.ID] = []
            for genre in Genre.allCases {
                let fichier = dossier.appendingPathComponent(genre.rawValue + ".json")
                try Data("{}".utf8).write(to: fichier)
                let id = CKRecord.ID(recordName: "sentinelle-" + genre.rawValue, zoneID: zone)
                let r = enregistrement(genre, nom: "sentinelle", fichier: fichier, date: Date(), id: id)
                _ = try await base.modifyRecords(saving: [r], deleting: [], savePolicy: .allKeys)
                ids.append(id)
                dire("\(genre.rawValue) écrit en Development (champs nom, modifie, contenu).")
            }
            // Les sentinelles s'en vont avec leur zone ; les types et leurs champs restent au schéma.
            _ = try await base.modifyRecordZones(saving: [], deleting: [zone])
            dire("seed RÉUSSI (\(ids.count) types).")
        } catch {
            dire("ÉCHEC : \(error)")
        }
        return true
    }
    #endif

    private func effacer(_ id: CKRecord.ID) {
        guard let (genre, nom) = genreEtNom(id), genre != .cache else { return }
        try? FileManager.default.removeItem(at: genre.url(nom))
        var etat = echanges
        etat[Self.cle(genre, nom)] = nil
        echanges = etat
        if genre == .corrections { CorrectionsEntites.partage.recharger() }
        NotificationCenter.default.post(name: Self.recu, object: nil, userInfo: ["genre": genre.rawValue, "nom": nom])
    }
}
