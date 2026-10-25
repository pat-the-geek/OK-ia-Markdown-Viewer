import SwiftUI

/// Option Analytic (1.4), Mac — l'import en cours : l'étape, ce qui est fait sur le tout, le
/// dernier élément repéré (un titre, une diapositive) et le temps qui reste.
struct ImportView: View {
    @ObservedObject var import_: ImportEnCours
    var annuler: () -> Void

    @State private var consignes = false
    @State private var rapport = false
    @ObservedObject private var loc = Localization.shared
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("Import de « %@ »", import_.nomSource), systemImage: "square.and.arrow.down.on.square")
                .font(.headline)
                .lineLimit(2)
            if let doc = import_.enAttente {
                question(doc)
            } else if let a = import_.avancement {
                ProgressView(value: Double(a.fait), total: Double(max(a.total, 1))).tint(orange)
                HStack {
                    Text("\(a.etape) · \(a.fait) / \(a.total)")
                    Spacer()
                    // Le compte à rebours, rafraîchi chaque seconde.
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        if let reste = import_.resteEstime(ctx.date) {
                            Text(tr("environ %d s", max(1, Int(reste.rounded()))))
                        }
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                if let d = a.dernier, !d.isEmpty {
                    Text(d).font(.footnote).foregroundStyle(.tertiary).lineLimit(1)
                }
            } else {
                ProgressView().tint(orange)
                Text(tr("Lecture du fichier…")).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(tr("Annuler"), role: .cancel, action: annuler).tint(orange)
                if import_.enAttente != nil {
                    Button(tr("Importer")) { import_.poursuivre(consignes: consignes, rapport: rapport) }
                        .buttonStyle(.borderedProminent)
                        .tint(orange)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .animation(.default, value: import_.enAttente == nil)
        .frame(minWidth: 380, idealWidth: 440)
    }

    /// La question, une fois le document lu : ce qu'Apple Intelligence peut y ajouter. Rien n'est
    /// coché d'avance — l'option est proposée, jamais imposée.
    @ViewBuilder private func question(_ doc: DocumentImporte) -> some View {
        Text(doc.resume).font(.subheadline).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 10) {
            if !doc.consignes.isEmpty {
                Toggle(isOn: $consignes) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.consignes.count == 1 ? tr("Utiliser le commentaire comme consigne")
                                                      : tr("Utiliser les %d commentaires comme consignes", doc.consignes.count))
                        Text(tr("Apple Intelligence rédige ce que chaque commentaire demande. Le texte rédigé est ajouté et marqué comme tel ; le vôtre n’est jamais remplacé."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Toggle(isOn: $rapport) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Rédiger aussi un rapport d’analyse"))
                    Text(tr("Résumé, points clés, perspectives et voix critiques, à la manière de fornews. Comptez une à deux minutes."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(orange)
        Label(tr("Sur votre Mac, avec Apple Intelligence : le document ne le quitte pas."), systemImage: "lock")
            .font(.caption).foregroundStyle(.secondary)
    }
}
