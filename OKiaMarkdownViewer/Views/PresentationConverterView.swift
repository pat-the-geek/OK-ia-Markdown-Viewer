import SwiftUI
import WebKit

/// Convertir le rapport ouvert en présentation (1.3) : on choisit le nombre de diapositives, le
/// modèle de l'appareil écrit, l'app assemble et vérifie, et le résultat s'ouvre au diaporama.
/// Le moteur est `ConvertisseurPresentation` ; cet écran ne fait que le piloter et le montrer.
struct PresentationConverterView: View {
    let document: MarkdownDocument
    let titreAffiche: String
    /// Reçoit la présentation à ouvrir au diaporama. Le lecteur l'ouvre une fois cette feuille
    /// refermée : deux présentations modales ne se chevauchent pas.
    var onPresenter: (MarkdownDocument) -> Void

    /// Tenue par le lecteur : la conversion survit à la feuille qu'on referme, à la seconde
    /// partie qui s'efface quand on tourne l'appareil, et reprend là où elle en est.
    @ObservedObject var conversion: ConversionEnCours

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fermerPanneau) private var fermerPanneau
    @ObservedObject private var loc = Localization.shared
    /// Un palier, ou 0 pour « Autre ».
    @State private var choix = 10
    @State private var libre = 12
    /// Calculé une fois : un rapport de plusieurs millions de caractères ne se redécoupe pas à
    /// chaque rafraîchissement de l'écran.
    @State private var maximum = 60

    private static let paliers = [5, 10, 15, 20, 25]
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    private var demande: Int { min(choix == 0 ? libre : choix, maximum) }

    var body: some View {
        NavigationStack {
            Group {
                switch conversion.etat {
                case .reglage:
                    Form { reglage }
                case .echec(let message):
                    Form { echec(message) }
                case .enCours, .fini:
                    // Une seule branche pour les deux états : la vue des vignettes reste la
                    // même de la première diapositive au résultat, rien ne se rend deux fois.
                    VStack(spacing: 0) {
                        entete
                        Divider()
                        ChantierWebView(diapositives: conversion.diapositives,
                                        markdownFinal: conversion.markdownFinal,
                                        prevues: conversion.prevues)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .navigationTitle(tr("Convertir en présentation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Fermer")) { conversion.annuler(); fermer() }
                }
            }
        }
        .tint(orange)
        .task {
            let md = document.text, nom = titreAffiche
            maximum = await Task.detached {
                PlanDiapositives.maximumUtile(RapportDecoupe(markdown: md, titreParDefaut: nom))
            }.value
        }
    }

    /// Dans la seconde partie, « Fermer » la replie ; dans une feuille, la referme.
    private func fermer() { (fermerPanneau ?? { dismiss() })() }

    // MARK: Les quatre états

    @ViewBuilder private var reglage: some View {
        Section {
            Picker(tr("Nombre de diapositives"), selection: $choix) {
                ForEach(Self.paliers, id: \.self) { Text("\($0)").tag($0) }
                Text(tr("Autre")).tag(0)
            }
            .pickerStyle(.segmented)
            if choix == 0 {
                Stepper(tr("%d diapositives", libre), value: $libre, in: 5...max(5, maximum))
            }
        } header: {
            Text(tr("Nombre de diapositives"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                // Mesuré au banc : environ deux secondes et demie par diapositive.
                Text(tr("Environ %d secondes, calculées sur l’appareil.", Int(Double(demande) * 2.5) + 5))
                if (choix == 0 ? libre : choix) > maximum {
                    Text(tr("Ce rapport donne au plus %d diapositives : la conversion s’arrêtera là.", maximum))
                        .foregroundStyle(orange)
                }
            }
        }
        Section {
            Button {
                conversion.lancer(markdown: document.text, titre: titreAffiche, diapositives: demande)
            } label: {
                Label(tr("Convertir"), systemImage: "sparkles")
            }
        } footer: {
            Text(tr("Tout se calcule sur l’appareil, avec Apple Intelligence : le rapport ne quitte pas l’appareil."))
        }
    }

    /// Au-dessus des vignettes : où en est la conversion, puis ce qu'on peut faire du résultat.
    @ViewBuilder private var entete: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch conversion.etat {
            case .enCours(let etape, let total, let section, let titres, let prevues):
                ProgressView(value: Double(max(etape - 1, 0)), total: Double(max(total, 1)))
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Diapositives prêtes : %d sur %d", titres.count, prevues))
                            .font(.subheadline.weight(.semibold))
                            .contentTransition(.numericText())
                            .animation(.easeOut, value: titres.count)
                        Text(tr("Étape %d sur %d", max(etape, 1), max(total, 1)) + " · "
                             + (section.isEmpty ? tr("Ouverture et conclusion") : section))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button(tr("Annuler"), role: .cancel) { conversion.annuler() }
                        .buttonStyle(.bordered)
                }
            case .fini(let r):
                // Une ligne quand la place le permet : en paysage, la hauteur est comptée, et
                // ce sont les vignettes qu'on vient voir.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { compte(r); Spacer(minLength: 4); actions(r) }
                    VStack(alignment: .leading, spacing: 8) { compte(r); HStack(spacing: 10) { actions(r) } }
                }
                if !r.omissions.isEmpty || r.ecartees > 0 {
                    DisclosureGroup(tr("Laissé de côté")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(r.omissions, id: \.self) { Text($0) }
                            if r.ecartees > 0 {
                                Text(tr("Puces écartées faute d’un chiffre présent dans le rapport : %d", r.ecartees))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                    .font(.footnote)
                }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func compte(_ r: ConversionEnCours.Fini) -> some View {
        Label(tr("%d diapositives prêtes", r.diapositives), systemImage: "checkmark.circle")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
    }

    @ViewBuilder private func actions(_ r: ConversionEnCours.Fini) -> some View {
        Button { conversion.reinitialiser() } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(tr("Recommencer"))
        if let url = r.document.sourceURL {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.down") }
                .buttonStyle(.bordered)
                .accessibilityLabel(tr("Enregistrer le fichier .md"))
        }
        Button {
            onPresenter(r.document)
            // Dans une feuille, le diaporama attend qu'elle se referme ; dans la seconde
            // partie, il s'ouvre par-dessus, et les vignettes attendent son retour.
            if fermerPanneau == nil { dismiss() }
        } label: {
            Label(tr("Lancer le diaporama"), systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
    }

    private func echec(_ message: String) -> some View {
        Section {
            Text(message).foregroundStyle(.secondary)
            Button(tr("Réessayer")) {
                conversion.lancer(markdown: document.text, titre: titreAffiche, diapositives: demande)
            }
        }
    }
}

/// L'état de la conversion, tenu hors de la vue : la tâche survit aux rafraîchissements, et
/// l'avancement arrive d'un fil d'exécution qui n'est pas celui de l'interface.
@MainActor
final class ConversionEnCours: ObservableObject {
    struct Fini {
        let document: MarkdownDocument
        let diapositives: Int
        let omissions: [String]
        let ecartees: Int
    }

    enum Etat {
        case reglage
        case enCours(etape: Int, total: Int, section: String, titres: [String], prevues: Int)
        case fini(Fini)
        case echec(String)
    }

    @Published private(set) var etat: Etat = .reglage
    /// Les diapositives prêtes, en Markdown : la vue des vignettes les rend au fur et à mesure.
    @Published private(set) var diapositives: [String] = []
    /// La présentation finie, telle qu'enregistrée : les vignettes s'y alignent une dernière fois.
    @Published private(set) var markdownFinal: String?
    @Published private(set) var prevues = 0
    private var tache: Task<Void, Never>?

    func lancer(markdown: String, titre: String, diapositives: Int) {
        tache?.cancel()
        self.diapositives = []
        markdownFinal = nil
        prevues = diapositives
        etat = .enCours(etape: 0, total: 1, section: "", titres: [], prevues: diapositives)
        #if DEBUG
        // Harnais : le simulateur ne génère pas. OKIA_FAKE_AI rejoue une conversion avec les
        // sections du rapport, une diapositive par seconde, pour éprouver les vignettes.
        if let flag = ProcessInfo.processInfo.environment["OKIA_FAKE_AI"], !flag.isEmpty, flag != "off" {
            simuler(markdown: markdown, titre: titre, diapositives: diapositives)
            return
        }
        #endif
        #if canImport(FoundationModels)
        // L'avancement arrive d'un autre fil : on le ramène sur celui de l'interface, sans jamais
        // retenir l'écran au-delà de sa fermeture.
        let suivi: @Sendable (ConvertisseurPresentation.Avancement) -> Void = { [weak self] a in
            guard let moi = self else { return }
            Task { @MainActor in moi.suivre(a) }
        }
        tache = Task { [weak self] in
            do {
                let r = try await ConvertisseurPresentation().convertir(
                    markdown: markdown, titreParDefaut: titre, diapositives: diapositives, avancement: suivi)
                let document = Self.enregistrer(r)
                self?.markdownFinal = r.markdown
                self?.etat = .fini(Fini(document: document, diapositives: r.diapositives,
                                        omissions: r.omissions.map(Self.texte), ecartees: r.pucesEcartees.count))
            } catch is CancellationError {
                // Annulée par le lecteur : l'écran est déjà revenu au réglage.
            } catch ConvertisseurPresentation.Echec.modeleIndisponible {
                self?.etat = .echec(tr("Apple Intelligence n’est pas disponible sur cet appareil."))
            } catch ConvertisseurPresentation.Echec.rapportVide {
                self?.etat = .echec(tr("Ce document n’a pas de section à présenter."))
            } catch {
                self?.etat = .echec(tr("La conversion a échoué (%@).", error.localizedDescription))
            }
        }
        #else
        etat = .echec(tr("Apple Intelligence n’est pas disponible sur cet appareil."))
        #endif
    }

    /// Une annulation arrivée entre-temps l'emporte : l'avancement ne rouvre pas l'écran de travail.
    private func suivre(_ a: ConvertisseurPresentation.Avancement) {
        guard case .enCours = etat else { return }
        diapositives = a.diapositives
        prevues = a.prevues
        etat = .enCours(etape: a.etape, total: a.total, section: a.section,
                        titres: a.diapositives.map(Self.titreDe), prevues: a.prevues)
    }

    #if DEBUG
    private func simuler(markdown: String, titre: String, diapositives demande: Int) {
        let sections = markdown.components(separatedBy: "\n## ").dropFirst().map { "## " + $0 }
        var diapos = ["# \(titre)\n\nPrésentation factice"]
        for section in sections.prefix(max(demande - 1, 1)) {
            // Hors des blocs de code : un bloc coupé en route avalerait les diapositives suivantes.
            var dansBloc = false
            let lignes = section.components(separatedBy: "\n").filter { ligne in
                if ligne.hasPrefix("```") { dansBloc.toggle(); return false }
                return !dansBloc && !ligne.trimmingCharacters(in: .whitespaces).isEmpty
            }
            diapos.append(lignes.prefix(5).joined(separator: "\n\n"))
        }
        let total = diapos.count
        tache = Task { [weak self] in
            for n in 1...total {
                try? await Task.sleep(for: .seconds(2.5))
                guard let self, !Task.isCancelled, case .enCours = self.etat else { return }
                let pretes = Array(diapos.prefix(n))
                self.diapositives = pretes
                self.prevues = total
                self.etat = .enCours(etape: n, total: total, section: Self.titreDe(diapos[n - 1]),
                                     titres: pretes.map(Self.titreDe), prevues: total)
            }
            guard let self, !Task.isCancelled else { return }
            let md = diapos.joined(separator: "\n\n---\n\n")
            self.markdownFinal = md
            self.etat = .fini(Fini(document: MarkdownDocument(filename: "factice.md", text: md),
                                   diapositives: total, omissions: [], ecartees: 0))
        }
    }
    #endif

    /// Le titre d'une diapositive : sa première ligne, sans les dièses du Markdown.
    nonisolated static func titreDe(_ diapo: String) -> String {
        let premiere = diapo.components(separatedBy: "\n").first ?? ""
        return premiere.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces)
    }

    func annuler() {
        tache?.cancel()
        tache = nil
        reinitialiser()
    }

    func reinitialiser() {
        etat = .reglage
        diapositives = []
        markdownFinal = nil
    }

    #if canImport(FoundationModels)
    /// Ce qui a été laissé de côté, dit dans la langue de l'app. Ce que le modèle écrit d'une
    /// section reste, lui, dans la langue du rapport.
    private static func texte(_ o: ConvertisseurPresentation.Omission) -> String {
        switch o {
        case .sectionEntiere(let t):       return tr("%@ — toute la section, faute de place", t)
        case .partielle(let t, let manque): return "\(t) — \(manque)"
        case .nonConvertie(let t):         return tr("%@ — non convertie : le modèle l’a refusée", t)
        }
    }

    /// La présentation devient un vrai fichier, dans le dossier temporaire : le diaporama l'ouvre
    /// comme n'importe quel document, et « Enregistrer » le propose à l'app Fichiers.
    private static func enregistrer(_ r: ConvertisseurPresentation.Resultat) -> MarkdownDocument {
        let sur = r.titre.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n")).joined(separator: " ")
        let nom = String(sur.prefix(80)).trimmingCharacters(in: .whitespaces) + " — " + tr("présentation") + ".md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nom)
        try? r.markdown.write(to: url, atomically: true, encoding: .utf8)
        return MarkdownDocument(filename: nom, text: r.markdown, sourceURL: url)
    }
    #endif
}

/// La présentation qui se construit : chaque diapositive prête, rendue par le moteur du
/// diaporama — thème, images, cartes, diagrammes —, dans sa vignette, au fur et à mesure.
struct ChantierWebView: UIViewRepresentable {
    var diapositives: [String]
    /// La présentation finie, si elle l'est : elle remplace les diapositives envoyées en route.
    var markdownFinal: String?
    var prevues: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "presentReady")
        controller.addUserScript(WKUserScript(
            source: "window.OKIA_LANG = '\(Localization.shared.code)';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // La page défile elle-même (la grille des vignettes) : la vue native ne bouge pas.
        webView.scrollView.isScrollEnabled = false
        context.coordinator.webView = webView
        if let page = Bundle.main.url(forResource: "presentation", withExtension: "html", subdirectory: "Web")
            ?? Bundle.main.url(forResource: "presentation", withExtension: "html") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let charge: [String: Any] = markdownFinal.map { ["md": $0, "fini": true] }
            ?? ["slides": diapositives, "prevues": prevues, "fini": false]
        context.coordinator.envoyer(charge)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private var pret = false
        private var enAttente: [String: Any]?
        private var dernier: Data?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "presentReady" else { return }
            pret = true
            if let charge = enAttente { enAttente = nil; envoyer(charge) }
        }

        /// N'envoie que ce qui a changé : SwiftUI rappelle `updateUIView` bien plus souvent.
        func envoyer(_ charge: [String: Any]) {
            guard pret, let webView else { enAttente = charge; return }
            guard let data = try? JSONSerialization.data(withJSONObject: charge),
                  data != dernier, let json = String(data: data, encoding: .utf8) else { return }
            dernier = data
            webView.evaluateJavaScript("window.OKIA_PRESENT && window.OKIA_PRESENT.chantier(\(json));")
        }
    }
}
