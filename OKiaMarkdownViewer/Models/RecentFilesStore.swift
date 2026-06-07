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
    @Published private(set) var items: [RecentFile] = []

    private let key = "okia.recentFiles"
    private let maxItems = 12

    init() { load() }

    /// Remember a local file (security-scoped bookmark).
    func add(url: URL) {
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        insert(RecentFile(name: url.lastPathComponent, bookmark: data, remoteURLString: nil, openedAt: Date()))
    }

    /// Remember a remote report (re-downloaded on reopen).
    func addRemote(url: URL, name: String) {
        insert(RecentFile(name: name, bookmark: nil, remoteURLString: url.absoluteString, openedAt: Date()))
    }

    private func insert(_ file: RecentFile) {
        var next = items.filter { $0.name != file.name }   // de-dupe by name (most recent wins)
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

    func remove(_ item: RecentFile) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
