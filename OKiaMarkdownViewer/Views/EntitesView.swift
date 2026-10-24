import SwiftUI

/// Option Analytic (1.4) — les entités du document, rangées par genre. Dans la seconde partie quand
/// l'écran en a la place (Duo déplié, grand écran en paysage, Mac), sinon dans une feuille. Toucher
/// une entité la cherche dans le document. La galerie et la carte viennent au lot ②.
struct EntitesView: View {
    let document: MarkdownDocument
    @ObservedObject var analyse: AnalyseEntites
    /// Cherche le nom dans le document qu'on lit.
    var surChoix: (EntiteDocument) -> Void

    @AppStorage(ConsentementWikidata.cle) private var consentementBrut = ConsentementWikidata.jamaisDemande.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fermerPanneau) private var fermerPanneau
    @ObservedObject private var loc = Localization.shared

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    private var consentement: ConsentementWikidata {
        ConsentementWikidata(rawValue: consentementBrut) ?? .jamaisDemande
    }

    var body: some View {
        NavigationStack {
            contenu
                .navigationTitle(tr("Entités"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(tr("Fermer")) { (fermerPanneau ?? { dismiss() })() }.tint(orange)
                    }
                    ToolbarItem(placement: .topBarLeading) { menuWikidata }
                }
        }
        .task(id: document.id) { analyse.analyser(document, wikidata: consentement) }
        .onChange(of: consentementBrut) { _, _ in analyse.analyser(document, wikidata: consentement) }
    }

    @ViewBuilder private var contenu: some View {
        if analyse.etat == .lecture || analyse.etat == .inactif {
            VStack(spacing: 12) {
                ProgressView()
                Text(tr("Lecture du document…")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if analyse.entites.isEmpty {
            ContentUnavailableView(tr("Aucune entité"), systemImage: "person.2",
                                   description: Text(tr("Ce document ne nomme ni personne, ni organisation, ni lieu.")))
        } else {
            List {
                if consentement == .jamaisDemande { Section { carteConsentement } }
                Section { bandeauEtat }
                ForEach(analyse.parType, id: \.type) { groupe in
                    Section {
                        ForEach(groupe.entites) { e in
                            Button {
                                surChoix(e)
                                if fermerPanneau == nil { dismiss() }
                            } label: { ligne(e) }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label(titre(groupe), systemImage: groupe.type.symbole)
                            .foregroundStyle(groupe.type.couleur)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Le titre d'une section : le genre du rapport fornews quand il le donne, sinon celui de fornews.
    private func titre(_ groupe: (type: TypeEntite, entites: [EntiteDocument])) -> String {
        "\(groupe.entites.first(where: { $0.genre != nil })?.genre ?? tr(groupe.type.libelle)) · \(groupe.entites.count)"
    }

    private func ligne(_ e: EntiteDocument) -> some View {
        HStack(spacing: 12) {
            vignette(e)
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
            if e.mentions > 1 {
                Text("\(e.mentions)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .accessibilityLabel(tr("%d mentions", e.mentions))
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private func vignette(_ e: EntiteDocument) -> some View {
        let symbole = Image(systemName: e.type.symbole)
            .font(.system(size: 17))
            .foregroundStyle(e.type.couleur)
            .frame(width: 40, height: 40)
            .background(Circle().fill(e.type.couleur.opacity(0.14)))
        if let s = e.image, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill().frame(width: 40, height: 40).clipShape(Circle())
                } else { symbole }
            }
        } else {
            symbole
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
            Text(analyse.depuisRapport ? tr("%d entités, d’après le rapport fornews et le texte", n)
                                       : tr("%d entités trouvées dans le texte", n))
                .font(.footnote).foregroundStyle(.secondary)
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
                analyse.analyser(document, wikidata: consentement, force: true)
            } label: {
                Label(tr("Oublier les fiches gardées"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .tint(orange)
        .accessibilityLabel(tr("Options des entités"))
    }
}
