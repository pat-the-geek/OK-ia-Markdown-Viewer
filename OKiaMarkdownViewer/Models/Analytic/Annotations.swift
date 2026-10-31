import Foundation
import CryptoKit
import WebKit

// Option Analytic (1.4) — les annotations d'un document. Le fichier .md n'est jamais modifié :
// elles vivent à côté, liées au document, et la page les repose à chaque rendu (Web/annotations.js).

/// Ce qui retrouve une annotation dans le texte, quelle que soit la mise en page : la citation
/// exacte et ce qui l'entoure. Pour une note manuscrite, la citation est le début de son bloc, et
/// `fx`, `fy`, `fl` sa place et sa largeur, en largeurs de bloc.
///
/// Une note posée sur un diagramme, une image ou une carte, qui n'ont pas de texte, s'ancre à
/// `media` (« diagramme », « image », « carte ») et à son `rang` parmi ceux de son genre, plus
/// `src` pour une image ; `fx`, `fy`, `fl` se mesurent alors en largeurs du dessin, et `prefix`
/// est le texte qui le précède.
struct AncreAnnotation: Codable, Equatable {
    var exact: String
    var prefix: String
    var suffix: String
    var balise: String?
    var fx: Double?
    var fy: Double?
    var fl: Double?
    var media: String?
    var rang: Int?
    var src: String?
    /// Sur une carte : le coin de la note en latitude et longitude, le zoom et la largeur (en
    /// pixels) du tracé. La note suit la carte qu'on déplace ou qu'on zoome.
    var lat: Double?
    var lng: Double?
    var zoom: Double?
    var px: Double?
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

/// Le document auquel des annotations appartiennent — **un seul** (Patrick, 27/10/2026 : « les
/// annotations doivent être liées à un seul document ; il faudra identifier clairement : date,
/// taille, nom de fichier, contenu »).
///
/// La clé est l'empreinte SHA-256 du nom de fichier ET du contenu : un autre document — un autre
/// texte, même sous le même nom, ou le même texte sous un autre nom — n'hérite jamais des
/// annotations d'un premier. Le chemin n'y entre pas : il diffère d'un appareil à l'autre, et la
/// clé doit être la même partout pour le partage par CloudKit. La date non plus : une copie ou une
/// synchronisation la change sans changer le document. Taille, date et chemin sont gardés pour
/// reconnaître le document à l'œil.
///
/// ⚠️ Conséquence voulue : un document modifié est un autre document. Ses annotations restent
/// liées à la version annotée.
struct IdentiteDocument: Codable, Equatable {
    /// Le nom du fichier.
    var nom: String
    /// La taille du contenu, en octets (UTF-8).
    var taille: Int
    /// La date de modification du fichier, quand on la connaît.
    var modifie: Date?
    /// L'empreinte SHA-256 du contenu, en hexadécimal.
    var empreinte: String
    /// Où il était, sur l'appareil qui l'a annoté — indicatif.
    var chemin: String?

    init(_ document: MarkdownDocument) {
        let octets = Data(Self.sansMarques(document.text).utf8)
        nom = document.filename
        taille = octets.count
        empreinte = Self.hex(SHA256.hash(data: octets))
        chemin = document.sourceURL?.standardizedFileURL.path
        modifie = document.sourceURL.flatMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }
    }

    /// La clé des annotations : le nom et le contenu, ensemble. C'est le nom du fichier
    /// d'annotations, et celui de son enregistrement dans iCloud.
    var cle: String { Self.cle(nom: nom, empreinte: empreinte) }

    /// La même clé, d'après le fichier lui-même (le nom, puis le texte tel que le lecteur le
    /// décode) : celle que cherche la marque « annoté » de l'accueil.
    nonisolated static func cle(fichier url: URL, octets: Data) -> String {
        cle(nom: url.lastPathComponent,
            empreinte: hex(SHA256.hash(data: Data(sansMarques(MarkdownLoader.decode(octets)).utf8))))
    }

    /// Le texte qui fait l'identité : sans les marques des diapositives masquées d'une présentation
    /// (`DiapositivesMasquees`). Masquer une diapositive réécrit le fichier ; ses annotations s'y
    /// perdaient (Patrick, 30/10/2026 : « fais les 2 »).
    nonisolated static func sansMarques(_ texte: String) -> String {
        texte.replacingOccurrences(of: DiapositivesMasquees.marque + "\n", with: "")
    }

    private nonisolated static func cle(nom: String, empreinte: String) -> String {
        String(hex(SHA256.hash(data: Data((nom + "\u{0}" + empreinte).utf8))).prefix(32))
    }

    private nonisolated static func hex(_ d: SHA256.Digest) -> String { d.map { String(format: "%02x", $0) }.joined() }
}

/// Les documents annotés, pour la marque de l'accueil (Patrick, 30/10/2026 : « on devrait pouvoir
/// savoir si des annotations ont été effectuées sur le fichier ») : les clés des fichiers
/// d'annotations présents. Relu quand des annotations s'écrivent, s'effacent ou arrivent d'iCloud.
@MainActor
final class DocumentsAnnotes: ObservableObject {
    static let partage = DocumentsAnnotes()
    @Published private(set) var cles: Set<String> = []

    private init() {
        rafraichir()
        NotificationCenter.default.addObserver(forName: SynchroICloud.recu, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?["genre"] as? String == SynchroICloud.Genre.annotations.rawValue else { return }
            MainActor.assumeIsolated { self?.rafraichir() }
        }
    }

    func rafraichir() {
        let presentes = Set(SynchroICloud.Genre.annotations.fichiers())
        if presentes != cles { cles = presentes }
    }
}

/// Les annotations, une liste par document, dans Application Support (`Annotations/<clé>.json`),
/// avec l'identité de leur document. Partagées entre les appareils par CloudKit (`SynchroICloud`),
/// fichier par fichier.
@MainActor
enum AnnotationsStore {
    private struct Fichier: Codable {
        /// Le document annoté. Absent des fichiers d'avant le 27/10/2026 (B96 et avant).
        var document: IdentiteDocument?
        /// L'ancienne clé : le chemin, ou le nom.
        var cle: String?
        var annotations: [Annotation]
    }

    private static func url(_ cle: String) -> URL { SynchroICloud.Genre.annotations.url(cle) }

    static func lire(_ identite: IdentiteDocument, document: MarkdownDocument) -> [Annotation] {
        if let data = try? Data(contentsOf: url(identite.cle)),
           let f = try? JSONDecoder().decode(Fichier.self, from: data),
           f.document == nil || f.document?.empreinte == identite.empreinte {
            return f.annotations
        }
        return reprendreAncien(identite, document: document)
    }

    /// Les annotations des builds de test jusqu'à B96 étaient rangées sous l'empreinte du chemin (à
    /// défaut du nom). Elles passent sous la nouvelle clé, une fois, au document ouvert.
    private static func reprendreAncien(_ identite: IdentiteDocument, document: MarkdownDocument) -> [Annotation] {
        let ancienne = document.sourceURL?.standardizedFileURL.path ?? document.filename
        let nom = String(SHA256.hash(data: Data(ancienne.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32))
        guard let data = try? Data(contentsOf: url(nom)),
              let f = try? JSONDecoder().decode(Fichier.self, from: data), f.document == nil else { return [] }
        ecrire(f.annotations, pour: identite)
        try? FileManager.default.removeItem(at: url(nom))
        return f.annotations
    }

    static func ecrire(_ annotations: [Annotation], pour identite: IdentiteDocument) {
        let u = url(identite.cle)
        defer { SynchroICloud.partage.signaler(); DocumentsAnnotes.partage.rafraichir() }
        if annotations.isEmpty { try? FileManager.default.removeItem(at: u); return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Fichier(document: identite, annotations: annotations)) {
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
    /// Le document annoté, tel qu'on le reconnaît (`IdentiteDocument`).
    private(set) var identite: IdentiteDocument?
    private var abonnement: NSObjectProtocol?
    weak var web: ReaderWebController?
    /// La page de droite du livre, quand il est ouvert.
    weak var livre: LivreController?
    /// Le diaporama : ses diapositives reprennent le texte du document, les annotations s'y posent.
    weak var diaporama: WKWebView?
    /// Les autres vues du document : l'écran du public et l'aperçu du présentateur (1.4).
    private let autresPages = NSHashTable<WKWebView>.weakObjects()

    func suivre(_ vue: WKWebView) {
        autresPages.add(vue)
        vue.evaluateJavaScript("window.OKIA_ANNOT && window.OKIA_ANNOT.appliquer(\(json))")
    }

    func charger(_ document: MarkdownDocument) {
        self.document = document
        let identite = IdentiteDocument(document)
        self.identite = identite
        annotations = AnnotationsStore.lire(identite, document: document)
        orphelines = []
        poser()
        // Les annotations de ce document, changées sur un autre appareil : on les relit.
        if abonnement == nil {
            abonnement = NotificationCenter.default.addObserver(forName: SynchroICloud.recu, object: nil, queue: .main) { [weak self] note in
                let nom = note.userInfo?["nom"] as? String
                MainActor.assumeIsolated {
                    guard let self, let d = self.document, let id = self.identite, nom == id.cle else { return }
                    self.annotations = AnnotationsStore.lire(id, document: d)
                    self.poser()
                }
            }
        }
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
        if let identite { AnnotationsStore.ecrire(annotations, pour: identite) }
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
        for vue in autresPages.allObjects { vue.evaluateJavaScript("window.OKIA_ANNOT && window.OKIA_ANNOT.appliquer(\(j))") }
    }
}
