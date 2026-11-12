import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Option Analytic (1.6) — le thème « à vos couleurs » (Patrick, 13/11/2026 : « A logo, two colours
/// and a typeface, applied to all your slideshows and carried into the PowerPoint export »).
///
/// Deux couleurs — le fond et l'accent (les titres, les liens, les filets) — et une police. Le texte
/// prend la couleur lisible sur le fond ; le reste s'en déduit dans la page (`presentation.js`,
/// `setMarque`). Le logo, en PNG, vit à côté (Application Support/Analytic/marque-logo.png).
struct ThemeMarque: Codable, Equatable {
    var fond = "#FFFFFF"
    var accent = "#E8972E"
    var police = "Avenir Next"
    /// Appliqué d'office à tous les diaporamas ; sinon, « Ma marque » est un thème parmi d'autres.
    var defaut = true

    /// Des polices présentes sur iPhone, iPad et Mac, et que PowerPoint et Keynote connaissent.
    static let polices = ["Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Optima",
                          "Georgia", "Palatino", "Baskerville", "Didot", "Menlo"]

    private static let cle = "okia.marque"

    static var actuel: ThemeMarque? {
        get {
            UserDefaults.standard.data(forKey: cle).flatMap { try? JSONDecoder().decode(ThemeMarque.self, from: $0) }
        }
        set {
            if let newValue, let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: cle) }
            else { UserDefaults.standard.removeObject(forKey: cle) }
            NotificationCenter.default.post(name: .okiaMarqueChangee, object: nil)
        }
    }

    private static var fichierLogo: URL {
        let dossier = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dossier.appendingPathComponent("Analytic/marque-logo.png")
    }

    static var logo: Data? {
        get { try? Data(contentsOf: fichierLogo) }
        set {
            if let newValue {
                try? FileManager.default.createDirectory(at: fichierLogo.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? newValue.write(to: fichierLogo, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: fichierLogo)
            }
            NotificationCenter.default.post(name: .okiaMarqueChangee, object: nil)
        }
    }

    // MARK: Couleurs

    /// Le texte : presque noir sur un fond clair, presque blanc sur un fond sombre.
    var texte: String { Self.luminance(fond) > 0.45 ? "#161616" : "#F5F4F0" }

    static func luminance(_ hex: String) -> Double {
        let (r, g, b) = rvb(hex)
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func rvb(_ hex: String) -> (Double, Double, Double) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return (1, 1, 1) }
        return (Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    static func couleur(_ hex: String) -> Color {
        let (r, g, b) = rvb(hex)
        return Color(red: r, green: g, blue: b)
    }

    #if canImport(UIKit)
    static func hex(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        func o(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", o(r), o(g), o(b))
    }

    /// Un logo choisi, réduit à 600 points au plus et enregistré en PNG (la transparence reste).
    static func preparerLogo(_ donnees: Data) -> Data? {
        guard let image = UIImage(data: donnees) else { return nil }
        let cote = max(image.size.width, image.size.height)
        let echelle = min(1, 600 / max(cote, 1))
        let taille = CGSize(width: image.size.width * echelle, height: image.size.height * echelle)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: taille, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: taille))
        }.pngData()
    }
    #endif

    /// Ce que la page reçoit (`OKIA_PRESENT.setMarque`), logo compris ; nil sans thème.
    @MainActor static var json: String {
        guard AchatAnalytic.partage.acces, let t = actuel else { return "null" }
        var d: [String: Any] = ["fond": t.fond, "accent": t.accent, "texte": t.texte, "police": t.police, "defaut": t.defaut]
        if let logo { d["logo"] = "data:image/png;base64," + logo.base64EncodedString() }
        guard let data = try? JSONSerialization.data(withJSONObject: d),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    /// Ce que l'export PowerPoint reprend.
    var pptx: MarquePptx {
        func sansDiese(_ s: String) -> String { s.hasPrefix("#") ? String(s.dropFirst()) : s }
        return MarquePptx(fond: sansDiese(fond), texte: sansDiese(texte), accent: sansDiese(accent),
                          police: police, logo: Self.logo)
    }
}

extension Notification.Name {
    static let okiaMarqueChangee = Notification.Name("ch.ok-ia.markdownviewer.marque")
}
