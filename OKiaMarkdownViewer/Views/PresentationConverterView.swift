import SwiftUI
import WebKit

/// Convertir le rapport ouvert en présentation (1.3) : on choisit le nombre de diapositives, le
/// modèle de l'appareil écrit, l'app assemble et vérifie, et le résultat s'ouvre au diaporama.
/// Le moteur est `ConvertisseurPresentation` ; cet écran ne fait que le piloter et le montrer.
struct PresentationConverterView: View {
    let document: MarkdownDocument
    /// Les surlignages et soulignements du rapport (option Analytic, 1.4) : la conversion les
    /// privilégie, et la présentation reprend ceux qu'elle cite mot pour mot.
    private var marquesDuRapport: [Annotation] {
        guard AchatAnalytic.partage.acces else { return [] }
        return AnnotationsStore.lire(IdentiteDocument(document), document: document)
            .filter { $0.type != .encre && !$0.ancre.exact.isEmpty }
    }
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
                                        prevues: conversion.prevues,
                                        masquees: conversion.masquees,
                                        basculer: { conversion.basculer($0) })
                            .ignoresSafeArea(edges: [.bottom, .horizontal])
                    }
                }
            }
            .navigationTitle(tr("Convertir en présentation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { boutonFermer }
            }
        }
        .tint(orange)
        #if DEBUG
        // Harnais de film : OKIA_DEMO_DIAPORAMA lance le diaporama quelques secondes après la fin
        // de la conversion — la vidéo enchaîne sans qu'on touche l'écran.
        .onChange(of: conversion.markdownFinal) { _, md in
            guard md != nil, ProcessInfo.processInfo.environment["OKIA_DEMO_DIAPORAMA"] != nil,
                  case .fini(let r) = conversion.etat else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { onPresenter(r.document) }
        }
        // Le rejeu des captures démarre seul : aucun geste à scripter.
        .task {
            if ProcessInfo.processInfo.environment["OKIA_CONVERSION_REJEU"] != nil, case .reglage = conversion.etat {
                conversion.lancer(markdown: document.text, titre: titreAffiche, diapositives: demande,
                                 marques: marquesDuRapport)
            }
        }
        #endif
        .task {
            let md = document.text, nom = titreAffiche
            maximum = await Task.detached {
                PlanDiapositives.maximumUtile(RapportDecoupe(markdown: md, titreParDefaut: nom))
            }.value
        }
    }

    private var boutonFermer: some View {
        Button(tr("Fermer")) { conversion.annuler(); fermer() }
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
                conversion.lancer(markdown: document.text, titre: titreAffiche, diapositives: demande,
                                 marques: marquesDuRapport)
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
        Label(tr("%d diapositives prêtes", r.diapositives)
              + (conversion.masquees.isEmpty ? "" : " · " + (conversion.masquees.count == 1
                    ? tr("1 masquée") : tr("%d masquées", conversion.masquees.count))),
              systemImage: "checkmark.circle")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
    }

    @ViewBuilder private func actions(_ r: ConversionEnCours.Fini) -> some View {
        Button { conversion.reinitialiser() } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(tr("Recommencer"))
        if let url = conversion.document(r).sourceURL {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.down") }
                .buttonStyle(.bordered)
                .accessibilityLabel(tr("Enregistrer le fichier .md"))
        }
        Button {
            onPresenter(conversion.document(r))
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
                conversion.lancer(markdown: document.text, titre: titreAffiche, diapositives: demande,
                                 marques: marquesDuRapport)
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
    /// Les diapositives que l'utilisateur a masquées, par leur rang dans la présentation finie.
    @Published private(set) var masquees: Set<Int> = []
    private var tache: Task<Void, Never>?
    /// Les surlignages et soulignements du rapport converti.
    private var marques: [Annotation] = []

    func lancer(markdown: String, titre: String, diapositives: Int, marques: [Annotation] = []) {
        tache?.cancel()
        self.marques = marques
        self.diapositives = []
        markdownFinal = nil
        masquees = []
        prevues = diapositives
        etat = .enCours(etape: 0, total: 1, section: "", titres: [], prevues: diapositives)
        #if DEBUG
        // Harnais des captures : OKIA_CONVERSION_REJEU rejoue une présentation que le vrai modèle a
        // écrite (sur le Mac, avec tools/ConversionBench), diapositive après diapositive. Le contenu
        // est celui du modèle ; seul le rythme est simulé. OKIA_CONVERSION_ARRET fige le rejeu après
        // n diapositives, conversion toujours en cours.
        if let rejeu = ProcessInfo.processInfo.environment["OKIA_CONVERSION_REJEU"], !rejeu.isEmpty {
            rejouer(rejeu, titre: titre,
                    arret: Int(ProcessInfo.processInfo.environment["OKIA_CONVERSION_ARRET"] ?? ""))
            return
        }
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
                    markdown: markdown, titreParDefaut: titre, diapositives: diapositives,
                    marques: marques.map(\.ancre.exact), avancement: suivi)
                let document = Self.enregistrer(r)
                self?.reporterMarques(sur: document)
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
    private func rejouer(_ md: String, titre: String, arret: Int?) {
        let diapos = md.components(separatedBy: "\n---\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let total = diapos.count, jusqua = min(arret ?? total, total)
        prevues = total
        tache = Task { [weak self] in
            for n in 1...max(jusqua, 1) {
                try? await Task.sleep(for: .seconds(0.8))
                guard let self, !Task.isCancelled, case .enCours = self.etat else { return }
                let pretes = Array(diapos.prefix(n))
                self.diapositives = pretes
                self.etat = .enCours(etape: n, total: total, section: Self.titreDe(diapos[n - 1]),
                                     titres: pretes.map(Self.titreDe), prevues: total)
            }
            guard let self, !Task.isCancelled, jusqua == total else { return }
            self.markdownFinal = md
            self.etat = .fini(Fini(document: MarkdownDocument(filename: titre + ".md", text: md),
                                   diapositives: total, omissions: [], ecartees: 0))
        }
    }

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
            // Un vrai fichier, comme la conversion de l'appareil (`enregistrer`) : le diaporama
            // l'ouvre de la même façon.
            let nom = titre + " — " + tr("présentation") + ".md"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(nom)
            try? md.write(to: url, atomically: true, encoding: .utf8)
            let document = MarkdownDocument(filename: nom, text: md, sourceURL: url)
            self.reporterMarques(sur: document)
            self.markdownFinal = md
            self.etat = .fini(Fini(document: document, diapositives: total, omissions: [], ecartees: 0))
        }
    }
    #endif

    /// Les surlignages et soulignements du rapport que la présentation cite mot pour mot y sont
    /// reportés, de la même couleur (Patrick, 30/10/2026 : « fais les 2 »). Ancrés à leur seule
    /// citation : la page les pose sur sa première occurrence. Les notes manuscrites restent au
    /// rapport, faute d'un dessin qui leur corresponde.
    private func reporterMarques(sur d: MarkdownDocument) {
        guard !marques.isEmpty else { return }
        let lu = DiapositivesMasquees.sansEmphase(d.text)
        let reprises = marques.filter { lu.contains($0.ancre.exact) }.map {
            Annotation(type: $0.type, couleur: $0.couleur,
                       ancre: AncreAnnotation(exact: $0.ancre.exact, prefix: "", suffix: ""))
        }
        guard !reprises.isEmpty else { return }
        AnnotationsStore.ecrire(reprises, pour: IdentiteDocument(d))
    }

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
        masquees = []
    }

    /// Masquer ou montrer une diapositive de la présentation finie (Patrick, 28/10/2026). Il en
    /// reste toujours une à montrer. Le fichier enregistré suit : la diapositive y reste, marquée,
    /// et le diaporama la saute.
    func basculer(_ i: Int) {
        guard case .fini(let r) = etat, i >= 0, i < r.diapositives else { return }
        if masquees.contains(i) { masquees.remove(i) }
        else if masquees.count + 1 < r.diapositives { masquees.insert(i) }
        else { return }
        if let url = r.document.sourceURL { try? document(r).text.write(to: url, atomically: true, encoding: .utf8) }
    }

    /// La présentation telle qu'on la lance ou l'enregistre : les diapositives masquées marquées.
    func document(_ r: Fini) -> MarkdownDocument {
        guard !masquees.isEmpty else { return r.document }
        return MarkdownDocument(filename: r.document.filename,
                                text: DiapositivesMasquees.marquer(r.document.text, masquees: masquees),
                                sourceURL: r.document.sourceURL)
    }

    #if canImport(FoundationModels)
    /// Ce qui a été laissé de côté, dit dans la langue de l'app. Ce que le modèle écrit d'une
    /// section reste, lui, dans la langue du rapport.
    private static func texte(_ o: ConvertisseurPresentation.Omission) -> String {
        switch o {
        case .sectionEntiere(let t):       return tr("%@ — toute la section, faute de place", t)
        case .texteSeul(let t):            return tr("%@ — son texte, faute de place ; ses visuels sont repris", t)
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
    /// Une fois finie : les diapositives masquées, et le geste qui masque ou montre.
    var masquees: Set<Int> = []
    var basculer: (Int) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "presentReady")
        controller.add(context.coordinator, name: "masquerDiapo")
        controller.addUserScript(WKUserScript(
            source: Localization.shared.scriptLangue,
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
        context.coordinator.basculer = basculer
        let charge: [String: Any] = markdownFinal.map { ["md": $0, "fini": true, "masquees": masquees.sorted()] }
            ?? ["slides": diapositives, "prevues": prevues, "fini": false]
        context.coordinator.envoyer(charge)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var basculer: (Int) -> Void = { _ in }
        private var pret = false
        private var enAttente: [String: Any]?
        private var dernier: Data?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "masquerDiapo" {
                if let i = (message.body as? [String: Any])?["index"] as? Int { basculer(i) }
                return
            }
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

/// Le marquage des diapositives masquées dans le fichier d'une présentation : un commentaire en tête
/// de la diapositive, que `presentation.js` reconnaît (`MASQUEE`). Le découpage suit celui du
/// diaporama (`splitSlides`) — séparateurs `---` hors des blocs de code, en-tête YAML à part,
/// diapositives vides ignorées —, sinon le rang ne désignerait pas la même diapositive.
enum DiapositivesMasquees {
    static let marque = "<!-- okia:masquee -->"

    /// Un texte Markdown tel qu'il se lit, pour y chercher un passage surligné : sans les astérisques
    /// ni les accents graves de l'emphase, ni les marques des diapositives masquées.
    static func sansEmphase(_ t: String) -> String {
        t.replacingOccurrences(of: marque + "\n", with: "")
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
    }

    static func marquer(_ markdown: String, masquees: Set<Int>) -> String {
        var lignes = markdown.components(separatedBy: "\n")
        var debut = 0
        if lignes.first?.trimmingCharacters(in: .whitespaces) == "---",
           let fin = lignes.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            debut = fin + 1
        }
        // Le premier rang non vide de chaque diapositive, dans l'ordre.
        var tetes: [Int] = [], tete: Int?, cloture: String?
        for i in debut..<lignes.count {
            let t = lignes[i].trimmingCharacters(in: .whitespaces)
            if let c = cloture {
                if t.hasPrefix(c) { cloture = nil }
            } else if t.hasPrefix("```") || t.hasPrefix("~~~") {
                cloture = String(t.prefix(3))
            } else if t.count >= 3, t.allSatisfy({ $0 == "-" }) {
                if let h = tete { tetes.append(h) }
                tete = nil
                continue
            }
            if tete == nil, !t.isEmpty { tete = i }
        }
        if let h = tete { tetes.append(h) }
        for (rang, h) in tetes.enumerated().reversed() where masquees.contains(rang) {
            lignes.insert(marque, at: h)
        }
        return lignes.joined(separator: "\n")
    }
}
