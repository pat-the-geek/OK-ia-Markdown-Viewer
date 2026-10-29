import SwiftUI

/// Option Analytic (1.4) — les entités du document, en liste, en galerie par genre ou sur une carte.
/// Dans la seconde partie quand l'écran en a la place (Duo déplié, grand écran en paysage, Mac),
/// sinon dans une feuille. Toucher une entité ouvre sa fiche, d'où l'on va à sa mention dans le
/// document ; un appui long y va directement.
struct EntitesView: View {
    let document: MarkdownDocument
    @ObservedObject var analyse: AnalyseEntites
    /// Cherche le nom dans le document qu'on lit.
    var surChoix: (EntiteDocument) -> Void

    /// Les trois façons de voir les entités. Le choix est retenu d'un document à l'autre.
    enum Vue: String, CaseIterable, Identifiable {
        case liste, galerie, carte
        var id: String { rawValue }
        var libelle: String {
            switch self {
            case .liste:   return tr("Liste")
            case .galerie: return tr("Galerie")
            case .carte:   return tr("Carte")
            }
        }
    }

    @AppStorage(ConsentementWikidata.cle) private var consentementBrut = ConsentementWikidata.jamaisDemande.rawValue
    @AppStorage("okia.analytic.vue") private var vueBrute = Vue.liste.rawValue
    @State private var fiche: EntiteDocument?
    /// Les deux corrections qui demandent une liste, ouvertes depuis le menu contextuel.
    @State private var autreFiche: EntiteDocument?
    @State private var memeQue: EntiteDocument?
    @State private var cartePleinEcran: TappedCarte?
    @ObservedObject private var achat = AchatAnalytic.partage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fermerPanneau) private var fermerPanneau
    @ObservedObject private var loc = Localization.shared

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    private var consentement: ConsentementWikidata {
        ConsentementWikidata(rawValue: consentementBrut) ?? .jamaisDemande
    }

    /// Avant l'achat, l'aperçu ne consulte jamais Wikidata : rien ne part tant que l'option n'est
    /// pas ouverte, quel que soit le choix déjà fait.
    private var consentementEffectif: ConsentementWikidata { achat.acces ? consentement : .refuse }

    private var vue: Vue { Vue(rawValue: vueBrute) ?? .liste }

    var body: some View {
        NavigationStack {
            racine
                .navigationDestination(item: $fiche) { e in
                    // La fiche suit l'analyse : une photo qui arrive de Wikidata s'y affiche.
                    FicheEntiteView(entite: analyse.entite(nommee: e.nom) ?? e, analyse: analyse,
                                    voirDansLeDocument: { voirDansLeDocument($0) })
                }
        }
        .task(id: document.id) { analyse.analyser(document, wikidata: consentementEffectif) }
        .onChange(of: consentementBrut) { _, _ in analyse.analyser(document, wikidata: consentementEffectif) }
        .onChange(of: achat.acces) { _, _ in analyse.analyser(document, wikidata: consentementEffectif) }
        .fullScreenCover(item: $cartePleinEcran) { carte in CarteZoomView(carte: carte) }
        .sheet(item: $autreFiche) { e in ChoixFicheView(entite: e, analyse: analyse) }
        .sheet(item: $memeQue) { e in ChoixMemeEntiteView(entite: e, analyse: analyse) }
    }

    private var titre: String { achat.acces ? tr("Entités") : "Analytic" }

    /// Dans une feuille, la barre du système. Dans la seconde partie, une rangée à nous, dans la zone
    /// sûre : sur le Duo, le système range les commandes de la barre dans sa colonne de droite (le
    /// « … » y descendait sous l'heure), et « Fermer », collé à cette colonne, ne répondait plus
    /// (Patrick, B88, 25/10/2026).
    @ViewBuilder private var racine: some View {
        if let fermer = fermerPanneau {
            VStack(spacing: 0) {
                // Tout à gauche, loin de la colonne du système qui borde la seconde partie à droite sur
                // le Duo : voir `fermerPanneau` (TableOfContentsView).
                HStack(spacing: 12) {
                    Button(tr("Fermer"), action: fermer)
                        .buttonStyle(.bordered)
                        .tint(orange)
                    Text(titre).font(.headline)
                    if achat.acces { menuWikidata }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                contenu
            }
            .toolbar(.hidden, for: .navigationBar)
        } else {
            contenu
                .navigationTitle(titre)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(tr("Fermer")) { dismiss() }.tint(orange)
                    }
                    ToolbarItem(placement: .topBarLeading) { if achat.acces { menuWikidata } }
                }
        }
    }

    /// Fermer la feuille (pas la seconde partie, qui reste à côté du document), puis chercher.
    private func voirDansLeDocument(_ e: EntiteDocument) {
        surChoix(e)
        if fermerPanneau == nil { dismiss() }
    }

    @ViewBuilder private var contenu: some View {
        if !achat.acces {
            ApercuAnalyticView(analyse: analyse)
        } else if analyse.etat == .lecture || analyse.etat == .inactif || (analyse.entites.isEmpty && analyse.enDetection) {
            VStack(spacing: 12) {
                ProgressView()
                Text(tr("Lecture du document…")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if analyse.entites.isEmpty {
            ContentUnavailableView {
                Label(tr("Aucune entité"), systemImage: "person.2")
            } description: {
                Text(tr("Ce document ne nomme ni personne, ni organisation, ni lieu."))
            } actions: {
                if AnalyseEntites.diagnosticVisible {
                    Text(analyse.diagnostic).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                }
            }
        } else {
            VStack(spacing: 0) {
                Picker(tr("Affichage"), selection: $vueBrute) {
                    ForEach(Vue.allCases) { v in Text(v.libelle).tag(v.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                switch vue {
                case .liste:   liste
                case .galerie: galerie
                case .carte:   carte
                }
            }
        }
    }

    // MARK: Liste

    private var liste: some View {
        List {
            if consentement == .jamaisDemande { Section { carteConsentement } }
            Section { bandeauEtat }
            ForEach(analyse.parType, id: \.type) { groupe in
                Section {
                    ForEach(groupe.entites) { e in
                        Button { fiche = e } label: { ligne(e) }
                            .buttonStyle(.plain)
                            .contextMenu { menuEntite(e) }
                    }
                } header: {
                    Label(titre(groupe), systemImage: groupe.type.symbole)
                        .foregroundStyle(groupe.type.couleur)
                }
            }
            if !analyse.sources.isEmpty {
                Section {
                    ForEach(analyse.sources) { e in
                        Button { voirDansLeDocument(e) } label: { ligne(e) }.buttonStyle(.plain)
                            .contextMenu { menuEntite(e) }
                    }
                } header: {
                    Label(titreSources, systemImage: "newspaper").foregroundStyle(.secondary)
                } footer: {
                    Text(tr("Les journaux et les sites que le document cite. Ils ne sont pas envoyés à Wikidata."))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var titreSources: String { "\(tr("Sources")) · \(analyse.sources.count)" }

    /// Le titre d'une section : le genre du rapport fornews quand il le donne, sinon celui de fornews.
    private func titre(_ groupe: (type: TypeEntite, entites: [EntiteDocument])) -> String {
        "\(groupe.entites.first(where: { $0.genre != nil })?.genre ?? tr(groupe.type.libelle)) · \(groupe.entites.count)"
    }

    @ViewBuilder private func menuEntite(_ e: EntiteDocument) -> some View {
        Button { voirDansLeDocument(e) } label: {
            Label(tr("Voir dans le document"), systemImage: "text.magnifyingglass")
        }
        Button { fiche = e } label: { Label(tr("Fiche"), systemImage: "info.circle") }
        Divider()
        MenuSignalerErreur(entite: e, analyse: analyse, autreFiche: { autreFiche = e }, memeQue: { memeQue = e })
    }

    private func ligne(_ e: EntiteDocument) -> some View {
        HStack(spacing: 12) {
            VignetteEntite(entite: e, taille: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.nom).font(.body.weight(.semibold))
                if let d = e.description, !d.isEmpty {
                    Text(d).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if e.aDesCoordonnees {
                Image(systemName: "mappin").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(tr("Situé sur la carte"))
            }
            if e.mentions > 1 { PastilleMentions(n: e.mentions) }
        }
        .contentShape(Rectangle())
    }

    // MARK: Galerie

    /// Alignées en haut : une carte à une ligne de description se centrait à côté d'une carte à deux.
    private let colonnes = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 14, alignment: .top)]

    private var galerie: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if consentement == .jamaisDemande { carteConsentement.modifier(Encadre()) }
                bandeauEtat.padding(.horizontal, 4)
                ForEach(analyse.parType, id: \.type) { groupe in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(titre(groupe), systemImage: groupe.type.symbole)
                            .font(.headline)
                            .foregroundStyle(groupe.type.couleur)
                        LazyVGrid(columns: colonnes, alignment: .leading, spacing: 14) {
                            ForEach(groupe.entites) { e in
                                Button { fiche = e } label: { CarteGalerie(entite: e) }
                                    .buttonStyle(.plain)
                                    .contextMenu { menuEntite(e) }
                            }
                        }
                    }
                }
                if !analyse.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(titreSources, systemImage: "newspaper").font(.headline).foregroundStyle(.secondary)
                        Text(analyse.sources.map(\.nom).joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Carte

    /// La ligne des sources de la carte (Leaflet, OpenFreeMap, OpenStreetMap), en bas : les
    /// boutons posés dessus la masquaient, et elle doit rester lisible.
    static let margeSources: CGFloat = 20

    @ViewBuilder private var carte: some View {
        let situees = analyse.situees
        if situees.isEmpty {
            ContentUnavailableView(tr("Aucun lieu situé"), systemImage: "map",
                                   description: Text(consentement == .accepte
                                       ? tr("Ni le document ni Wikidata ne donnent de position à ses entités.")
                                       : tr("Le document ne donne la position d’aucune de ses entités. Wikidata peut en trouver, si vous l’acceptez.")))
        } else {
            let cfg = AnalyseEntites.configurationCarte(situees)
            CarteWebView(cfg: cfg, surMarqueur: { nom in fiche = analyse.entite(nommee: nom) },
                         sousBoutonFermer: false)
                .overlay(alignment: .bottomLeading) {
                    Text(tr("%d lieux sur la carte", situees.count))
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                        .padding(12)
                        .padding(.bottom, Self.margeSources)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button { cartePleinEcran = TappedCarte(cfg: cfg) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(12)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .tint(orange)
                    .padding(12)
                    .padding(.bottom, Self.margeSources)
                    .accessibilityLabel(tr("Carte en plein écran"))
                }
        }
    }

    // MARK: Wikidata

    /// La question, posée une fois, avant que le moindre nom ne parte — décision de Patrick du
    /// 25/10/2026 : Wikidata est proposée, jamais imposée.
    private var carteConsentement: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("Compléter par Wikidata ?"), systemImage: "globe")
                .font(.headline)
            Text(tr("Pour les entités que le document ne décrit pas, md Viewer peut chercher leur photo, leur description et leur position sur Wikidata. Seuls les noms partent, un par un — jamais le document, ni son titre."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(tr("Compléter")) { consentementBrut = ConsentementWikidata.accepte.rawValue }
                    .buttonStyle(.borderedProminent).tint(orange)
                Button(tr("Pas maintenant")) { consentementBrut = ConsentementWikidata.refuse.rawValue }
                    .buttonStyle(.bordered).tint(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var bandeauEtat: some View {
        let n = analyse.entites.count
        switch analyse.etat {
        case .detection(let fait, let total):
            // Les premières entités sont là ; le reste du document se lit encore.
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Lecture du document…")).font(.footnote).foregroundStyle(.secondary)
                ProgressView(value: Double(fait), total: Double(max(total, 1))).tint(orange)
            }
        case .resolution(let fait, let total):
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Wikidata complète %d sur %d…", fait, total)).font(.footnote).foregroundStyle(.secondary)
                ProgressView(value: Double(fait), total: Double(max(total, 1))).tint(orange)
            }
        case .wikidataMuet:
            // La raison précise (quota, refus) vient du client de fornews, en français seulement :
            // on dit ici ce qui compte pour le lecteur, dans sa langue.
            Label(tr("Wikidata ne répond pas : la liste reste celle du document."),
                  systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(.secondary)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(analyse.depuisRapport ? tr("%d entités, d’après le rapport fornews et le texte", n)
                                           : tr("%d entités trouvées dans le texte", n))
                    .font(.footnote).foregroundStyle(.secondary)
                // Builds de test seulement : le moyen de détection, à recopier d'un appui long.
                if AnalyseEntites.diagnosticVisible {
                    Text(analyse.diagnostic)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var menuWikidata: some View {
        Menu {
            Toggle(isOn: Binding(get: { consentement == .accepte },
                                 set: { consentementBrut = ($0 ? ConsentementWikidata.accepte : .refuse).rawValue })) {
                Label(tr("Compléter par Wikidata"), systemImage: "globe")
            }
            Button(role: .destructive) {
                CacheEntites.partage.vider()
                CacheImagesEntites.partage.vider()
                analyse.analyser(document, wikidata: consentement, force: true)
            } label: {
                Label(tr("Oublier les fiches gardées"), systemImage: "trash")
            }
            if analyse.nombreDeCorrections > 0 {
                Button(role: .destructive) { analyse.oublierToutesLesCorrections() } label: {
                    Label(tr("Oublier mes %d corrections", analyse.nombreDeCorrections), systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .tint(orange)
        .accessibilityLabel(tr("Options des entités"))
    }
}

// MARK: - Pièces partagées par la liste, la galerie et la fiche

/// La photo d'une entité quand Wikidata en a une, sinon le symbole de son genre, dans sa couleur.
struct VignetteEntite: View {
    let entite: EntiteDocument
    var taille: CGFloat
    var rond = true

    /// Le cadre d'abord, l'image ensuite, en surimpression et rognée : une image en remplissage
    /// prend sinon sa taille naturelle, élargit sa carte et déborde sur les voisines (un logo de
    /// 3 000 points sur la galerie du Duo plié, Patrick, B89).
    var body: some View {
        let forme = rond ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        Color.clear
            .frame(width: rond ? taille : nil, height: taille)
            .frame(maxWidth: rond ? nil : .infinity)
            .overlay {
                // L'image OU le symbole : sous un logo transparent, le symbole transparaissait.
                if let s = entite.image, let image = photo ?? CacheImagesEntites.partage.immediate(s) {
                    ImageRecadree(image: image, cle: s).background(Color.white)
                } else {
                    symbole
                }
            }
            .clipShape(forme)
            .contentShape(forme)
            // La photo vient du cache de l'appareil (`CacheImagesEntites`), sinon de Commons, une fois.
            .task(id: entite.image) {
                photo = nil
                guard let s = entite.image else { return }
                photo = await CacheImagesEntites.partage.image(s)
            }
    }

    @State private var photo: UIImage?

    private var symbole: some View {
        ZStack {
            entite.type.couleur.opacity(0.14)
            Image(systemName: entite.type.symbole)
                .font(.system(size: taille * 0.42))
                .foregroundStyle(entite.type.couleur)
        }
    }
}

/// Une carte de la galerie : la photo, le nom, une ligne de description.
private struct CarteGalerie: View {
    let entite: EntiteDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VignetteEntite(entite: entite, taille: 120, rond: false)
                .overlay(alignment: .topTrailing) {
                    if entite.mentions > 1 { PastilleMentions(n: entite.mentions).padding(6) }
                }
            Text(entite.nom)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let d = entite.description, !d.isEmpty {
                Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .contentShape(Rectangle())
    }
}

struct PastilleMentions: View {
    let n: Int
    var body: some View {
        Text("\(n)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(.regularMaterial))
            .accessibilityLabel(tr("%d mentions", n))
    }
}

/// Le cadre d'une carte posée hors d'une liste (la question Wikidata, dans la galerie).
private struct Encadre: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
