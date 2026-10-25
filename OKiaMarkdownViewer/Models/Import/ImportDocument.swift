import Foundation
import UniformTypeIdentifiers

/// Option Analytic (1.4), Mac — l'import d'un document Word, PDF ou PowerPoint : le choix du
/// convertisseur, l'avancement pour le compte à rebours, et le fichier Markdown écrit dans le
/// dossier « Importés » de l'app, d'où le lecteur l'ouvre comme n'importe quel document (il entre
/// dans les récents ; on peut le partager ou l'exporter).
@MainActor
final class ImportEnCours: ObservableObject, Identifiable {
    let id = UUID()
    let nomSource: String
    @Published private(set) var avancement: AvancementImport?
    @Published private(set) var debut = Date()
    private var tache: Task<Void, Never>?

    init(nomSource: String) { self.nomSource = nomSource }

    /// Les formats qu'on importe.
    static let types: [UTType] = [
        .pdf,
        UTType("org.openxmlformats.wordprocessingml.document") ?? UTType(filenameExtension: "docx") ?? .data,
        UTType("org.openxmlformats.presentationml.presentation") ?? UTType(filenameExtension: "pptx") ?? .data,
    ]

    static func estImportable(_ url: URL) -> Bool {
        ["pdf", "docx", "pptx"].contains(url.pathExtension.lowercased())
    }

    /// Le temps qui reste, d'après l'allure jusqu'ici ; nil tant qu'on n'en sait rien.
    func resteEstime(_ maintenant: Date) -> TimeInterval? {
        guard let a = avancement, a.fait >= 2, a.total > a.fait else { return nil }
        let ecoule = maintenant.timeIntervalSince(debut)
        return ecoule / Double(a.fait) * Double(a.total - a.fait)
    }

    /// Lit, convertit et écrit le document ; rend l'adresse du Markdown écrit.
    func lancer(_ url: URL, fini: @escaping @MainActor (Result<URL, Error>) -> Void) {
        debut = Date()
        tache = Task { [weak self] in
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let donnees = try Data(contentsOf: url)
                let nom = url.lastPathComponent
                let suivi: SuiviImport = { [weak self] a in self?.avancement = a }
                let doc: DocumentImporte
                switch url.pathExtension.lowercased() {
                case "docx": doc = try await ImportWord.convertir(donnees, nom: nom, suivi: suivi)
                case "pptx": doc = try await ImportPowerPoint.convertir(donnees, nom: nom, suivi: suivi)
                case "pdf":  doc = try await ImportPDF.convertir(donnees, nom: nom, suivi: suivi)
                default:     throw ErreurImport.formatInconnu(nom)
                }
                try Task.checkCancellation()
                let cible = try Self.ecrire(doc.markdown, nomSource: nom)
                fini(.success(cible))
            } catch is CancellationError {
                return
            } catch {
                fini(.failure(error))
            }
        }
    }

    func annuler() { tache?.cancel() }

    /// Écrit le Markdown dans le dossier « Importés » des documents de l'app, sous le nom du
    /// document d'origine, sans écraser un import précédent.
    nonisolated static func ecrire(_ markdown: String, nomSource: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dossier = docs.appendingPathComponent("Importés", isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let base = (nomSource as NSString).deletingPathExtension
        var cible = dossier.appendingPathComponent(base + ".md")
        var n = 2
        while FileManager.default.fileExists(atPath: cible.path) {
            cible = dossier.appendingPathComponent("\(base) \(n).md"); n += 1
        }
        try markdown.write(to: cible, atomically: true, encoding: .utf8)
        return cible
    }
}

enum ErreurImport: LocalizedError {
    case formatInconnu(String)
    var errorDescription: String? {
        switch self {
        case .formatInconnu(let nom): return tr("md Viewer n’importe pas « %@ » : Word, PDF ou PowerPoint seulement.", nom)
        }
    }
}
