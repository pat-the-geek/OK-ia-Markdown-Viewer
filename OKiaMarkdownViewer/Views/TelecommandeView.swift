import SwiftUI

/// Option Analytic (1.6) — la télécommande, sur l'iPhone (ou un autre appareil) : trouver le
/// diaporama, le piloter, lire ses notes, dessiner sur la diapositive et montrer un pointeur.
struct TelecommandeView: View {
    @StateObject private var client = TelecommandeClient()
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = Localization.shared

    enum Outil: String, CaseIterable, Identifiable {
        case pointeur, crayon, cercle, surligneur
        var id: String { rawValue }
        var symbole: String {
            switch self {
            case .pointeur: return "hand.point.up.left"
            case .crayon: return "pencil.tip"
            case .cercle: return "circle"
            case .surligneur: return "highlighter"
            }
        }
        var libelle: String {
            switch self {
            case .pointeur: return tr("Pointeur")
            case .crayon: return tr("Crayon")
            case .cercle: return tr("Cercle")
            case .surligneur: return tr("Surligneur")
            }
        }
    }

    @State private var outil: Outil = .pointeur
    @State private var traitEnCours: TraitTelecommande?
    @State private var dernierEnvoi = Date.distantPast
    @State private var debut = Date()
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            Group {
                if case .connecte = client.etat { pilote } else { recherche }
            }
            .navigationTitle(tr("Télécommande"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Fermer")) { dismiss() } } }
            .tint(orange)
        }
        .onAppear { client.chercher(); UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { client.arreter(); UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Trouver le diaporama

    private var recherche: some View {
        List {
            Section {
                if client.trouvees.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(tr("Recherche d’un diaporama…")).foregroundStyle(.secondary)
                    }
                }
                ForEach(client.trouvees) { p in
                    Button { client.rejoindre(p) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.titre.isEmpty ? p.nom : p.titre).font(.body.weight(.semibold))
                            Text(p.nom).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    switch client.etat {
                    case .connexion(let nom): Text(tr("Acceptez la demande sur « %@ »…", nom)).foregroundStyle(orange)
                    case .refuse: Text(tr("La demande n’a pas été acceptée.")).foregroundStyle(.red)
                    default: EmptyView()
                    }
                    Text(tr("Lancez le diaporama sur le Mac ou l’iPad, sur le même réseau Wi-Fi ou à portée Bluetooth. Rien ne passe par un serveur."))
                }
            }
        }
    }

    // MARK: Piloter

    private var pilote: some View {
        VStack(spacing: 12) {
            HStack {
                Text(client.titre).font(.headline).lineLimit(1)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { c in
                    Text(RepetitionDiaporama.duree(c.date.timeIntervalSince(debut))).monospacedDigit().foregroundStyle(orange)
                }
                Text("\(client.index + 1) / \(max(client.total, 1))").monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            diapositive
            HStack(spacing: 10) {
                Picker(tr("Outil"), selection: $outil) {
                    ForEach(Outil.allCases) { Image(systemName: $0.symbole).accessibilityLabel($0.libelle).tag($0) }
                }
                .pickerStyle(.segmented)
                Button { client.envoyer(PaquetTelecommande(type: "effacer")) } label: {
                    Image(systemName: "eraser")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(tr("Effacer les traits"))
            }
            .padding(.horizontal)
            ScrollView {
                Text(client.notes.isEmpty ? tr("Pas de notes pour cette diapositive.") : client.notes)
                    .foregroundStyle(client.notes.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            HStack(spacing: 14) {
                bouton("chevron.left", tr("Précédente")) { client.envoyer(PaquetTelecommande(type: "precedente")) }
                bouton("chevron.right", tr("Suivante")) { client.envoyer(PaquetTelecommande(type: "suivante")) }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func bouton(_ symbole: String, _ libelle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole).font(.largeTitle.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 74)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(libelle)
    }

    /// L'image de la diapositive : le doigt y pointe ou y dessine, en coordonnées de 0 à 1.
    private var diapositive: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.06)
                if let image = client.image {
                    Image(uiImage: image).resizable().scaledToFit()
                        // Ce qu'on dessine, sur la diapositive comme sur l'écran qui présente.
                        .overlay { DessinTelecommande(traits: client.traits, pointeur: client.pointeur) }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in toucher(v.location, cadre: cadreImage(geo.size), fin: false) }
                .onEnded { v in toucher(v.location, cadre: cadreImage(geo.size), fin: true) })
        }
        .aspectRatio(image: client.image)
        .padding(.horizontal)
    }

    private func cadreImage(_ zone: CGSize) -> CGRect {
        guard let i = client.image, i.size.width > 0, i.size.height > 0 else { return CGRect(origin: .zero, size: zone) }
        let ar = i.size.width / i.size.height
        var w = zone.width, h = w / ar
        if h > zone.height { h = zone.height; w = h * ar }
        return CGRect(x: (zone.width - w) / 2, y: (zone.height - h) / 2, width: w, height: h)
    }

    private func toucher(_ p: CGPoint, cadre: CGRect, fin: Bool) {
        let x = min(max((p.x - cadre.minX) / max(cadre.width, 1), 0), 1)
        let y = min(max((p.y - cadre.minY) / max(cadre.height, 1), 0), 1)
        switch outil {
        case .pointeur:
            let maintenant = Date()
            guard fin || maintenant.timeIntervalSince(dernierEnvoi) > 0.03 else { return }
            dernierEnvoi = maintenant
            client.envoyer(PaquetTelecommande(type: "pointeur", point: fin ? nil : [x, y]), fiable: fin)
        case .crayon, .surligneur, .cercle:
            if traitEnCours == nil { traitEnCours = TraitTelecommande(id: UUID().uuidString, points: [], outil: outil.rawValue) }
            // Le cercle : le point de départ et celui du doigt, l'ellipse entre les deux.
            if outil == .cercle, (traitEnCours?.points.count ?? 0) >= 2 { traitEnCours?.points[1] = [x, y] }
            else { traitEnCours?.points.append([x, y]) }
            let maintenant = Date()
            if fin || maintenant.timeIntervalSince(dernierEnvoi) > 0.05, let t = traitEnCours {
                dernierEnvoi = maintenant
                client.envoyer(PaquetTelecommande(type: "trait", trait: t))
            }
            if fin { traitEnCours = nil }
        }
    }
}

private extension View {
    /// La zone de la diapositive prend le format de son image (16:10 tant qu'il n'y en a pas).
    func aspectRatio(image: UIImage?) -> some View {
        let ar = image.map { $0.size.width / max($0.size.height, 1) } ?? 16 / 10
        return aspectRatio(ar, contentMode: .fit)
    }
}
