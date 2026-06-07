#if targetEnvironment(macCatalyst)
import Foundation

/// macOS only: watches the vault folder and reports newly arrived reports so the app can
/// auto-open them. Runs only while the app is active (iOS suspends background apps, so this
/// is intentionally Catalyst-only).
@MainActor
final class VaultWatcher {
    private let vault: VaultStore
    private let onNew: (VaultReport) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var folderURL: URL?
    private var scoped = false
    private var lastNewest: Date = .distantPast
    private var debounce: DispatchWorkItem?

    init(vault: VaultStore, onNew: @escaping (VaultReport) -> Void) {
        self.vault = vault
        self.onNew = onNew
    }

    func start() {
        stop()
        guard let folder = vault.resolveFolder() else { return }
        scoped = folder.startAccessingSecurityScopedResource()
        folderURL = folder

        // Baseline: don't auto-open an existing report at startup, only future arrivals.
        vault.refresh()
        lastNewest = vault.reports.first?.modified ?? .distantPast

        fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { stop(); return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.handleChange() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel(); source = nil
        if scoped, let folderURL { folderURL.stopAccessingSecurityScopedResource() }
        scoped = false
        folderURL = nil
    }

    private func handleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func evaluate() {
        vault.refresh()
        guard let newest = vault.reports.first else { return }
        if newest.modified > lastNewest {
            lastNewest = newest.modified
            onNew(newest)
        }
    }
}
#endif
