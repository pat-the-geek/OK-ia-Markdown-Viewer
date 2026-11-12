import SwiftUI
import WebKit

// Option Analytic (1.6) — répéter son diaporama et en tirer un polycopié (Patrick, 13/11/2026 :
// « Rehearse your slideshow: set a target length, and presenter mode times every slide; at the end,
// the time spent on each and where you ran over », « Handouts: the slides and their notes as a PDF,
// one to three per page »).

// MARK: - La répétition

@MainActor
final class RepetitionDiaporama: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var debut = Date()
    @Published private(set) var courante = 0
    @Published private(set) var debutCourante = Date()
    @Published var rapport: Rapport?
    private(set) var dureeVisee: TimeInterval = 600
    private var temps: [Int: TimeInterval] = [:]
    private var total = 1

    static let cleMinutes = "okia.repetition.minutes"

    struct Ligne: Identifiable {
        let index: Int
        let titre: String
        let temps: TimeInterval
        let cible: TimeInterval
        var id: Int { index }
        /// Dépassée de plus de 10 % (et de 5 secondes au moins).
        var depassee: Bool { temps > cible * 1.1 && temps - cible >= 5 }
    }

    struct Rapport: Identifiable {
        let id = UUID()
        let dureeVisee: TimeInterval
        let duree: TimeInterval
        let lignes: [Ligne]
    }

    var cibleParDiapo: TimeInterval { dureeVisee / Double(max(total, 1)) }

    func commencer(minutes: Int, total: Int, depart: Int) {
        dureeVisee = TimeInterval(minutes * 60)
        self.total = max(total, 1)
        temps = [:]
        courante = depart
        debut = Date()
        debutCourante = debut
        active = true
        UserDefaults.standard.set(minutes, forKey: Self.cleMinutes)
    }

    func changer(_ i: Int) {
        guard active, i != courante else { return }
        temps[courante, default: 0] += Date().timeIntervalSince(debutCourante)
        courante = i
        debutCourante = Date()
    }

    func terminer(titres: [String]) {
        guard active else { return }
        temps[courante, default: 0] += Date().timeIntervalSince(debutCourante)
        active = false
        let cible = cibleParDiapo
        let lignes = (0..<total).map { i in
            Ligne(index: i, titre: i < titres.count ? titres[i] : tr("Diapositive %d", i + 1),
                  temps: temps[i] ?? 0, cible: cible)
        }
        rapport = Rapport(dureeVisee: dureeVisee, duree: Date().timeIntervalSince(debut), lignes: lignes)
    }

    func abandonner() { active = false }

    static func duree(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Avant de répéter : la durée visée.
struct RepetitionReglageView: View {
    let total: Int
    var commencer: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    init(total: Int, commencer: @escaping (Int) -> Void) {
        self.total = total
        self.commencer = commencer
        let gardees = UserDefaults.standard.integer(forKey: RepetitionDiaporama.cleMinutes)
        _minutes = State(initialValue: gardees > 0 ? gardees : max(1, total))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $minutes, in: 1...240) {
                        Text(tr("Durée visée : %d min", minutes)).monospacedDigit()
                    }
                } footer: {
                    Text(tr("Le diaporama chronomètre chaque diapositive. À la fin, le temps passé sur chacune et les dépassements, pour %d diapositives (environ %@ chacune).",
                            total, RepetitionDiaporama.duree(Double(minutes * 60) / Double(max(total, 1)))))
                }
            }
            .navigationTitle(tr("Répéter le diaporama"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Commencer")) { dismiss(); commencer(minutes) }.fontWeight(.semibold)
                }
            }
            .tint(orange)
        }
        .presentationDetents([.medium])
    }
}

/// Pendant la répétition : le temps écoulé et celui de la diapositive, en rouge au-delà.
struct BandeauRepetition: View {
    @ObservedObject var repetition: RepetitionDiaporama
    var terminer: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { c in
            let ecoule = c.date.timeIntervalSince(repetition.debut)
            let diapo = c.date.timeIntervalSince(repetition.debutCourante)
            let horsTemps = ecoule > repetition.dureeVisee
            let diapoHors = diapo > repetition.cibleParDiapo
            HStack(spacing: 12) {
                Image(systemName: "stopwatch")
                Text(RepetitionDiaporama.duree(ecoule) + " / " + RepetitionDiaporama.duree(repetition.dureeVisee))
                    .foregroundStyle(horsTemps ? .red : .primary)
                Text("·").foregroundStyle(.secondary)
                Text(tr("Diapositive %d", repetition.courante + 1) + " " + RepetitionDiaporama.duree(diapo)
                     + " / " + RepetitionDiaporama.duree(repetition.cibleParDiapo))
                    .foregroundStyle(diapoHors ? .red : .secondary)
                Button(tr("Terminer"), action: terminer)
                    .fontWeight(.semibold)
                    .buttonStyle(.borderless)
                    .tint(Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255))
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 16).padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

/// À la fin : le temps passé sur chaque diapositive, les dépassements en rouge.
struct RapportRepetitionView: View {
    let rapport: RepetitionDiaporama.Rapport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let ecart = rapport.duree - rapport.dureeVisee
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("%@ pour %@ visées", RepetitionDiaporama.duree(rapport.duree), RepetitionDiaporama.duree(rapport.dureeVisee)))
                            .font(.title3.weight(.semibold)).monospacedDigit()
                        let nonVues = rapport.lignes.filter { $0.temps <= 0 }.count
                        if ecart > 0 {
                            Text(tr("Dépassement de %@", RepetitionDiaporama.duree(ecart))).foregroundStyle(.red)
                        } else if nonVues > 0 {
                            // Arrêtée avant la fin : l'avance ne dit rien.
                            Text(nonVues == 1 ? tr("Arrêtée avant la fin : 1 diapositive non vue")
                                              : tr("Arrêtée avant la fin : %d diapositives non vues", nonVues))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(tr("Dans le temps, %@ d’avance", RepetitionDiaporama.duree(-ecart))).foregroundStyle(.green)
                        }
                    }
                }
                Section {
                    ForEach(rapport.lignes) { l in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(l.index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                            Text(l.titre).lineLimit(2)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(l.temps > 0 ? RepetitionDiaporama.duree(l.temps) : "—")
                                    .monospacedDigit().foregroundStyle(l.depassee ? .red : .primary)
                                if l.depassee {
                                    Text("+" + RepetitionDiaporama.duree(l.temps - l.cible)).font(.caption).monospacedDigit().foregroundStyle(.red)
                                }
                            }
                        }
                    }
                } header: {
                    Text(tr("Diapositive par diapositive"))
                } footer: {
                    Text(tr("Environ %@ par diapositive pour tenir la durée visée.", RepetitionDiaporama.duree(rapport.lignes.first?.cible ?? 0)))
                }
            }
            .navigationTitle(tr("Bilan de la répétition"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("OK")) { dismiss() } } }
        }
    }
}

// MARK: - Le polycopié

/// Le polycopié : chaque diapositive photographiée dans le diaporama, puis mise en page en A4 avec
/// ses notes, une, deux ou trois par page.
@MainActor
enum Polycopie {
    struct Diapo {
        let image: UIImage
        let notes: String
    }

    static func capturer(_ vue: WKWebView, total: Int, avancement: @escaping (Int) -> Void) async -> [Diapo] {
        let depart = (try? await vue.evaluateJavaScript("window.OKIA_PRESENT ? window.OKIA_PRESENT.courante() : 0")) as? Int ?? 0
        var diapos: [Diapo] = []
        for i in 0..<total {
            avancement(i + 1)
            let cadre = (try? await vue.callAsyncJavaScript("return await window.OKIA_PRESENT.preparerCapture(i);",
                                                            arguments: ["i": i], in: nil, contentWorld: .page)) as? [String: Any]
            let notes = (try? await vue.evaluateJavaScript("window.OKIA_PRESENT.notes(\(i))")) as? String ?? ""
            // La diapositive seule, en 16:9 (le cadre que le diaporama a posé pour la photo).
            let reglage = WKSnapshotConfiguration()
            if let c = cadre, let w = (c["w"] as? NSNumber)?.doubleValue, let h = (c["h"] as? NSNumber)?.doubleValue, w > 0, h > 0 {
                reglage.rect = CGRect(x: (c["x"] as? NSNumber)?.doubleValue ?? 0, y: (c["y"] as? NSNumber)?.doubleValue ?? 0,
                                      width: w, height: h)
            }
            if let image = try? await vue.takeSnapshot(configuration: reglage) {
                diapos.append(Diapo(image: image, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        _ = try? await vue.evaluateJavaScript("window.OKIA_PRESENT.finirCapture(); window.OKIA_PRESENT.aller(\(depart), true); 0")
        return diapos
    }

    /// Le PDF A4. Une par page : la diapositive en grand, les notes dessous. Deux : l'une sous l'autre,
    /// chacune avec ses notes. Trois : la diapositive à gauche, ses notes (ou des lignes pour en
    /// prendre) à droite.
    static func pdf(_ diapos: [Diapo], parPage: Int, avecNotes: Bool, titre: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let marge: CGFloat = 40
        let corps = UIFont.systemFont(ofSize: parPage == 1 ? 12 : 10)
        let gris = UIColor(white: 0.35, alpha: 1)
        let pages = stride(from: 0, to: diapos.count, by: parPage).map { Array(diapos[$0..<min($0 + parPage, diapos.count)]) }
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            for (n, lot) in pages.enumerated() {
                ctx.beginPage()
                // En-tête : le titre ; pied : la page.
                (titre as NSString).draw(at: CGPoint(x: marge, y: 18),
                                         withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: gris])
                let pied = "\(n + 1) / \(pages.count)" as NSString
                let tPied = pied.size(withAttributes: [.font: UIFont.systemFont(ofSize: 9)])
                pied.draw(at: CGPoint(x: page.width - marge - tPied.width, y: page.height - 26),
                          withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: gris])
                let zone = CGRect(x: marge, y: 40, width: page.width - 2 * marge, height: page.height - 80)
                let hauteur = zone.height / CGFloat(parPage)
                for (k, d) in lot.enumerated() {
                    let case_ = CGRect(x: zone.minX, y: zone.minY + CGFloat(k) * hauteur, width: zone.width, height: hauteur - 10)
                    let ar = d.image.size.width / max(d.image.size.height, 1)
                    if parPage == 3 {
                        let w = case_.width * 0.52
                        let r = ajuster(ar, CGRect(x: case_.minX, y: case_.minY, width: w, height: case_.height))
                        cadre(d.image, r)
                        let droite = CGRect(x: case_.minX + w + 14, y: case_.minY, width: case_.width - w - 14, height: case_.height)
                        if avecNotes && !d.notes.isEmpty { texte(d.notes, droite, corps) } else { lignes(droite) }
                    } else {
                        // La diapositive sur toute la largeur quand la place le permet, les notes dessous.
                        let hImage = avecNotes && !d.notes.isEmpty ? case_.height * (parPage == 1 ? 0.6 : 0.78) : case_.height
                        var r = ajuster(ar, CGRect(x: case_.minX, y: case_.minY, width: case_.width, height: hImage))
                        r.origin.x = case_.midX - r.width / 2
                        cadre(d.image, r)
                        if avecNotes && !d.notes.isEmpty {
                            texte(d.notes, CGRect(x: case_.minX, y: r.maxY + 10, width: case_.width, height: case_.maxY - r.maxY - 10), corps)
                        }
                    }
                }
            }
        }
    }

    private static func ajuster(_ ar: CGFloat, _ r: CGRect) -> CGRect {
        var w = r.width, h = w / ar
        if h > r.height { h = r.height; w = h * ar }
        return CGRect(x: r.minX, y: r.minY, width: w, height: h)
    }

    private static func cadre(_ image: UIImage, _ r: CGRect) {
        image.draw(in: r)
        let c = UIBezierPath(rect: r)
        UIColor(white: 0.8, alpha: 1).setStroke()
        c.lineWidth = 0.5
        c.stroke()
    }

    private static func texte(_ s: String, _ r: CGRect, _ police: UIFont) {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.paragraphSpacing = 3
        (s as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                             attributes: [.font: police, .paragraphStyle: p, .foregroundColor: UIColor(white: 0.12, alpha: 1)], context: nil)
    }

    /// Des lignes pour prendre des notes.
    private static func lignes(_ r: CGRect) {
        UIColor(white: 0.82, alpha: 1).setStroke()
        var y = r.minY + 22
        while y < r.maxY {
            let l = UIBezierPath()
            l.move(to: CGPoint(x: r.minX, y: y)); l.addLine(to: CGPoint(x: r.maxX, y: y))
            l.lineWidth = 0.5
            l.stroke()
            y += 22
        }
    }
}

/// Avant le polycopié : combien de diapositives par page, avec ou sans les notes.
struct PolycopieReglageView: View {
    var creer: (Int, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("okia.polycopie.parPage") private var parPage = 2
    @AppStorage("okia.polycopie.notes") private var avecNotes = true
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        NavigationStack {
            Form {
                Picker(tr("Diapositives par page"), selection: $parPage) {
                    ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(tr("Avec les notes de l’orateur"), isOn: $avecNotes)
                Text(parPage == 3 ? tr("Trois par page : les notes, ou des lignes pour en prendre, à côté de chaque diapositive.")
                                  : tr("Les notes sous chaque diapositive."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(tr("Polycopié PDF"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Créer")) { dismiss(); creer(parPage, avecNotes) }.fontWeight(.semibold)
                }
            }
            .tint(orange)
        }
        .presentationDetents([.medium])
    }
}
