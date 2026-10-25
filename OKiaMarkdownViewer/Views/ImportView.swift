import SwiftUI

/// Option Analytic (1.4), Mac — l'import en cours : l'étape, ce qui est fait sur le tout, le
/// dernier élément repéré (un titre, une diapositive) et le temps qui reste.
struct ImportView: View {
    @ObservedObject var import_: ImportEnCours
    var annuler: () -> Void

    @ObservedObject private var loc = Localization.shared
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("Import de « %@ »", import_.nomSource), systemImage: "square.and.arrow.down.on.square")
                .font(.headline)
                .lineLimit(2)
            if let a = import_.avancement {
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
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 440)
    }
}
