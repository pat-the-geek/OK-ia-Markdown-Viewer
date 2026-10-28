import SwiftUI
import CryptoKit

/// L'accueil en cartes : une grille, chaque carte avec la vignette de son document, à la place des
/// lignes (1.4, Patrick, 28/10/2026 : « sur Mac, un affichage plus spectaculaire avec des
/// thumbnails de document », puis « aussi sur iPhone petit écran »). Les sections, leurs
/// intitulés et leurs menus restent ceux de la liste ; la liste revient aux tailles de texte
/// d'accessibilité.
extension EnvironmentValues {
    @Entry var accueilEnGrille = false
}

/// Ce qu'une carte montre d'un document : sa première image, sinon son titre et ses premières
/// lignes ; et d'où il vient.
struct ApercuDocument {
    enum Origine: String, Codable {
        case web, pdf, word, powerpoint, analyse

        var libelle: String {
            switch self {
            case .web:        return tr("Fiche web")
            case .pdf:        return "PDF"
            case .word:       return "Word"
            case .powerpoint: return "PowerPoint"
            case .analyse:    return tr("Analyse")
            }
        }
        var symbole: String {
            switch self {
            case .web:        return "safari"
            case .pdf:        return "doc.richtext"
            case .word:       return "doc.text"
            case .powerpoint: return "rectangle.on.rectangle"
            case .analyse:    return "sparkle.magnifyingglass"
            }
        }
    }

    var image: UIImage?
    var titre: String
    var extrait: String
    var origine: Origine?
}

/// Les aperçus, calculés hors du fil principal et gardés : en mémoire, et sur le disque (le dossier
/// des caches, par chemin et date de modification) — un document qui change est relu.
@MainActor
final class ApercusDocuments {
    static let partage = ApercusDocuments()
    private var memoire: [String: ApercuDocument] = [:]

    /// `portee` : l'URL dont il faut ouvrir l'accès (le signet d'un récent, la racine du coffre).
    func apercu(_ url: URL, portee: URL?) async -> ApercuDocument {
        let cle = url.path
        if let a = memoire[cle] { return a }
        let a = await Task.detached(priority: .utility) { Self.calculer(url, portee: portee) }.value
        memoire[cle] = a
        return a
    }

    private struct Fiche: Codable { var titre: String; var extrait: String; var origine: ApercuDocument.Origine?; var image: Bool }

    nonisolated private static var dossierCache: URL? {
        guard let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Vignettes", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    nonisolated private static func calculer(_ url: URL, portee: URL?) -> ApercuDocument {
        let acces = portee?.startAccessingSecurityScopedResource() ?? false
        defer { if acces { portee?.stopAccessingSecurityScopedResource() } }
        let nom = url.deletingPathExtension().lastPathComponent
        let modif = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let empreinte = SHA256.hash(data: Data((url.path + "|\(modif.timeIntervalSince1970)").utf8))
            .map { String(format: "%02x", $0) }.joined()
        let fiche = dossierCache?.appendingPathComponent(empreinte + ".json")
        let vignette = dossierCache?.appendingPathComponent(empreinte + ".jpg")
        if let fiche, let d = try? Data(contentsOf: fiche), let f = try? JSONDecoder().decode(Fiche.self, from: d) {
            let image = f.image ? vignette.flatMap { UIImage(contentsOfFile: $0.path) } : nil
            return ApercuDocument(image: image, titre: f.titre, extrait: f.extrait, origine: f.origine)
        }
        // Un document encore dans iCloud (pas téléchargé) : son nom seul.
        guard let donnees = try? Data(contentsOf: url), let texte = String(data: donnees, encoding: .utf8) else {
            return ApercuDocument(image: nil, titre: nom, extrait: "", origine: nil)
        }
        var a = lire(texte, nom: nom)
        if let source = premiereImage(texte, dossier: url.deletingLastPathComponent()),
           let image = charger(source).flatMap(reduire) {
            a.image = image
            if let vignette, let jpeg = image.jpegData(compressionQuality: 0.78) { try? jpeg.write(to: vignette) }
        }
        if let fiche, let d = try? JSONEncoder().encode(Fiche(titre: a.titre, extrait: a.extrait, origine: a.origine, image: a.image != nil)) {
            try? d.write(to: fiche)
        }
        return a
    }

    /// Le titre (en-tête YAML, sinon premier titre, sinon le nom), les premières lignes de texte, et
    /// l'origine (le fichier importé, l'adresse d'une page web, un rapport d'analyse).
    nonisolated private static func lire(_ texte: String, nom: String) -> ApercuDocument {
        var corps = Substring(texte)
        var entete: [String: String] = [:]
        if corps.hasPrefix("---\n"), let fin = corps.dropFirst(4).range(of: "\n---") {
            for ligne in corps[corps.index(corps.startIndex, offsetBy: 4)..<fin.lowerBound].split(separator: "\n") {
                guard let deux = ligne.firstIndex(of: ":") else { continue }
                let cle = ligne[..<deux].trimmingCharacters(in: .whitespaces).lowercased()
                let valeur = ligne[ligne.index(after: deux)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                entete[cle] = valeur
            }
            corps = corps[fin.upperBound...]
        }
        // Les balises HTML d'abord, même sur plusieurs lignes (les en-têtes des revues de presse).
        let debut = String(corps.prefix(8000)).replacingOccurrences(of: #"<[^>]*>"#, with: "\n", options: .regularExpression)
        var titre = entete["titre"] ?? entete["title"] ?? ""
        var lignes: [String] = []
        var dansBloc = false
        for brute in debut.components(separatedBy: "\n") {
            let l = brute.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("```") || l.hasPrefix("~~~") { dansBloc.toggle(); continue }
            if dansBloc || l.isEmpty || l.hasPrefix("|") || l.hasPrefix("[") { continue }
            if l.hasPrefix("#") {
                if titre.isEmpty { titre = l.drop(while: { $0 == "#" || $0 == " " }).description }
                continue
            }
            let propre = l.replacingOccurrences(of: #"!\[[^\]]*\](\([^)]*\)|\[[^\]]*\])"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"[*_`>]+|^[-•]\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if propre.count >= 3 { lignes.append(propre) }
            if lignes.joined(separator: " ").count > 280 { break }
        }
        let source = (entete["source"] ?? "").lowercased()
        let origine: ApercuDocument.Origine? =
            source.hasSuffix(".pdf") ? .pdf
            : source.hasSuffix(".docx") ? .word
            : source.hasSuffix(".pptx") ? .powerpoint
            : entete["url"] != nil ? .web
            : nom.hasSuffix(" — " + tr("analyse")) || nom.hasSuffix(" — analyse") ? .analyse
            : nil
        return ApercuDocument(image: nil, titre: titre.isEmpty ? nom : titre,
                              extrait: String(lignes.joined(separator: " ").prefix(280)), origine: origine)
    }

    /// La première image du document : une balise HTML, une image Markdown en ligne ou par référence.
    nonisolated private static func premiereImage(_ texte: String, dossier: URL) -> String? {
        let motifs = [#"<img\b[^>]*\bsrc="([^"]+)""#, #"!\[[^\]\n]*\]\(([^)\s]+)"#, #"!\[[^\]\n]*\]\[([^\]\n]+)\]"#]
        var meilleur: (position: Int, valeur: String, reference: Bool)?
        let ns = texte as NSString
        for (k, m) in motifs.enumerated() {
            guard let re = try? NSRegularExpression(pattern: m),
                  let r = re.firstMatch(in: texte, range: NSRange(location: 0, length: ns.length)) else { continue }
            if meilleur == nil || r.range.location < meilleur!.position {
                meilleur = (r.range.location, ns.substring(with: r.range(at: 1)), k == 2)
            }
        }
        guard var valeur = meilleur?.valeur else { return nil }
        if meilleur?.reference == true {
            // La définition, par simple recherche : une image embarquée tient sur une ligne de plusieurs
            // centaines de milliers de caractères, qu'une expression régulière ne parcourt pas.
            let debut = ns.range(of: "\n[" + valeur + "]:", options: .caseInsensitive)
            guard debut.location != NSNotFound else { return nil }
            let apres = debut.location + debut.length
            let fin = ns.range(of: "\n", range: NSRange(location: apres, length: ns.length - apres)).location
            valeur = ns.substring(with: NSRange(location: apres, length: (fin == NSNotFound ? ns.length : fin) - apres))
                .trimmingCharacters(in: .whitespaces)
            if let espace = valeur.firstIndex(of: " ") { valeur = String(valeur[..<espace]) }
        }
        if valeur.hasPrefix("data:") || valeur.hasPrefix("http") { return valeur }
        return dossier.appendingPathComponent(valeur.removingPercentEncoding ?? valeur).absoluteString
    }

    nonisolated private static func charger(_ source: String) -> UIImage? {
        if source.hasPrefix("data:"), let virgule = source.firstIndex(of: ",") {
            return Data(base64Encoded: String(source[source.index(after: virgule)...]), options: .ignoreUnknownCharacters)
                .flatMap(UIImage.init(data:))
        }
        guard let url = URL(string: source) else { return nil }
        if url.isFileURL { return UIImage(contentsOfFile: url.path) }
        // Une image d'une page web : celle que le lecteur chargerait aussi. Huit secondes au plus.
        var requete = URLRequest(url: url, timeoutInterval: 8)
        requete.setValue("image/*", forHTTPHeaderField: "Accept")
        let fin = DispatchSemaphore(value: 0)
        var resultat: UIImage?
        URLSession.shared.dataTask(with: requete) { d, _, _ in resultat = d.flatMap(UIImage.init(data:)); fin.signal() }.resume()
        _ = fin.wait(timeout: .now() + 9)
        return resultat
    }

    /// La vignette : 640 points de large au plus ; une icône (moins de 120 points) n'en est pas une.
    nonisolated private static func reduire(_ image: UIImage) -> UIImage? {
        let w = image.size.width, h = image.size.height
        guard w >= 120, h >= 80 else { return nil }
        let k = min(1, 640 / w)
        let taille = CGSize(width: (w * k).rounded(), height: (h * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: taille, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: taille)) }
    }
}

/// La grille d'une section de l'accueil : des cartes de 190 à 260 points, autant que la largeur
/// en admet ; sur iPhone (et le Duo replié), de 140 à 220 points, deux par rangée au moins.
/// Dans la liste, sur le fond de la liste.
struct GrilleCartes<Contenu: View>: View {
    @Environment(\.horizontalSizeClass) private var tailleHorizontale
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        let etroit = tailleHorizontale == .compact
        LazyVGrid(columns: [GridItem(.adaptive(minimum: etroit ? 140 : 190, maximum: etroit ? 220 : 260),
                                     spacing: etroit ? 14 : 20, alignment: .top)],
                  alignment: .leading, spacing: etroit ? 18 : 24, content: contenu)
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 12, trailing: 4))
            .listRowBackground(Color.clear)
    }
}

/// Une carte de l'accueil : la vignette (ou, sans image, le titre et les premières lignes du
/// document), son origine, son nom et sa date.
struct CarteDocument<Menu: View>: View {
    let nom: String
    let mention: String
    /// Le document et l'URL dont il faut ouvrir l'accès ; nil pour un rapport distant.
    var resoudre: () -> (url: URL, portee: URL?)?
    var action: () -> Void
    @ViewBuilder var menu: () -> Menu

    @State private var apercu: ApercuDocument?
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                vignette
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
                    .overlay(alignment: .topLeading) { badge }
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                Text(nom)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(mention)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu(menuItems: menu)
        .task {
            guard apercu == nil, let (url, portee) = resoudre() else { return }
            apercu = await ApercusDocuments.partage.apercu(url, portee: portee)
        }
    }

    @ViewBuilder private var vignette: some View {
        if let image = apercu?.image {
            Color.clear.overlay(Image(uiImage: image).resizable().scaledToFill())
        } else {
            // Sans image : le document lui-même, son titre et ses premières lignes, sur papier.
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [orange.opacity(0.16), Color(uiColor: .secondarySystemGroupedBackground)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 6) {
                    Text(apercu?.titre ?? nom)
                        .font(.system(.headline, design: .serif).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    if let e = apercu?.extrait, !e.isEmpty {
                        Text(e)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, apercu?.origine == nil ? 12 : 34)
            }
        }
    }

    @ViewBuilder private var badge: some View {
        if let o = apercu?.origine {
            // Pas un `Label` : dans une liste, il réserve à l'icône la colonne des lignes, et le
            // mot partait loin de son icône.
            HStack(spacing: 4) {
                Image(systemName: o.symbole)
                Text(o.libelle)
            }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
    }
}
