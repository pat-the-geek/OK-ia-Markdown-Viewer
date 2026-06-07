#if targetEnvironment(macCatalyst)
import Foundation

/// macOS only: periodically polls the vault's matching subfolders and reports newly arrived
/// reports so the app can auto-open them. Polling (vs. a single FS event source) is used because
/// reports may land in several "rapports-*" subfolders, and iCLoud sync itself isn't instant.
/// Runs only while the app is active (iOS suspends background apps, so this is Catalyst-only).
@MainActor
final class VaultWatcher {
    private let vault: VaultStore
    private let onNew: (VaultReport) -> Void

    private var timer: Timer?
    private var lastNewest: Date = .distantPast
    private let interval: TimeInterval = 5

    init(vault: VaultStore, onNew: @escaping (VaultReport) -> Void) {
        self.vault = vault
        self.onNew = onNew
    }

    func start() {
        stop()
        guard vault.hasFolder else { return }
        // Baseline: don't auto-open an existing report at startup, only future arrivals.
        vault.refresh()
        lastNewest = vault.reports.first?.modified ?? .distantPast

        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        vault.refresh()
        guard let newest = vault.reports.first else { return }
        if newest.modified > lastNewest {
            lastNewest = newest.modified
            onNew(newest)
        }
    }
}
#endif
