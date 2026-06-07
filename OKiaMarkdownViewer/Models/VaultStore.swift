import Foundation

/// A Markdown report found inside a matching subfolder of the vault root.
struct VaultReport: Identifiable, Equatable {
    let subfolder: String     // matching "rapports-*" directory, relative to the vault root
    let name: String          // file name, e.g. "2026-06-07 rapport.md"
    let modified: Date
    let downloaded: Bool       // false = iCloud placeholder not yet downloaded
    var id: String { subfolder + "/" + name }
}

/// Remembers the vault **root** folder (security-scoped bookmark) and lists Markdown reports
/// from its immediate subfolders whose name matches a glob pattern (default "rapports-*").
/// Only matching folders are read — the rest of the vault is ignored.
@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var folderName: String?
    @Published private(set) var reports: [VaultReport] = []
    @Published private(set) var pattern: String

    private let folderKey = "okia.vaultFolder"
    private let patternKey = "okia.vaultPattern"
    static let defaultPattern = "rapports-*"

    private var bookmark: Data?

    init() {
        bookmark = UserDefaults.standard.data(forKey: folderKey)
        pattern = UserDefaults.standard.string(forKey: patternKey) ?? VaultStore.defaultPattern
        folderName = resolveFolder()?.lastPathComponent
    }

    var hasFolder: Bool { bookmark != nil }

    func setFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        bookmark = data
        UserDefaults.standard.set(data, forKey: folderKey)
        folderName = url.lastPathComponent
        refresh()
    }

    func setPattern(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        pattern = trimmed.isEmpty ? VaultStore.defaultPattern : trimmed
        UserDefaults.standard.set(pattern, forKey: patternKey)
        refresh()
    }

    func clearFolder() {
        bookmark = nil
        UserDefaults.standard.removeObject(forKey: folderKey)
        folderName = nil
        reports = []
    }

    /// Resolve the stored bookmark to the vault root URL. Caller manages security scope when reading.
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
                UserDefaults.standard.set(fresh, forKey: folderKey)
            }
        }
        return url
    }

    func reportURL(_ report: VaultReport) -> URL? {
        resolveFolder()?.appendingPathComponent(report.subfolder).appendingPathComponent(report.name)
    }

    /// Scan immediate subfolders matching `pattern` and collect their `.md` reports, newest first.
    func refresh() {
        guard let root = resolveFolder() else { reports = []; return }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            reports = []; return
        }
        let predicate = NSPredicate(format: "SELF LIKE[c] %@", pattern)

        var found: [VaultReport] = []
        for child in children {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let dirName = child.lastPathComponent
            guard predicate.evaluate(with: dirName) else { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: child, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { continue }
            for file in files {
                let last = file.lastPathComponent
                let name: String
                let downloaded: Bool
                if last.hasSuffix(".md") && !last.hasPrefix(".") {
                    name = last; downloaded = true
                } else if last.hasPrefix(".") && last.hasSuffix(".icloud") {
                    let inner = String(last.dropFirst().dropLast(".icloud".count))
                    guard inner.hasSuffix(".md") else { continue }
                    name = inner; downloaded = false
                } else {
                    continue
                }
                let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                found.append(VaultReport(subfolder: dirName, name: name, modified: mod, downloaded: downloaded))
            }
        }
        reports = found.sorted { $0.modified > $1.modified }
    }
}
