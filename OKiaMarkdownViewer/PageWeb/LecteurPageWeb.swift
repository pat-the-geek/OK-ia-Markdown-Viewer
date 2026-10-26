import Foundation
import WebKit

/// Option Analytic (1.4) — une page reçue par sa seule adresse (une app qui ne partage que le lien,
/// Safari quand le script n'a rien rendu) : md Viewer la charge dans une vue web hors écran et y
/// exécute `ExtrairePage.js`, le script que Safari exécute au partage. Même extraction, même résultat.
@MainActor
final class LecteurPageWeb: NSObject, WKNavigationDelegate {
    private var vue: WKWebView?
    private var suite: CheckedContinuation<PageWeb, Error>?
    private var minuteur: Task<Void, Never>?

    enum Erreur: LocalizedError {
        case adresse, chargement(String), lecture
        var errorDescription: String? {
            switch self {
            case .adresse:              return tr("Cette adresse n’est pas une page web.")
            case .chargement(let m):    return tr("La page n’a pas pu être chargée (%@).", m)
            case .lecture:              return tr("md Viewer n’a pas trouvé d’article dans cette page.")
            }
        }
    }

    /// Charge la page et en extrait l'article. 30 secondes au plus.
    static func lire(_ adresse: String) async throws -> PageWeb {
        guard let url = URL(string: adresse), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw Erreur.adresse
        }
        let lecteur = LecteurPageWeb()
        return try await lecteur.charger(url)
    }

    private func charger(_ url: URL) async throws -> PageWeb {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<PageWeb, Error>) in
            suite = c
            let config = WKWebViewConfiguration()
            // Rien de ce qu'on lit ici ne reste : ni cookies, ni cache.
            config.websiteDataStore = .nonPersistent()
            let v = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1400), configuration: config)
            v.navigationDelegate = self
            vue = v
            v.load(URLRequest(url: url, timeoutInterval: 25))
            minuteur = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.terminer(.failure(Erreur.chargement(tr("délai dépassé"))))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Les pages qui posent leur texte après le chargement (scripts, images paresseuses) : un temps.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.extraire()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        terminer(.failure(Erreur.chargement(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        terminer(.failure(Erreur.chargement(error.localizedDescription)))
    }

    private func extraire() {
        guard let vue, let script = Self.script else { terminer(.failure(Erreur.lecture)); return }
        vue.evaluateJavaScript(script + "\n;JSON.stringify(window.okiaExtrairePage())") { [weak self] r, _ in
            guard let self else { return }
            guard let s = r as? String, let data = s.data(using: .utf8),
                  let page = try? JSONDecoder().decode(PageWeb.self, from: data) else {
                self.terminer(.failure(Erreur.lecture)); return
            }
            self.terminer(.success(page))
        }
    }

    private func terminer(_ r: Result<PageWeb, Error>) {
        minuteur?.cancel()
        vue?.stopLoading()
        vue = nil
        suite?.resume(with: r)
        suite = nil
    }

    /// Le script d'extraction, livré dans l'app comme dans l'extension.
    static let script: String? = Bundle.main.url(forResource: "ExtrairePage", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
}
