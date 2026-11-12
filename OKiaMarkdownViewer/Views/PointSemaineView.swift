import SwiftUI

/// Option Analytic (1.7) — le point de la semaine, dans l'analyse du coffre (`PointSemaine`).
struct PointSemaineView: View {
    @ObservedObject var analyse: AnalyseCoffre
    /// La dernière visite, lue à l'ouverture de l'analyse.
    let derniereVisite: Date
    var ouvrir: (String) -> Void

    enum Periode: String, CaseIterable, Identifiable {
        case visite, semaine, mois
        var id: String { rawValue }
        var libelle: String {
            switch self {
            case .visite:  return tr("Depuis votre dernière visite")
            case .semaine: return tr("Les 7 derniers jours")
            case .mois:    return tr("Les 30 derniers jours")
            }
        }
    }

    @State private var periode: Periode = .visite
    @State private var resume: String?
    @State private var enRedaction = false
    @State private var montres = 20
    @ObservedObject private var loc = Localization.shared
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    private var depuis: Date {
        switch periode {
        case .visite:  return derniereVisite
        case .semaine: return Date().addingTimeInterval(-7 * 86_400)
        case .mois:    return Date().addingTimeInterval(-30 * 86_400)
        }
    }

    var body: some View {
        let point = analyse.pointDeLaSemaine(depuis: depuis)
        List {
            Section {
                Picker(tr("Période"), selection: $periode) {
                    ForEach(Periode.allCases) { Text($0.libelle).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text(resume ?? point.phrase)
                    if enRedaction {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(tr("Résumé sur l’appareil…"))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(tr("Calculé sur l’appareil, d’après l’index du coffre : rien ne quitte l’appareil."))
            }
            if !point.documents.isEmpty {
                Section(tr("Nouveaux documents") + " · \(point.documents.count)") {
                    ForEach(point.documents.prefix(montres)) { d in
                        Button { ouvrir(AnalyseCoffre.idTrouve(d.id)) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.nom).lineLimit(2)
                                Text(d.arrivee.dateCourte).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                    // Une longue semaine : les vingt plus récents, puis tous sur demande.
                    if point.documents.count > montres {
                        Button(tr("Voir les %d autres", point.documents.count - montres)) { montres = .max }
                            .tint(orange)
                    }
                }
            }
            if !point.nouvelles.isEmpty {
                Section(tr("Nouveaux noms") + " · \(point.nouvelles.count)") {
                    ForEach(point.nouvelles) { e in
                        NavigationLink(value: e) { ligne(e, detail: tr("%d documents", e.presences.count)) }
                    }
                }
            }
            if !point.hausses.isEmpty {
                Section(tr("Plus souvent qu’avant") + " · \(point.hausses.count)") {
                    ForEach(point.hausses) { h in
                        NavigationLink(value: h.entite) {
                            ligne(h.entite, detail: tr("%d documents, contre %d avant", h.maintenant, h.avant))
                        }
                    }
                }
            }
        }
        .task(id: cle(point)) { await rediger(point) }
    }

    private func ligne(_ e: AnalyseCoffre.EntiteCoffre, detail: String) -> some View {
        HStack(spacing: 12) {
            VignetteEntite(entite: e.entite, taille: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.entite.nom).font(.body.weight(.medium)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Le résumé se refait quand la période ou les documents changent.
    private func cle(_ p: PointSemaine) -> String {
        periode.rawValue + "|" + p.documents.map(\.id).joined(separator: ",") + "|" + loc.code
            + "|" + (analyse.etat == .fini ? "fini" : "lecture")
    }

    /// Le modèle de l'appareil, quand Apple Intelligence est là : un paragraphe sur les titres et les
    /// noms. Sinon, ou sur échec, la phrase composée ici.
    private func rediger(_ p: PointSemaine) async {
        resume = nil
        // Une fois le coffre lu : le résumé ne se refait pas à chaque lot de documents.
        guard !p.vide, analyse.etat == .fini, MoteurRedaction.disponible else { return }
        enRedaction = true
        defer { enRedaction = false }
        let langue = ConsignesAnalyste.nomLangue(LangueIA.code)
        let consigne = """
        Tu écris, en \(langue), le point de la semaine d'un lecteur : ce qui est entré dans son coffre \
        de documents. Trois à cinq phrases, un seul paragraphe, sans titre ni liste. Dis de quoi parlent \
        les documents arrivés et quels noms ressortent. N'emploie que les titres et les noms fournis ; \
        n'invente ni fait, ni chiffre, ni date.
        """
        if let texte = await MoteurRedaction.rediger(consigne: consigne, matiere: p.matiere, motsAttendus: 120),
           !Task.isCancelled {
            resume = texte
        }
    }
}
