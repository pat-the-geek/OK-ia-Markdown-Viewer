import Foundation

/// Option Analytic (1.4) — le dossier d'import surveillé, sur Mac (Patrick, 27/10/2026, fonction Mac
/// n° 3) : chaque Word, PDF ou PowerPoint qui y arrive (sous-dossiers compris) est importé, à la
/// suite des autres (`DocumentStore.importerLot`), et rangé comme tout import.
///
/// Ce qui s'y trouvait déjà quand on l'a choisi n'est pas importé : seuls les nouveaux. Un fichier
/// est reconnu par son chemin et sa date de modification — remplacé, il repart. Relu toutes les
/// 10 secondes, tant que l'app est ouverte ; un fichier modifié il y a moins de 5 secondes attend
/// le passage suivant (il est peut-être encore en train d'être copié).
@MainActor
final class DossierSurveille: ObservableObject {
    static let partage = DossierSurveille()

    @Published private(set) var nom: String?
    private var bookmark: Data?
    private var dossier: URL?
    private var timer: Timer?
    private var importer: (([URL]) -> Void)?
    private let defauts = UserDefaults.standard
    private let cleDossier = "okia.dossierSurveille"
    private let cleVus = "okia.dossierSurveille.vus"

    init() {
        bookmark = defauts.data(forKey: cleDossier)
        nom = resoudre()?.lastPathComponent
    }

    /// Ce qui a déjà été vu (importé, ou présent au choix du dossier) : chemin relatif → date.
    private var vus: [String: Date] {
        get { (defauts.dictionary(forKey: cleVus) as? [String: Date]) ?? [:] }
        set { defauts.set(newValue, forKey: cleVus) }
    }

    func choisir(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        arreterSurveillance()
        bookmark = data
        defauts.set(data, forKey: cleDossier)
        nom = url.lastPathComponent
        // Ce qui est déjà là n'est pas importé : seuls les nouveaux.
        vus = Dictionary(uniqueKeysWithValues: Self.fichiers(dans: url).map { ($0.cle, $0.date) })
        if let importer { demarrer(importer) }
    }

    func arreter() {
        arreterSurveillance()
        bookmark = nil
        nom = nil
        defauts.removeObject(forKey: cleDossier)
        defauts.removeObject(forKey: cleVus)
    }

    /// Lance la surveillance ; `importer` reçoit les nouveaux fichiers.
    func demarrer(_ importer: @escaping ([URL]) -> Void) {
        self.importer = importer
        arreterSurveillance()
        guard let url = resoudre() else { return }
        // L'accès au dossier reste ouvert tant qu'on le surveille : les fichiers en dépendent.
        _ = url.startAccessingSecurityScopedResource()
        dossier = url
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.relever() }
        }
        relever()
    }

    private func arreterSurveillance() {
        timer?.invalidate()
        timer = nil
        dossier?.stopAccessingSecurityScopedResource()
        dossier = nil
    }

    private func relever() {
        guard let dossier, let importer else { return }
        var deja = vus
        let maintenant = Date()
        let nouveaux = Self.fichiers(dans: dossier).filter { f in
            guard maintenant.timeIntervalSince(f.date) > 5 else { return false }
            if let d = deja[f.cle], d >= f.date { return false }
            deja[f.cle] = f.date
            return true
        }
        guard !nouveaux.isEmpty else { return }
        vus = deja
        importer(nouveaux.map(\.url))
    }

    private static func fichiers(dans dossier: URL) -> [(url: URL, cle: String, date: Date)] {
        DocumentStore.importables(dans: dossier).map { u in
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let cle = String(u.standardizedFileURL.path.dropFirst(dossier.standardizedFileURL.path.count))
            return (u, cle, date)
        }
    }

    private func resoudre() -> URL? {
        guard let bookmark else { return nil }
        var perime = false
        return try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &perime)
    }
}
