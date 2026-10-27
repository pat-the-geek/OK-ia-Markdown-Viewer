import Foundation
import CryptoKit
import WebKit

// Option Analytic (1.4) — les annotations d'un document. Le fichier .md n'est jamais modifié :
// elles vivent à côté, liées au document, et la page les repose à chaque rendu (Web/annotations.js).

/// Ce qui retrouve une annotation dans le texte, quelle que soit la mise en page : la citation
/// exacte et ce qui l'entoure. Pour une note manuscrite, la citation est le début de son bloc, et
/// `fx`, `fy`, `fl` sa place et sa largeur, en largeurs de bloc.
struct AncreAnnotation: Codable, Equatable {
    var exact: String
    var prefix: String
    var suffix: String
    var balise: String?
    var fx: Double?
    var fy: Double?
    var fl: Double?
}

struct Annotation: Codable, Identifiable, Equatable {
    enum Genre: String, Codable { case surligne, souligne, encre }
    enum Couleur: String, Codable, CaseIterable { case jaune, vert, rose, bleu }

    var id = UUID().uuidString
    var type: Genre
    var couleur: Couleur
    var ancre: AncreAnnotation
    /// La note manuscrite, en PNG (base64), telle que la page l'affiche.
    var image: String?
    /// Le tracé PencilKit d'origine, pour pouvoir un jour le reprendre.
    var trace: Data?
    var date = Date()
}

/// Les annotations, une liste par document, dans Application Support. Clé : le chemin du fichier
/// (un document du coffre garde le sien), à défaut son nom.
/// ⚠️ Le passage d'un appareil à l'autre par l'iCloud privé attend la même capacité iCloud que le
/// cache des entités (TACHES-1.4.md).
enum AnnotationsStore {
    private struct Fichier: Codable {
        var cle: String
        var annotations: [Annotation]
    }

    static func cle(_ document: MarkdownDocument) -> String {
        document.sourceURL?.standardizedFileURL.path ?? document.filename
    }

    private static func url(_ cle: String) -> URL {
        let dossier = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let nom = SHA256.hash(data: Data(cle.utf8)).map { String(format: "%02x", $0) }.joined()
        return dossier.appendingPathComponent("Annotations/\(nom.prefix(32)).json")
    }

    static func lire(_ document: MarkdownDocument) -> [Annotation] {
        guard let data = try? Data(contentsOf: url(cle(document))),
              let f = try? JSONDecoder().decode(Fichier.self, from: data) else { return [] }
        return f.annotations
    }

    static func ecrire(_ annotations: [Annotation], pour document: MarkdownDocument) {
        let u = url(cle(document))
        if annotations.isEmpty { try? FileManager.default.removeItem(at: u); return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Fichier(cle: cle(document), annotations: annotations)) {
            try? data.write(to: u, options: .atomic)
        }
    }
}

/// Les annotations du document ouvert, et l'état du mode « Annoter ». Tenu par le lecteur.
@MainActor
final class AnnotationsDocument: ObservableObject {
    enum Outil: String, CaseIterable, Identifiable {
        case surligner, souligner, ecrire, gomme
        var id: String { rawValue }
        var symbole: String {
            switch self {
            case .surligner: return "highlighter"
            case .souligner: return "underline"
            case .ecrire:    return "pencil.tip"
            case .gomme:     return "eraser"
            }
        }
        var libelle: String {
            switch self {
            case .surligner: return tr("Surligner")
            case .souligner: return tr("Souligner")
            case .ecrire:    return tr("Écrire")
            case .gomme:     return tr("Gomme")
            }
        }
    }

    @Published private(set) var annotations: [Annotation] = []
    @Published var actif = false
    @Published var outil: Outil = .surligner
    @Published var couleur: Annotation.Couleur = .jaune
    /// Annotations que la page n'a pas retrouvées (le document a changé, ou il est traduit).
    @Published private(set) var orphelines: Set<String> = []

    private var document: MarkdownDocument?
    weak var web: ReaderWebController?
    /// La page de droite du livre, quand il est ouvert.
    weak var livre: LivreController?
    /// Le diaporama : ses diapositives reprennent le texte du document, les annotations s'y posent.
    weak var diaporama: WKWebView?

    func charger(_ document: MarkdownDocument) {
        self.document = document
        annotations = AnnotationsStore.lire(document)
        orphelines = []
        poser()
    }

    func ajouter(_ a: Annotation) {
        annotations.append(a)
        enregistrer()
    }

    func supprimer(_ id: String) {
        annotations.removeAll { $0.id == id }
        enregistrer()
    }

    func toutEffacer() {
        annotations = []
        enregistrer()
    }

    func signalerOrphelines(_ ids: [String]) { orphelines = Set(ids) }

    private func enregistrer() {
        if let document { AnnotationsStore.ecrire(annotations, pour: document) }
        poser()
    }

    /// Le JSON que la page attend (`OKIA_ANNOT.appliquer`), sans le tracé PencilKit.
    var json: String {
        struct Vue: Encodable { let id, type, couleur: String; let ancre: AncreAnnotation; let image: String? }
        let vues = annotations.map { Vue(id: $0.id, type: $0.type.rawValue, couleur: $0.couleur.rawValue,
                                         ancre: $0.ancre, image: $0.image) }
        return (try? String(data: JSONEncoder().encode(vues), encoding: .utf8)) ?? "[]"
    }

    func poser() {
        let j = json
        web?.poserAnnotations(j)
        livre?.poserAnnotations(j)
        diaporama?.evaluateJavaScript("window.OKIA_ANNOT && window.OKIA_ANNOT.appliquer(\(j))")
    }
}
