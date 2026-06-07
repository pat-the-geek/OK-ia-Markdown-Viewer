import Foundation

/// A Markdown report found inside the watched vault folder.
struct VaultReport: Identifiable, Equatable {
    let name: String          // e.g. "2026-06-07 rapport.md"
    let modified: Date
    let downloaded: Bool      // false = iCloud placeholder not yet downloaded
    var id: String { name }
}

/// Remembers a folder (typically an Obsidian vault / "Rapports" subfolder in iCloud Drive)
/// via a security-scoped bookmark, and lists the Markdown reports inside it (newest first).
@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var folderName: String?
    @Published private(set) var reports: [VaultReport] = []

    private let key = "okia.vaultFolder"
    private var bookmark: Data?

    init() {
        bookmark = UserDefaults.standard.data(forKey: key)
        folderName = resolveFolder()?.lastPathComponent
    }

    var hasFolder: Bool { bookmark != nil }

    func setFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        bookmark = data
        UserDefaults.standard.set(data, forKey: key)
        folderName = url.lastPathComponent
        refresh()
    }

    func clearFolder() {
        bookmark = nil
        UserDefaults.standard.removeObject(forKey: key)
        folderName = nil
        reports = []
    }

    /// Resolve the stored bookmark to the folder URL. Caller must manage security scope when reading.
    func resolveFolder() -> URL? {
        guard let bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                self.bookmark = fresh
                UserDefaults.standard.set(fresh, forKey: key)
            }
        }
        return url
    }

    /// Resolve the file URL of a report inside the vault folder.
    func reportURL(_ report: VaultReport) -> URL? {
        resolveFolder()?.appendingPathComponent(report.name)
    }

    /// List `.md` reports (including not-yet-downloaded iCloud placeholders), newest first.
    func refresh() {
        guard let folder = resolveFolder() else { reports = []; return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: []) else {
            reports = []; return
        }

        var found: [VaultReport] = []
        for item in items {
            let last = item.lastPathComponent
            let name: String
            let downloaded: Bool
            if last.hasSuffix(".md") && !last.hasPrefix(".") {
                name = last; downloaded = true
            } else if last.hasPrefix(".") && last.hasSuffix(".icloud") {
                // iCloud placeholder ".<real name>.icloud" -> "<real name>"
                let inner = String(last.dropFirst().dropLast(".icloud".count))
                guard inner.hasSuffix(".md") else { continue }
                name = inner; downloaded = false
            } else {
                continue
            }
            let mod = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            found.append(VaultReport(name: name, modified: mod, downloaded: downloaded))
        }
        reports = found.sorted { $0.modified > $1.modified }
    }
}
