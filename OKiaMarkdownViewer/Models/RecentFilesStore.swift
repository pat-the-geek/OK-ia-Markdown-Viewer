import Foundation

/// A previously opened document. Either a local file (security-scoped bookmark) or a
/// remote report opened via mdviewer://open?url= (stored as its HTTPS URL).
struct RecentFile: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    var bookmark: Data?            // local files
    var remoteURLString: String?   // remote reports (mdviewer://open?url=)
    let openedAt: Date

    var isRemote: Bool { remoteURLString != nil }
}

/// Persists the list of recently opened Markdown documents (most-recent first).
/// On iOS, bookmarks created from document-picker / open-in URLs are security-scoped by default.
@MainActor
final class RecentFilesStore: ObservableObject {
    /// Les mêmes récents dans toutes les fenêtres (1.4).
    static let partage = RecentFilesStore()

    @Published private(set) var items: [RecentFile] = []

    private let key = "okia.recentFiles"
    private let maxItems = 12

    init() { load() }

    /// Remember a local file (security-scoped bookmark).
    func add(url: URL) {
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        let chemin = Self.chemin(url)
        insert(RecentFile(name: url.lastPathComponent, bookmark: data, remoteURLString: nil, openedAt: Date())) { item in
            guard item.bookmark != nil else { return false }
            // Un signet qui ne se résout plus (fichier supprimé, déplacé hors d'atteinte) ne désigne
            // plus rien : du même nom, il cède la place.
            guard let u = self.cheminSansEffet(item) else { return item.name == url.lastPathComponent }
            return u == chemin
        }
    }

    /// Remember a remote report (re-downloaded on reopen).
    func addRemote(url: URL, name: String) {
        insert(RecentFile(name: name, bookmark: nil, remoteURLString: url.absoluteString, openedAt: Date())) {
            $0.remoteURLString == url.absoluteString
        }
    }

    /// Un récent par DOCUMENT, pas par nom : deux « Rapport.md » de dossiers différents restent l'un
    /// et l'autre ; le dédoublonnage par nom chassait le premier dès qu'on ouvrait le second
    /// (Patrick, 31/10/2026). `memeDocument` dit quelles entrées désignent le document ajouté.
    private func insert(_ file: RecentFile, memeDocument: (RecentFile) -> Bool) {
        var next = items.filter { !memeDocument($0) }
        next.insert(file, at: 0)
        if next.count > maxItems { next = Array(next.prefix(maxItems)) }
        items = next
        save()
    }

    /// Resolves a local recent entry back to a usable URL. Remote entries return nil
    /// (the caller reopens them via their `remoteURLString`).
    func resolve(_ item: RecentFile) -> URL? {
        guard let bookmark = item.bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale, url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
               let idx = items.firstIndex(of: item) {
                items[idx] = RecentFile(id: item.id, name: item.name, bookmark: fresh,
                                        remoteURLString: nil, openedAt: item.openedAt)
                save()
            }
        }
        return url
    }

    /// Retire des récents le fichier qu'on va supprimer : son signet le suivrait jusqu'à la corbeille.
    func retirer(url: URL) {
        let chemin = Self.chemin(url)
        let avant = items.count
        items.removeAll { item in
            guard item.bookmark != nil, let u = resolve(item) else { return false }
            return Self.chemin(u) == chemin
        }
        if items.count != avant { save() }
    }

    /// Le dossier d'un récent local, pour distinguer deux récents du même nom ; nil pour un rapport
    /// distant ou un signet qui ne se résout plus. Sans effet : appelé pendant l'affichage.
    func dossier(_ item: RecentFile) -> String? {
        cheminSansEffet(item).map { (($0 as NSString).deletingLastPathComponent as NSString).lastPathComponent }
    }

    private static func chemin(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Le chemin d'un récent local, sans rafraîchir son signet (au contraire de `resolve`).
    private func cheminSansEffet(_ item: RecentFile) -> String? {
        guard let b = item.bookmark else { return nil }
        var perime = false
        guard let u = try? URL(resolvingBookmarkData: b, options: [], relativeTo: nil, bookmarkDataIsStale: &perime)
        else { return nil }
        return Self.chemin(u)
    }

    func remove(_ item: RecentFile) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        #if DEBUG
        if ModeDemo.actif { return }   // l'accueil de démonstration n'a pas de récents
        #endif
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        #if DEBUG
        if ModeDemo.actif { return }
        #endif
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
