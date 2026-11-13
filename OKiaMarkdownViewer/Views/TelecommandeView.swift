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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Fermer")) { dismiss() } }
                // Connectée : le titre du diaporama, le chronomètre et le rang dans la barre, une
                // rangée de plus pour la diapositive.
                if case .connecte = client.etat {
                    ToolbarItem(placement: .principal) {
                        Text(client.titre).font(.headline).lineLimit(1)
                    }
                    ToolbarItem(placement: .primaryAction) { compteurs }
                }
            }
            .tint(orange)
        }
        .onAppear {
            client.chercher(); UIApplication.shared.isIdleTimerDisabled = true
            #if DEBUG
            if ProcessInfo.processInfo.environment["OKIA_TELECOMMANDE"] == "pilote" { client.essaiConnecte() }
            #endif
        }
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

    /// La diapositive d'abord (Patrick, 13/11/2026 : « on doit donner plus de place à la
    /// présentation », puis « les boutons peuvent être en liquide glass sur la présentation ») : les
    /// flèches flottent en verre sur la diapositive ; en largeur, elle prend la hauteur entière à
    /// gauche, les outils et les notes en colonne à droite ; en hauteur, toute la largeur, les notes
    /// dans ce qui reste.
    private var pilote: some View {
        GeometryReader { g in
            // Colonne à droite seulement sur un écran très allongé (iPhone en largeur) : sur le Duo
            // ouvert, presque carré, la diapositive est plus grande sur toute la largeur.
            let large = g.size.width > g.size.height * 1.8
            VStack(spacing: 10) {
                if large {
                    HStack(alignment: .top, spacing: 14) {
                        diapositive
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        VStack(spacing: 10) {
                            outils
                            notes
                        }
                        .frame(width: min(300, g.size.width * 0.28))
                    }
                } else {
                    diapositive.layoutPriority(1)
                    outils
                    notes.frame(minHeight: 60)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var compteurs: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { c in
                Text(RepetitionDiaporama.duree(c.date.timeIntervalSince(debut))).monospacedDigit().foregroundStyle(orange)
            }
            Text("\(client.index + 1) / \(max(client.total, 1))").monospacedDigit().foregroundStyle(.secondary)
        }
        .fixedSize()
        .padding(.horizontal, 6)
    }

    private var outils: some View {
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
    }

    private var notes: some View {
        ScrollView {
            Text(client.notes.isEmpty ? tr("Pas de notes pour cette diapositive.") : client.notes)
                .foregroundStyle(client.notes.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Précédente et suivante, en verre, aux coins bas de la diapositive : le pouce les trouve sans
    /// quitter l'image des yeux, et elles ne prennent plus de place sous elle.
    private var navigation: some View {
        HStack {
            bouton("chevron.left", tr("Précédente")) { client.envoyer(PaquetTelecommande(type: "precedente")) }
            Spacer()
            bouton("chevron.right", tr("Suivante")) { client.envoyer(PaquetTelecommande(type: "suivante")) }
        }
        .padding(10)
    }

    private func bouton(_ symbole: String, _ libelle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(orange.opacity(0.75)).interactive(), in: .circle)
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
        .overlay(alignment: .bottom) { navigation }
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
