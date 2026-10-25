import SwiftUI

/// Option Analytic (1.4) — la fiche d'une entité : sa photo, ce que le document et Wikidata en
/// disent, sa place sur la carte, et le chemin vers ses mentions dans le document.
struct FicheEntiteView: View {
    let entite: EntiteDocument
    var voirDansLeDocument: (EntiteDocument) -> Void

    @State private var cartePleinEcran: TappedCarte?
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
                provenance
            }
            .padding(16)
        }
        .navigationTitle(entite.nom)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $cartePleinEcran) { carte in CarteZoomView(carte: carte) }
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
            if entite.image != nil { Text(tr("Photo : Wikimedia Commons.")) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
