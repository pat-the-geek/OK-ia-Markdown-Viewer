import SwiftUI

// Option Analytic, 1.5.1 — toutes les annotations, document par document (Patrick, 12/11/2026 :
// « une liste de toutes les annotations prises qui permet d'ouvrir le document concerné »).
//
// Une annotation connaît son document par son nom et l'empreinte de son contenu (`IdentiteDocument`),
// pas par un chemin valable partout : elles arrivent aussi d'autres appareils par iCloud. Le document
// se cherche donc parmi ceux que l'app sait ouvrir — le coffre, les documents analysés, les récents,
// et le chemin où il a été annoté — d'abord par le nom, puis par la clé de ses annotations, lue
// hors du fil principal (`ApercusDocuments`, déjà gardé pour l'accueil). Un document qu'on ne
// retrouve pas reste dans la liste, sans s'ouvrir : « Introuvable sur cet appareil ».

/// Un document annoté, et où le trouver.
struct DocumentAnnote: Identifiable {
    enum Source { case coffre, analyse, recent, chemin }
    struct Lieu {
        let url: URL
        /// L'URL dont il faut ouvrir l'accès : la racine du coffre, le signet d'un récent.
        let portee: URL?
        let source: Source
    }

    /// La clé des annotations (`IdentiteDocument.cle`).
    let id: String
    let identite: IdentiteDocument
    /// Les annotations, la plus récente d'abord.
    let annotations: [Annotation]
    /// Les notes manuscrites, prêtes à afficher.
    let vignettes: [String: UIImage]
    var lieu: Lieu?
    var recherche = true

    var titre: String { (identite.nom as NSString).deletingPathExtension }
    var derniere: Date { annotations.first?.date ?? .distantPast }
}

struct ListeAnnotationsView: View {
    @ObservedObject var vault: VaultStore
    @ObservedObject var recents: RecentFilesStore
    /// Ouvre le document, et y montre l'annotation (nil : le document seul).
    var ouvrir: (DocumentAnnote.Lieu, String?) -> Void
    @ObservedObject private var annotes = DocumentsAnnotes.partage
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [DocumentAnnote] = []
    @State private var lu = false
    @State private var requete = ""
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            contenu
                .navigationTitle(tr("Toutes les annotations"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(tr("Fermer")) { dismiss() } }
                }
                .searchable(text: $requete, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: tr("Rechercher dans les annotations"))
        }
        .tint(orange)
        // Relue quand des annotations s'écrivent, s'effacent ou arrivent d'un autre appareil.
        .task(id: annotes.cles) { await charger() }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 560, minHeight: 600)
        #endif
    }

    // MARK: Le contenu

    @ViewBuilder private var contenu: some View {
        let visibles = filtres
        if !lu {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if documents.isEmpty {
            ContentUnavailableView(tr("Aucune annotation"), systemImage: "highlighter",
                                   description: Text(tr("Les surlignages, les soulignements et les notes manuscrites posés dans vos documents apparaîtront ici.")))
        } else if visibles.isEmpty {
            ContentUnavailableView.search(text: requete)
        } else {
            List {
                ForEach(visibles) { d in
                    Section {
                        ForEach(d.annotations) { a in ligne(a, de: d) }
                    } header: {
                        entete(d)
                    }
                }
            }
        }
    }

    /// Les documents et les annotations où se trouve la requête (le texte annoté, ou le nom du
    /// document), sans tenir compte des majuscules ni des accents.
    private var filtres: [DocumentAnnote] {
        let q = requete.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return documents }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return documents.compactMap { d in
            if d.titre.range(of: q, options: options) != nil { return d }
            let gardees = d.annotations.filter { $0.ancre.exact.range(of: q, options: options) != nil }
            guard !gardees.isEmpty else { return nil }
            var copie = DocumentAnnote(id: d.id, identite: d.identite, annotations: gardees, vignettes: d.vignettes)
            copie.lieu = d.lieu
            copie.recherche = d.recherche
            return copie
        }
    }

    /// L'en-tête d'un document : son nom (le toucher l'ouvre), où il est, combien d'annotations.
    private func entete(_ d: DocumentAnnote) -> some View {
        Button {
            guard let lieu = d.lieu else { return }
            dismiss()
            ouvrir(lieu, nil)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbole(d.lieu?.source))
                    .foregroundStyle(d.lieu == nil ? Color.secondary : orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.titre)
                        .font(.headline)
                        .foregroundStyle(d.lieu == nil ? Color.secondary : Color.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if d.lieu == nil, d.recherche { ProgressView().controlSize(.mini) }
                        Text(mention(d))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(d.annotations.count == 1 ? tr("1 annotation") : tr("%d annotations", d.annotations.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(d.lieu == nil)
        .textCase(nil)
        .accessibilityHint(d.lieu == nil ? "" : tr("Ouvrir le document"))
    }

    private func ligne(_ a: Annotation, de d: DocumentAnnote) -> some View {
        Button {
            guard let lieu = d.lieu else { return }
            dismiss()
            ouvrir(lieu, a.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(uiColor: CalqueAnnotation.encre(a.couleur)))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    if a.type == .encre, let image = d.vignettes[a.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 70, alignment: .leading)
                            .accessibilityHidden(true)
                    }
                    if let texte = texte(a) {
                        Text(texte)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .background(a.type == .surligne ? Color(uiColor: CalqueAnnotation.fond(a.couleur)) : .clear)
                            .underline(a.type == .souligne, color: Color(uiColor: CalqueAnnotation.encre(a.couleur)))
                    }
                    Text(genre(a) + " · " + a.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(d.lieu == nil)
    }

    // MARK: Les libellés

    private func texte(_ a: Annotation) -> String? {
        let exact = a.ancre.exact.trimmingCharacters(in: .whitespacesAndNewlines)
        switch a.type {
        case .surligne, .souligne:
            return exact.isEmpty ? nil : exact
        case .encre:
            switch a.ancre.media {
            case "diagramme": return tr("Sur un diagramme")
            case "image": return tr("Sur une image")
            case "carte": return tr("Sur une carte")
            default:
                guard !exact.isEmpty else { return nil }
                let debut = exact.count > 80 ? String(exact.prefix(80)) + "…" : exact
                return tr("Près de « %@ »", debut)
            }
        }
    }

    private func genre(_ a: Annotation) -> String {
        switch a.type {
        case .surligne: return tr("Surligné")
        case .souligne: return tr("Souligné")
        case .encre: return tr("Note manuscrite")
        }
    }

    private func symbole(_ s: DocumentAnnote.Source?) -> String {
        switch s {
        case .coffre: return "folder"
        case .analyse: return "doc.text.magnifyingglass"
        case .recent, .chemin: return "doc.text"
        case nil: return "questionmark.folder"
        }
    }

    private func mention(_ d: DocumentAnnote) -> String {
        let date = DecoupageParDate.mention(pour: d.derniere)
        switch d.lieu?.source {
        case .coffre: return tr("Coffre") + " · " + date
        case .analyse: return tr("Documents analysés") + " · " + date
        case .recent, .chemin: return tr("Récents") + " · " + date
        case nil: return d.recherche ? date : tr("Introuvable sur cet appareil") + " · " + date
        }
    }

    // MARK: La lecture

    private func charger() async {
        // Les fichiers d'annotations et leurs notes manuscrites, hors du fil principal.
        let lus = await Task.detached(priority: .userInitiated) { () -> [DocumentAnnote] in
            AnnotationsStore.toutes().map { e in
                var vignettes: [String: UIImage] = [:]
                for a in e.annotations where a.type == .encre {
                    if let b = a.image, let data = Data(base64Encoded: b), let image = UIImage(data: data) {
                        vignettes[a.id] = image
                    }
                }
                return DocumentAnnote(id: e.cle, identite: e.document,
                                      annotations: e.annotations.sorted { $0.date > $1.date },
                                      vignettes: vignettes)
            }
            .sorted { $0.derniere > $1.derniere }
        }.value
        // Les lieux déjà trouvés restent : la liste ne clignote pas quand une annotation change.
        let connus = Dictionary(documents.map { ($0.id, $0.lieu) }, uniquingKeysWith: { a, _ in a })
        documents = lus.map { d in
            var d = d
            if let lieu = connus[d.id] ?? nil { d.lieu = lieu; d.recherche = false }
            return d
        }
        lu = true
        await localiser()
    }

    /// Cherche chaque document parmi ceux que l'app sait ouvrir.
    private func localiser() async {
        let noms = Set(documents.filter { $0.lieu == nil }.map(\.identite.nom))
        guard !noms.isEmpty else { return }
        var candidats: [DocumentAnnote.Lieu] = []
        if let racine = await vault.racineHorsFil() {
            for r in vault.reports where noms.contains(r.name) {
                candidats.append(.init(url: racine.appendingPathComponent(r.subfolder).appendingPathComponent(r.name),
                                       portee: racine, source: .coffre))
            }
        }
        if await AchatAnalytic.partage.acces {
            let analyses = await Task.detached { RangementDocuments.documents().map(\.url) }.value
            for u in analyses where noms.contains(u.lastPathComponent) {
                candidats.append(.init(url: u, portee: nil, source: .analyse))
            }
        }
        for item in recents.items where item.bookmark != nil && noms.contains(item.name) {
            if let u = await recents.resoudreHorsFil(item) {
                candidats.append(.init(url: u, portee: u, source: .recent))
            }
        }
        for i in documents.indices where documents[i].lieu == nil {
            guard !Task.isCancelled else { return }
            let d = documents[i]
            var essais = candidats.filter { $0.url.lastPathComponent == d.identite.nom }
            // Là où il a été annoté, s'il est sur cet appareil et lisible.
            if let chemin = d.identite.chemin, !essais.contains(where: { $0.url.path == chemin }) {
                essais.append(.init(url: URL(fileURLWithPath: chemin), portee: nil, source: .chemin))
            }
            var trouve: DocumentAnnote.Lieu?
            for lieu in essais {
                let a = await ApercusDocuments.partage.apercu(lieu.url, portee: lieu.portee)
                if a.cleAnnotations == d.id || a.cleAncienne == d.id { trouve = lieu; break }
            }
            guard i < documents.count, documents[i].id == d.id else { continue }
            documents[i].lieu = trouve
            documents[i].recherche = false
        }
    }
}
