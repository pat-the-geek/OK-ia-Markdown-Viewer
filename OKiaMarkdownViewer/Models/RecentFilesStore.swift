import Foundation

/// A previously opened document, persisted via a security-scoped bookmark so it can be reopened.
struct RecentFile: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let bookmark: Data
    let openedAt: Date
}

/// Persists the list of recently opened Markdown files (most-recent first).
/// On iOS, bookmarks created from document-picker / open-in URLs are security-scoped by default.
@MainActor
final class RecentFilesStore: ObservableObject {
    @Published private(set) var items: [RecentFile] = []

    private let key = "okia.recentFiles"
    private let maxItems = 12

    init() { load() }

    func add(url: URL) {
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        let name = url.lastPathComponent
        // De-dupe by filename (most recent wins).
        var next = items.filter { $0.name != name }
        next.insert(RecentFile(name: name, bookmark: data, openedAt: Date()), at: 0)
        if next.count > maxItems { next = Array(next.prefix(maxItems)) }
        items = next
        save()
    }

    /// Resolves a recent entry back to a usable URL. Caller must start/stop security-scoped access.
    func resolve(_ item: RecentFile) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale {
            // Refresh the stored bookmark opportunistically.
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                   let idx = items.firstIndex(of: item) {
                    items[idx] = RecentFile(id: item.id, name: item.name, bookmark: fresh, openedAt: item.openedAt)
                    save()
                }
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
