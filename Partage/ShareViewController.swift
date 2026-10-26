import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Option Analytic (1.4) — l'extension « md Viewer » du menu Partager. Depuis Safari, elle reçoit la
/// page telle que Safari l'a chargée (`ExtrairePage.js`, exécuté dans la page) ; depuis une autre
/// app, l'adresse seule. Elle la dépose dans la boîte de réception partagée (`BoitePages`), puis
/// ouvre md Viewer quand le système le permet (sur Mac) ; sinon (iPhone, iPad, où une extension de
/// partage n'ouvre pas son app), elle dit que la fiche se prépare à la prochaine ouverture de
/// md Viewer. Elle ne lit ni n'envoie rien d'autre.
final class ShareViewController: UIViewController {
    private let etat = EtatPartage()

    override func viewDidLoad() {
        super.viewDidLoad()
        let vue = UIHostingController(rootView: VuePartage(etat: etat) { [weak self] in self?.terminer() })
        addChild(vue)
        vue.view.frame = view.bounds
        vue.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(vue.view)
        vue.didMove(toParent: self)
        Task { await recevoir() }
    }

    private func recevoir() async {
        guard let page = await Self.page(extensionContext?.inputItems as? [NSExtensionItem] ?? []) else {
            etat.issue = .rien; return
        }
        do { try BoitePages.deposer(page) } catch { etat.issue = .rien; return }
        etat.titre = page.titre ?? page.url
        // Ouvrir md Viewer, là où le système le permet ; il relève la boîte en passant au premier plan.
        let ouvert = await withCheckedContinuation { c in
            extensionContext?.open(URL(string: "mdviewer://pages")!) { c.resume(returning: $0) } ?? c.resume(returning: false)
        }
        if ouvert { terminer() } else { etat.issue = .deposee }
    }

    /// La page : le résultat du script de Safari s'il y en a un, sinon l'adresse partagée.
    private static func page(_ items: [NSExtensionItem]) async -> PageWeb? {
        var adresse: String?
        for item in items {
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                   let d = try? await p.loadItem(forTypeIdentifier: UTType.propertyList.identifier) as? [String: Any],
                   let r = d[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
                   let json = (r["page"] as? String)?.data(using: .utf8),
                   let page = try? JSONDecoder().decode(PageWeb.self, from: json) {
                    return page
                }
                if adresse == nil, p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
                    adresse = u.absoluteString
                }
            }
        }
        return adresse.map { PageWeb(url: $0) }
    }

    private func terminer() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

@MainActor
final class EtatPartage: ObservableObject {
    enum Issue { case enCours, deposee, rien }
    @Published var issue = Issue.enCours
    @Published var titre = ""
}

/// La petite fenêtre du partage. L'extension n'a pas le catalogue de l'app : ses quelques phrases
/// sont ici, dans les cinq langues.
struct VuePartage: View {
    @ObservedObject var etat: EtatPartage
    var fermer: () -> Void
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: etat.issue == .rien ? "exclamationmark.triangle" : "sparkle.magnifyingglass")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(orange)
            switch etat.issue {
            case .enCours:
                ProgressView()
            case .deposee:
                Text(Textes.envoyee).font(.headline)
                if !etat.titre.isEmpty {
                    Text(etat.titre).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.center)
                }
                Text(Textes.ouvrez).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .rien:
                Text(Textes.rien).font(.headline).multilineTextAlignment(.center)
            }
            if etat.issue != .enCours {
                Button(Textes.ok, action: fermer).buttonStyle(.borderedProminent).tint(orange)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum Textes {
    static let langue = String((Locale.preferredLanguages.first ?? "fr").prefix(2))
    static func choisir(_ t: [String: String]) -> String { t[langue] ?? t["en"] ?? "" }
    static let envoyee = choisir(["fr": "Page envoyée à md Viewer", "en": "Page sent to md Viewer",
                                  "de": "Seite an md Viewer gesendet", "es": "Página enviada a md Viewer",
                                  "it": "Pagina inviata a md Viewer"])
    static let ouvrez = choisir(["fr": "Ouvrez md Viewer : sa fiche de lecture s’y prépare.",
                                 "en": "Open md Viewer: its reading sheet is being prepared there.",
                                 "de": "Öffnen Sie md Viewer: Dort wird das Lesedossier vorbereitet.",
                                 "es": "Abra md Viewer: allí se prepara su ficha de lectura.",
                                 "it": "Aprite md Viewer: lì si prepara la sua scheda di lettura."])
    static let rien = choisir(["fr": "Cette page ne peut pas être envoyée à md Viewer.",
                               "en": "This page cannot be sent to md Viewer.",
                               "de": "Diese Seite kann nicht an md Viewer gesendet werden.",
                               "es": "Esta página no se puede enviar a md Viewer.",
                               "it": "Questa pagina non può essere inviata a md Viewer."])
    static let ok = "OK"
}
