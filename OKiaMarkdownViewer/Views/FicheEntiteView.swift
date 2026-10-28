import SwiftUI

/// Option Analytic (1.4) — la fiche d'une entité : sa photo, ce que le document et Wikidata en
/// disent, sa place sur la carte, et le chemin vers ses mentions dans le document.
struct FicheEntiteView: View {
    let entite: EntiteDocument
    @ObservedObject var analyse: AnalyseEntites
    @EnvironmentObject private var store: DocumentStore
    var voirDansLeDocument: (EntiteDocument) -> Void

    @State private var cartePleinEcran: TappedCarte?
    @State private var autreFiche = false
    @State private var memeQue = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = Localization.shared
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if entite.image != nil {
                    VignetteEntite(entite: entite, taille: 240, rond: false)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(entite.nom).font(.title2.weight(.bold))
                    HStack(spacing: 8) {
                        Label(entite.genre ?? tr(entite.type.libelle), systemImage: entite.type.symbole)
                            .foregroundStyle(entite.type.couleur)
                        if entite.mentions > 0 {
                            Text("·").foregroundStyle(.secondary)
                            Text(tr("%d mentions", entite.mentions)).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                if let d = entite.description, !d.isEmpty {
                    Text(d).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                Button { voirDansLeDocument(entite) } label: {
                    Label(tr("Voir dans le document"), systemImage: "text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(orange)
                .disabled(entite.mentions == 0)
                if entite.aDesCoordonnees { miniCarte }
                dansLeCoffre
                provenance
            }
            .padding(16)
        }
        .navigationTitle(entite.nom)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $cartePleinEcran) { carte in CarteZoomView(carte: carte) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MenuSignalerErreur(entite: entite, analyse: analyse,
                                   autreFiche: { autreFiche = true }, memeQue: { memeQue = true },
                                   retiree: { dismiss() })
                    .labelStyle(.iconOnly)
                    .tint(orange)
            }
        }
        .sheet(isPresented: $autreFiche) { ChoixFicheView(entite: entite, analyse: analyse) }
        .sheet(isPresented: $memeQue) { ChoixMemeEntiteView(entite: entite, analyse: analyse, reunie: { dismiss() }) }
    }

    private var miniCarte: some View {
        let cfg = AnalyseEntites.configurationCarte([entite])
        return CarteWebView(cfg: cfg, sousBoutonFermer: false)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Button { cartePleinEcran = TappedCarte(cfg: cfg) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(10)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .tint(orange)
                .padding(10)
                .padding(.bottom, EntitesView.margeSources)
                .accessibilityLabel(tr("Carte en plein écran"))
            }
    }

    /// Les documents du coffre qui nomment cette entité (l'index de l'analyse du coffre), du plus
    /// récent au plus ancien : toucher l'un d'eux l'ouvre (Patrick, 27/10/2026 : « on doit pouvoir
    /// afficher les documents d'une entité »).
    @ViewBuilder private var dansLeCoffre: some View {
        if let e = AnalyseCoffre.partage.entite(nommee: entite.nom), !e.presences.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Dans le coffre") + " · " + tr("%d documents", e.presences.count))
                    .font(.headline)
                ForEach(e.presences) { p in
                    Button {
                        NotificationCenter.default.post(name: .okiaOuvrirRapport, object: store, userInfo: ["id": p.document])
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.nom).lineLimit(2).multilineTextAlignment(.leading)
                                Text(p.date.dateCourte)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            PastilleMentions(n: p.mentions)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    /// D'où vient ce que la fiche affirme : le document, et Wikidata quand il a été consulté. La
    /// photo vient de Wikimedia Commons, sous la licence de son auteur.
    @ViewBuilder private var provenance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entite.origine == .rapport ? tr("Nommée par le rapport fornews.") : tr("Trouvée dans le texte du document."))
            if let qid = entite.qid, let url = URL(string: "https://www.wikidata.org/wiki/\(qid)") {
                Link(destination: url) {
                    Label(tr("Fiche Wikidata %@", qid), systemImage: "arrow.up.right.square")
                }
                .tint(orange)
            }
            // fornews ouvre sa fiche s'il connaît l'entité, sinon il le dit et mène à Wikidata.
            if let qid = entite.qid, let url = URL(string: "fornews://entite?qid=\(qid)"),
               UIApplication.shared.canOpenURL(url) {
                Link(destination: url) {
                    Label(tr("Ouvrir dans fornews"), systemImage: "arrow.up.forward.app")
                }
                .tint(orange)
            }
            if entite.image != nil { Text(tr("Photo : Wikimedia Commons.")) }
            if analyse.correction(entite) != nil { Text(tr("Corrigée par vous.")) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
