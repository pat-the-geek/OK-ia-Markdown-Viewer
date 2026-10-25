import SwiftUI

/// Option Analytic (1.4) — l'écran qui la présente : ce qu'elle apporte, son prix, ce qui reste
/// sur l'appareil. Pas d'essai de sept jours (décision du 25/10/2026) : l'aperçu des entités du
/// document ouvert en tient lieu (`ApercuAnalyticView`).
struct OptionAnalyticView: View {
    /// Dans l'aperçu, l'écran se fait plus serré : le compte des entités du document le suit.
    var compact = false

    @ObservedObject private var achat = AchatAnalytic.partage
    @ObservedObject private var loc = Localization.shared
    @State private var message: String?
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    /// Ce que l'option apporte. Sur Mac, en plus : l'import de Word, PDF et PowerPoint.
    private var apports: [(String, String)] {
        [("person.2", tr("Les personnes, organisations, lieux et produits du document, rassemblés par genre.")),
         ("square.grid.2x2", tr("Une galerie, et une carte des lieux en plein écran.")),
         ("text.magnifyingglass", tr("De chaque fiche, un geste vous ramène à ses mentions dans le texte.")),
         ("pencil.tip.crop.circle", AchatAnalytic.surMac
            ? tr("Surlignez, soulignez et annotez à la souris ou au trackpad : vos notes restent attachées au texte.")
            : tr("Surlignez, soulignez et écrivez au crayon : vos notes restent attachées au texte.")),
         ("newspaper", tr("Un rapport fornews est exploité d’abord : ce qu’il donne n’est jamais redemandé."))]
            + (AchatAnalytic.surMac
               ? [("square.and.arrow.down.on.square", tr("Importez vos documents Word, PDF et PowerPoint : titres, listes, tableaux, images et commentaires repris en Markdown."))]
               : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Analytic", systemImage: "sparkle.magnifyingglass")
                    .font(compact ? .title3.weight(.bold) : .largeTitle.weight(.bold))
                    .foregroundStyle(orange)
                Text(tr("Lisez plus loin que le texte."))
                    .font(compact ? .subheadline : .title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                ForEach(apports, id: \.1) { symbole, texte in
                    Label { Text(texte).fixedSize(horizontal: false, vertical: true) } icon: {
                        Image(systemName: symbole).foregroundStyle(orange)
                    }
                }
            }
            .font(compact ? .footnote : .callout)
            if achat.acces {
                Label(tr("L’option est active sur cet appareil. Merci !"), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                boutonAcheter
            }
            Button {
                Task { message = AchatAnalytic.message(await achat.restaurer()) }
            } label: {
                HStack(spacing: 6) {
                    if achat.restauration { ProgressView().controlSize(.small) }
                    Text(tr("Restaurer mes achats"))
                }
            }
            .font(.callout)
            .tint(orange)
            .disabled(achat.restauration)
            if !achat.acces && achat.produit == nil && !achat.chargement && !AchatAnalytic.vitrine {
                // Jamais d'impasse (leçon de fornews) : dire pourquoi, et pouvoir réessayer.
                HStack(spacing: 8) {
                    Text(tr("L’achat est indisponible pour le moment."))
                    Button(tr("Réessayer")) { Task { await achat.charger() } }.tint(orange)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(AchatAnalytic.surMac
                     ? tr("Achat unique, valable sur vos Mac. Sur iPhone et iPad, Analytic est un achat distinct.")
                     : tr("Achat unique, valable sur votre iPhone et votre iPad. Sur Mac, Analytic pour Mac est un achat distinct."))
                Text(tr("Tout se calcule sur l’appareil. Wikidata n’est consulté que si vous l’acceptez, et seuls les noms partent."))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .task { await achat.charger() }
    }

    private var boutonAcheter: some View {
        Button {
            Task { message = await achat.acheter() }
        } label: {
            HStack {
                if achat.enAchat { ProgressView() }
                Text(tr("Débloquer Analytic · %@", achat.prix))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(orange)
        .disabled(achat.enAchat || (achat.produit == nil && !AchatAnalytic.vitrine))
    }
}

/// L'aperçu, à la place des entités tant que l'option n'est pas achetée : ce que l'analyse locale
/// a trouvé dans le document ouvert, compté par genre, sans le détail. Rien ne part sur le réseau :
/// Wikidata n'est proposé qu'une fois l'option achetée.
struct ApercuAnalyticView: View {
    @ObservedObject var analyse: AnalyseEntites
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OptionAnalyticView(compact: true)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground)))
                if analyse.enCours || analyse.etat == .inactif {
                    ProgressView().frame(maxWidth: .infinity)
                } else if !analyse.entites.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("Dans ce document"))
                            .font(.headline)
                        ForEach(analyse.parType, id: \.type) { groupe in
                            HStack(spacing: 12) {
                                Image(systemName: groupe.type.symbole)
                                    .foregroundStyle(groupe.type.couleur)
                                    .frame(width: 28)
                                Text(groupe.entites.first(where: { $0.genre != nil })?.genre ?? tr(groupe.type.libelle))
                                Spacer()
                                Text("\(groupe.entites.count)")
                                    .font(.body.monospacedDigit().weight(.semibold))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
