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
    @State private var notesVisibles = false
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    private var connectee: Bool { if case .connecte = client.etat { return true } else { return false } }

    var body: some View {
        GeometryReader { g in
            // Tenue en largeur et connectée : la diapositive bord à bord, tout le reste en verre
            // par-dessus (Patrick, 13/11/2026 : « on doit vraiment essayer de faire de bord à bord »).
            if connectee && g.size.width > g.size.height {
                immersif(marge: max(g.safeAreaInsets.leading, g.safeAreaInsets.trailing))
            } else {
                NavigationStack {
                    Group { if connectee { pilote } else { recherche } }
                        .navigationTitle(tr("Télécommande"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button(tr("Fermer")) { dismiss() } }
                            // Connectée : le titre du diaporama, le chronomètre et le rang dans la
                            // barre, une rangée de plus pour la diapositive.
                            if connectee {
                                ToolbarItem(placement: .principal) {
                                    Text(client.titre).font(.headline).lineLimit(1)
                                }
                                ToolbarItem(placement: .primaryAction) { compteurs }
                            }
                        }
                }
            }
        }
        .tint(orange)
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

    /// Tenue droite : la diapositive bord à bord sur toute la largeur, les flèches en verre sur elle,
    /// les outils et les notes dessous (Patrick, 13/11/2026 : « on doit donner plus de place à la
    /// présentation », « les boutons peuvent être en liquide glass sur la présentation »).
    private var pilote: some View {
        VStack(spacing: 12) {
            diapositive
                .overlay(alignment: .bottom) { navigation }
            outilsVerre
            ScrollView { texteNotes.padding(.horizontal) }
        }
        .padding(.bottom, 8)
    }

    /// Tenue en largeur : la diapositive occupe tout l'écran ; fermer, chronomètre, outils, notes
    /// et flèches flottent en verre par-dessus.
    private func immersif(marge: CGFloat) -> some View {
        // Le noir jusqu'aux bords de l'écran ; la diapositive et les boutons dans la zone sûre, avec
        // la même marge des deux côtés (la plus grande) pour rester centrés : sans quoi les bords de
        // l'iPhone coupaient le compteur et la flèche de droite (Patrick, 13/11/2026 : « attention,
        // mauvais cadrage horizontal »).
        commandesImmersives(diapositive.frame(maxWidth: .infinity, maxHeight: .infinity))
            .padding(.horizontal, marge)
            .ignoresSafeArea(edges: .horizontal)
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
    }

    private func commandesImmersives(_ fond: some View) -> some View {
        fond
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(tr("Fermer"))
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            compteurs.padding(.vertical, 10).padding(.horizontal, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(10)
        }
        .overlay(alignment: .top) {
            if notesVisibles {
                ScrollView { texteNotes.padding(14) }
                    .frame(maxWidth: 520, maxHeight: 160)
                    .fixedSize(horizontal: false, vertical: true)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .padding(.top, 64)
                    .padding(.horizontal, 70)
            }
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .center) {
                bouton("chevron.left", tr("Précédente")) { client.envoyer(PaquetTelecommande(type: "precedente")) }
                Spacer(minLength: 8)
                outilsVerre
                Spacer(minLength: 8)
                bouton("chevron.right", tr("Suivante")) { client.envoyer(PaquetTelecommande(type: "suivante")) }
            }
            .padding(10)
        }
    }

    private var texteNotes: some View {
        Text(client.notes.isEmpty ? tr("Pas de notes pour cette diapositive.") : client.notes)
            .foregroundStyle(client.notes.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Les outils en verre : pointeur, crayon, cercle, surligneur, puis effacer et, en largeur, les
    /// notes à afficher par-dessus la diapositive.
    private var outilsVerre: some View {
        HStack(spacing: 2) {
            ForEach(Outil.allCases) { o in
                Button { outil = o } label: {
                    Image(systemName: o.symbole)
                        .font(.title3)
                        .foregroundStyle(outil == o ? Color.white : Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(outil == o ? orange : Color.clear))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(o.libelle)
                .accessibilityAddTraits(outil == o ? .isSelected : [])
            }
            Divider().frame(height: 26).padding(.horizontal, 4)
            Button { client.envoyer(PaquetTelecommande(type: "effacer")) } label: {
                Image(systemName: "eraser").font(.title3).frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Effacer les traits"))
            Button { notesVisibles.toggle() } label: {
                Image(systemName: notesVisibles ? "text.bubble.fill" : "text.bubble")
                    .font(.title3)
                    .foregroundStyle(client.notes.isEmpty ? Color.secondary : orange)
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Notes de l’orateur"))
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
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
