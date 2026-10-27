import AppKit

/// Option Analytic (1.4) — les Services macOS de md Viewer (fonction Mac n° 6, Patrick, 27/10/2026) :
/// « Ouvrir dans md Viewer » et « Fiche de cette page », depuis le menu Services de n'importe quelle
/// app et le menu contextuel du Finder.
///
/// Mac Catalyst ne sait pas fournir de Services : c'est `NSApplication` qui les reçoit, et UIKit
/// n'y donne pas accès. Ce module AppKit, chargé par l'app au lancement sur Mac
/// (`OKiaMarkdownViewerApp`), s'en charge : il lit ce que le Service envoie et le passe à l'app par
/// une notification. Les Services sont déclarés dans l'Info.plist de l'app (`NSServices`), leurs
/// libellés traduits dans `ServicesMenu.xcstrings`.
@objc(FournisseurServices)
final class FournisseurServices: NSObject {

    /// Le chargement du module installe le fournisseur ; l'app garde l'objet.
    override init() {
        super.init()
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// « Ouvrir dans md Viewer » : des fichiers du Finder (Markdown à lire ; Word, PDF, PowerPoint
    /// à importer), ou du texte sélectionné, ouvert comme un document.
    @objc(ouvrirDansMdViewer:userData:error:)
    func ouvrirDansMdViewer(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            transmettre("okia.service.fichiers", ["urls": urls])
        } else if let texte = pboard.string(forType: .string),
                  !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transmettre("okia.service.texte", ["texte": texte])
        } else {
            error.pointee = "Rien à ouvrir dans md Viewer." as NSString
        }
    }

    /// « Fiche de cette page » : un lien, ou une adresse sélectionnée dans un texte.
    @objc(ficheDeCettePage:userData:error:)
    func ficheDeCettePage(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let lien = (pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first { !$0.isFileURL }
            ?? pboard.string(forType: .string).flatMap(Self.adresse)
        guard let lien, ["http", "https"].contains(lien.scheme?.lowercased() ?? "") else {
            error.pointee = "Aucune adresse web dans la sélection." as NSString
            return
        }
        transmettre("okia.service.page", ["adresse": lien.absoluteString])
    }

    /// La première adresse web d'un texte.
    private static func adresse(_ texte: String) -> URL? {
        let detecteur = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let tout = NSRange(texte.startIndex..., in: texte)
        return detecteur?.matches(in: texte, range: tout).compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }

    /// Passe la demande à l'app et la met au premier plan : un Service ne l'active pas de lui-même.
    private func transmettre(_ nom: String, _ contenu: [String: Any]) {
        NSApplication.shared.activate()
        NotificationCenter.default.post(name: Notification.Name(nom), object: nil, userInfo: contenu)
    }
}
