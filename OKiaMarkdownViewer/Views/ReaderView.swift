import SwiftUI
import WebKit
#if canImport(FoundationModels)
import FoundationModels   // Apple Intelligence on-device model (iOS 26 / macOS 26+)
#endif

/// Displays a rendered Markdown document with a title bar (TOC, search, share, open),
/// an in-document search bar, and the full-screen diagram zoom overlay.
struct ReaderView: View {
    let document: MarkdownDocument
    var onOpen: () -> Void
    var onHome: () -> Void

    @EnvironmentObject private var store: DocumentStore

    @StateObject private var web = ReaderWebController()
    @State private var tapped: TappedDiagram?
    @State private var tappedImage: TappedImage?
    @State private var presenting = false
    @State private var title: String = ""

    @State private var showTOC = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var showShareOptions = false
    @State private var sharePayload: SharePayload?
    @State private var externalLink: ExternalLink?
    @State private var showTextSize = false
    @State private var showSummary = false
    @State private var showChat = false
    /// Conversion en présentation (1.3). La présentation produite attend la fermeture de la
    /// feuille avant de s'ouvrir au diaporama : deux présentations modales ne se chevauchent pas.
    @State private var showConverter = false
    @State private var presentationEnAttente: MarkdownDocument?
    @State private var presentationConvertie: MarkdownDocument?
    /// La conversion en cours, partagée par la feuille et la seconde partie.
    @StateObject private var conversion = ConversionEnCours()
    /// Vrai sur un appareil pliable (Duo) : sa colonne réservée à droite est alors rendue au
    /// texte, au lieu de rester une marge vide sur toute la hauteur.
    @State private var appareilPliable = false
    /// La charnière est ouverte : l'écran intérieur, assez grand pour deux parties.
    @State private var charniereOuverte = false
    /// Partiellement repliée : le système coupe l'écran à la pliure. Sans panneau ouvert, la
    /// partie droite devient la page suivante — le mode livre.
    @State private var charnierePartielle = false
    @StateObject private var livre = LivreController()
    /// En mode livre, la barre s'efface pour rendre toute la place aux deux pages ; un toucher
    /// sur une page la fait revenir, un second la renvoie — comme dans Livres.
    @State private var barreLivreVisible = false
    @State private var paginationLivre = PaginationLivre()
    @State private var tappedCarte: TappedCarte?
    /// Ce que la seconde partie montre, à côté du document ; nil : une seule partie.
    @State private var panneauDuo: PanneauDuo?
    @State private var tailleEcran: CGSize = .zero
    @State private var margeDroite: CGFloat = 0
    @State private var margeGauche: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    @AppStorage("okia.fontScale") private var fontScale: Double = 1.0
    /// Thème de lecture (1.3), retenu comme la taille du texte. Clé d'un `ReaderTheme`.
    @AppStorage("okia.readerTheme") private var readerTheme = ReaderTheme.okia.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var tailleHorizontale
    @AppStorage("okia.autoTranslate") private var autoTranslate = false
    @StateObject private var translator = DocumentTranslator()
    /// Faux quand le lecteur a demandé à revoir l'original. La traduction reste en
    /// mémoire : la bascule ne recalcule rien.
    @State private var afficheTraduction = true
    /// La langue du document, devinée dès le rendu. Elle sert à griser la langue d'arrivée
    /// qui n'aurait rien à traduire, et à annoncer d'où l'on part.
    @State private var langueDetectee: String?
    @ObservedObject private var loc = Localization.shared

    private let minScale = 0.7, maxScale = 2.0, scaleStep = 0.1

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    /// True when the document is made of at least two slides — i.e. it contains a
    /// top-level "---" separator after any YAML frontmatter and outside code fences.
    private var hasSlides: Bool { Self.slideCount(in: document.text) >= 2 }

    static func slideCount(in markdown: String) -> Int {
        var text = markdown
        // Drop a leading YAML frontmatter block.
        if let r = text.range(of: "^---\\r?\\n[\\s\\S]*?\\r?\\n---\\r?\\n?",
                              options: .regularExpression), r.lowerBound == text.startIndex {
            text.removeSubrange(r)
        }
        var separators = 0, content = 0, inFence = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { if !line.isEmpty { content += 1 }; continue }
            if line.range(of: #"^-{3,}$"#, options: .regularExpression) != nil { separators += 1 }
            else if !line.isEmpty { content += 1 }
        }
        return (separators > 0 && content > 0) ? separators + 1 : (content > 0 ? 1 : 0)
    }

    var body: some View {
        #if DUO_SDK && !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) {
            // Duo : le lecteur et, à côté, une seconde partie — de l'autre côté de la pliure quand
            // l'appareil est déplié. L'ArrangementView est toujours là, même vide : changer la
            // structure au moment d'ouvrir la seconde partie recréerait la vue web, et le
            // document repartirait de zéro.
            ArrangementView {
                // Seul, le lecteur prend tout : sans cela, la seconde partie vide gardait sa moitié.
                lecteur
                    .splitArrangementLayoutRatio(deuxParties || modeLivre ? nil : 1)
            } secondary: {
                if let panneau = panneauDuo, deuxParties {
                    secondePartie(panneau)
                } else if modeLivre {
                    PageLivre(livre: livre, surPret: { demarrerLivre() },
                              surToucher: { withAnimation(.easeInOut(duration: 0.2)) { barreLivreVisible.toggle() } },
                              surDiagramme: { tapped = $0 }, surImage: { tappedImage = $0 },
                              surCarte: { tappedCarte = $0 })
                        .ignoresSafeArea(edges: [.bottom, .horizontal])
                }
            }
            .arrangementViewStyle(.split)
            .onChange(of: modeLivre) { _, actif in
                poserCoinLibre()
                if actif { demarrerLivre() } else { arreterLivre() }
            }
            // La barre qui part ou revient change la largeur de la page de gauche : on réaligne.
            .onChange(of: barreLivreVisible) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { demarrerLivre() }
            }
            // La taille de tout l'écran, mesurée hors des parties : mesurer le lecteur ferait
            // osciller la décision — deux parties le réduisent de moitié, il ne serait plus large.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tailleEcran = $0 }
        } else {
            coteACote
        }
        #else
        coteACote
        #endif
    }

    /// Deux parties sans `ArrangementView` — iOS 27.1 n'existe que pour le Duo : un iPhone Pro Max
    /// ou un iPad en paysage, sous iOS 26 et 27.0, met la seconde partie à droite du document. Le
    /// document reste le premier enfant de la pile : l'ouvrir ou la fermer ne recrée pas sa vue web.
    private var coteACote: some View {
        HStack(spacing: 0) {
            lecteur
            if deuxParties, let panneau = panneauDuo {
                Divider().ignoresSafeArea()
                secondePartie(panneau)
                    .frame(width: max(320, tailleEcran.width * 0.4))
            } else if modeLivre {
                // Le livre sur grand écran en paysage : la page de droite prend la moitié.
                PageLivre(livre: livre, surPret: { demarrerLivre() },
                          surToucher: { withAnimation(.easeInOut(duration: 0.2)) { barreLivreVisible.toggle() } },
                              surDiagramme: { tapped = $0 }, surImage: { tappedImage = $0 },
                              surCarte: { tappedCarte = $0 })
                    .frame(width: tailleEcran.width / 2)
                    .ignoresSafeArea(edges: [.bottom, .horizontal])
            }
        }
        .onChange(of: modeLivre) { _, actif in
                poserCoinLibre()
                if actif { demarrerLivre() } else { arreterLivre() }
            }
        .onChange(of: barreLivreVisible) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { demarrerLivre() }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tailleEcran = $0 }
    }

    /// Le lecteur, sous la barre d'outils du système : le titre, la maison, les commandes en
    /// groupes de Liquid Glass — l'allure d'une app iOS ou macOS, sur le modèle de fornews, et
    /// non plus celle d'une page web. Le document défile sous la barre, que le système voile.
    private var lecteur: some View {
        NavigationStack {
        ZStack(alignment: .top) {
            MarkdownWebView(document: document, tapped: $tapped, tappedImage: $tappedImage,
                            onTitle: { title = $0 },
                            webController: web, onExternalLink: handleExternalLink,
                            // Le Duo ne compte pas toute la rangée du titre dans la marge de la vue
                            // web : on lui donne ce qui manque, pour que la page défile sous le verre
                            // sans s'y cacher.
                            topInset: appareilPliable ? margeHauteDuo : 0)
                // La page passe sous la barre, où le défilement se voile ; sur le Duo, aussi sous la
                // colonne de droite, où le système range les commandes. Ailleurs, la marge latérale
                // protège l'encoche de la caméra.
                .ignoresSafeArea(edges: appareilPliable ? [.top, .bottom, .horizontal] : [.top, .bottom])
            // Le haut réel du contenu, sous la barre : sur le Duo, la vue web n'en reçoit qu'une
            // partie dans sa marge, et le haut du document se cachait sous la rangée du titre.
            Color.clear
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { barHeight = proxy.frame(in: .global).minY }
                            .onChange(of: proxy.frame(in: .global).minY) { _, h in barHeight = h }
                    }
                )
                .allowsHitTesting(false)
            #if DUO_SDK && !targetEnvironment(macCatalyst)
            .background {
                if #available(iOS 27.1, *) {
                    DetecteurCharniere { pliable, ouverte, partielle in
                        appareilPliable = pliable
                        charniereOuverte = ouverte
                        charnierePartielle = partielle
                    }
                        .frame(width: 0, height: 0)
                }
            }
            #endif
            .onChange(of: appareilPliable) { _, _ in poserCoinLibre() }
            .onChange(of: margeDroite) { _, _ in poserCoinLibre() }
            .onChange(of: margeGauche) { _, _ in poserCoinLibre() }
            .onChange(of: barHeight) { _, _ in poserCoinLibre() }

            TranslationHostView(translator: translator)
        }
        .safeAreaInset(edge: .top, spacing: 0) { bandeauTraduction }
        .navigationTitle(title.isEmpty ? document.filename : title)
        .navigationBarTitleDisplayMode(.inline)
        // Sur Mac, une barre « éditeur » se range dans la barre de la fenêtre.
        .toolbarRole(.editor)
        .toolbar { barreOutils }
        .toolbar(modeLivre && !barreLivreVisible ? .hidden : .automatic, for: .navigationBar, .bottomBar)
        // La recherche du système, réduite à un bouton tant qu'on ne cherche pas.
        .searchable(text: $searchText, isPresented: $isSearching, prompt: tr("Rechercher dans le document"))
        .searchToolbarBehavior(.minimize)
        .onSubmit(of: .search) { web.searchNext() }
        .onChange(of: searchText) { _, q in web.search(q) }
        .onChange(of: isSearching) { _, actif in
            if !actif { searchText = ""; web.clearSearch() }
        }
        }
        .fullScreenCover(item: $tapped) { diagram in
            DiagramZoomView(diagram: diagram)
        }
        .fullScreenCover(item: $tappedImage) { image in
            ImageZoomView(image: image)
        }
        .fullScreenCover(item: $tappedCarte) { carte in
            CarteZoomView(carte: carte)
        }
        .fullScreenCover(isPresented: $presenting) {
            // Le diaporama reçoit le traducteur du lecteur, pas un neuf : sa mémoire
            // porte déjà tout ce que la lecture a traduit, et la même diapositive ne se
            // paiera pas une seconde fois.
            PresentationView(document: document,
                             memoireHeritee: translator.memoire,
                             langueSource: translator.demandeSource,
                             traduire: traductionActive)
        }
        #if DEBUG
        // OKIA_DUO_PANNEAU ouvre la seconde partie du Duo au lancement : sommaire, resume, discussion.
        .onAppear {
            // OKIA_ORIENTATION=paysage tourne l'app en paysage, pour essayer les deux parties d'un
            // grand écran sans toucher au simulateur (l'écran du Mac peut être verrouillé).
            #if !targetEnvironment(macCatalyst)
            if ProcessInfo.processInfo.environment["OKIA_ORIENTATION"] == "paysage",
               let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
                // L'iPad ignore la demande ci-dessus (app multitâche) : on tourne l'appareil lui-même.
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
            // « portrait » remet droit un simulateur qu'un essai précédent a laissé couché.
            if ProcessInfo.processInfo.environment["OKIA_ORIENTATION"] == "portrait",
               let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
            #endif
            // OKIA_THEME fixe le thème de lecture ; OKIA_APPARENCE ouvre le panneau « Aa » — les
            // captures des thèmes, sans toucher à l'écran.
            if let theme = ProcessInfo.processInfo.environment["OKIA_THEME"], ReaderTheme(rawValue: theme) != nil {
                readerTheme = theme
            }
            // OKIA_FONT_SCALE fixe la taille du texte le temps des captures, en gardant de côté celle
            // de l'utilisateur ; « restaurer » la lui rend. Le conteneur de l'app est protégé : le
            // script ne peut pas la rétablir lui-même.
            if let echelle = ProcessInfo.processInfo.environment["OKIA_FONT_SCALE"] {
                let cle = "okia.fontScale.avantCapture", d = UserDefaults.standard
                if echelle == "restaurer" {
                    if d.object(forKey: cle) != nil { fontScale = d.double(forKey: cle); d.removeObject(forKey: cle) }
                } else if let v = Double(echelle) {
                    if d.object(forKey: cle) == nil { d.set(fontScale, forKey: cle) }
                    fontScale = v
                }
            }
            if ProcessInfo.processInfo.environment["OKIA_APPARENCE"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showTextSize = true }
            }
            switch ProcessInfo.processInfo.environment["OKIA_DUO_PANNEAU"] {
            case "sommaire":   panneauDuo = .sommaire
            case "resume":     panneauDuo = .resume
            case "discussion": panneauDuo = .discussion
            case "conversion": panneauDuo = .conversion
            default: break
            }
        }
        // Harnais de capture (Debug uniquement, absent du binaire livré) : OKIA_OPEN_SLIDES
        // ouvre le diaporama dès l'affichage, ce qu'aucune variable ne savait faire — la
        // présentation n'était atteignable que par un bouton, donc impossible à capturer
        // sans piloter l'interface.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if env["OKIA_OPEN_SLIDES"] != nil && hasSlides {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { presenting = true }
            }
            // OKIA_AI ouvre le résumé, la discussion ou la conversion au lancement. Le contenu
            // affiché reste celui du vrai modèle : le harnais ouvre la porte, il n'écrit pas la
            // réponse — contrairement à OKIA_FAKE_AI, dont le texte est fabriqué et n'a
            // donc rien à faire sur une capture publiée.
            // « convert » ouvre la conversion en présentation, dont l'entrée est un menu qu'on ne
            // pilote pas en arrière-plan. OKIA_AI_DELAY la retarde (en secondes), le temps de
            // filmer le rapport qu'on parcourt avant.
            let delai = Double(env["OKIA_AI_DELAY"] ?? "") ?? 0.5
            switch env["OKIA_AI"] {
            case "summary": DispatchQueue.main.asyncAfter(deadline: .now() + delai) { ouvrir(.resume) }
            case "chat":    DispatchQueue.main.asyncAfter(deadline: .now() + delai) { ouvrir(.discussion) }
            case "convert": DispatchQueue.main.asyncAfter(deadline: .now() + delai) { ouvrir(.conversion) }
            default: break
            }
        }
        #endif
        .sheet(isPresented: $showTOC) {
            TableOfContentsView(items: web.toc) { item in web.scrollToHeading(item.id) }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .sheet(isPresented: $showSummary) {
            DocumentSummaryView(sourceTitle: title.isEmpty ? document.filename : title,
                                sourceMarkdown: document.text)
        }
        .sheet(isPresented: $showChat) {
            DocumentChatView(sourceTitle: title.isEmpty ? document.filename : title,
                             sourceMarkdown: document.text)
        }
        .sheet(isPresented: $showConverter, onDismiss: {
            if let d = presentationEnAttente { presentationEnAttente = nil; presentationConvertie = d }
        }) {
            PresentationConverterView(document: document,
                                      titreAffiche: title.isEmpty ? document.filename : title,
                                      onPresenter: { d in presentationEnAttente = d },
                                      conversion: conversion)
        }
        // La présentation convertie est un document neuf, dans la langue du rapport : rien à
        // hériter de la traduction du lecteur.
        .fullScreenCover(item: $presentationConvertie) { d in
            PresentationView(document: d, memoireHeritee: [:], langueSource: nil, traduire: false)
        }
#if !targetEnvironment(macCatalyst)
        .sheet(item: $externalLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
#endif
        .confirmationDialog(tr("Partager"), isPresented: $showShareOptions, titleVisibility: .visible) {
            Button(tr("Exporter en PDF")) { exportPDF() }
            Button(tr("Exporter en Word (.docx)")) { exportWord() }
            Button(tr("Partager le Markdown (.md)")) { shareMarkdown() }
            Button(tr("Annuler"), role: .cancel) {}
        }
        // Reset transient UI when the document changes.
        .onChange(of: document.id) { _, _ in
            isSearching = false; searchText = ""; web.clearSearch(); showTOC = false
            conversion.annuler()
            if panneauDuo == .conversion { panneauDuo = nil }
        }
        .onChange(of: translator.state) { _, etat in
            // La barre du lecteur montre le titre du document : quand le document passe
            // en allemand, elle le suit. Le coffre et les Récents, eux, indexent des
            // fichiers par leur nom — ils ne bougent pas, sans quoi le même document
            // apparaîtrait sous deux noms selon un réglage.
            if case .finished = etat {
                web.titreCourant { t in if !t.isEmpty { title = t } }
            }
        }
        .onChange(of: fontScale) { _, v in web.setFontScale(v) }
        .onChange(of: readerTheme) { _, v in web.setTheme(v) }
        // `[web]` est explicite : la tâche tient le contrôleur le temps de s'exécuter — il le
        // faut bien pour former les captures `[weak web]` ci-dessous —, et Swift 27 demande
        // qu'on le dise. Les fermetures confiées au traducteur, elles, restent faibles.
        .task { [web] in
            web.setTheme(readerTheme)
            web.setFontScale(fontScale)
            // Chaque bloc traduit se réécrit dès qu'il arrive : le document se traduit
            // sous les yeux du lecteur au lieu d'apparaître d'un coup après l'attente.
            translator.onBloc = { [weak web] bloc in web?.appliquerTraduction(bloc) }
            translator.extras = { [weak web] in await web?.collecterExtras() ?? [] }
            translator.onExtras = { [weak web] table in web?.appliquerExtras(table) }
            web.onRendered = { analyserPuisTraduire() }
        }
        // Changer de langue ou décocher l'option en cours de lecture doit se voir tout de
        // suite : c'est le même document, il n'y aura pas de nouveau rendu pour rattraper.
        .onChange(of: autoTranslate) { _, actif in
            if actif { traduireSiDemandé() } else { translator.annuler(); web.restaurerOriginaux() }
        }
        .onChange(of: loc.language) { _, _ in
            translator.annuler()
            web.restaurerOriginaux()
            traduireSiDemandé()
        }
        // An App Intent (Siri/Shortcuts) asked to summarise the opened report.
        .onAppear {
            if store.summaryRequested { showSummary = true; store.summaryRequested = false }
        }
        .onChange(of: store.summaryRequested) { _, requested in
            if requested { showSummary = true; store.summaryRequested = false }
        }
    }

    // MARK: Traduction

    /// Une traduction automatique se signale — comme le résumé le fait déjà — et
    /// l'original reste à un geste. Le bandeau dit trois choses et pas une de plus :
    /// que le texte est traduit, d'où il vient, et que rien n'est sorti de l'appareil.
    @ViewBuilder private var bandeauTraduction: some View {
        switch translator.state {
        case .attente(let source, let cible):
            bandeauProposition(source: source, cible: cible)
        case .running(let faits, let total):
            bandeau(progression: total > 0 ? Double(faits) / Double(total) : 0,
                    texte: tr("Traduction en cours…"))
        case .finished(_, let echecs):
            bandeau(progression: nil,
                    texte: echecs == 0
                        ? tr("Traduit sur l’appareil · %@", nomLangueSource)
                        : tr("Traduit, sauf %d passage", echecs))
        default:
            EmptyView()
        }
    }

    /// Le bandeau qui demande avant de télécharger. Il dit le prix — un dictionnaire à
    /// récupérer — plutôt que de laisser une invite système l'annoncer à sa place.
    private func bandeauProposition(source: String, cible: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(orange)
            Text(tr("Ce document est en %@. Le traduire en %@ demande un téléchargement.",
                    nomDeLangue(source), nomDeLangue(cible)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(tr("Traduire")) { accepterTraduction(cible: cible) }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func bandeau(progression: Double?, texte: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "character.book.closed")
                    .font(.caption)
                    .foregroundStyle(orange)
                Text(texte)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(afficheTraduction ? tr("Voir l’original") : tr("Voir la traduction")) {
                    afficheTraduction.toggle()
                    web.afficherTraduction(afficheTraduction)
                    // Les diagrammes et les marqueurs suivent : un document « original »
                    // qui garderait ses libellés traduits ne serait pas l'original.
                    if afficheTraduction { web.reappliquerExtras() } else { web.restaurerExtras() }
                    web.titreCourant { t in if !t.isEmpty { title = t } }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)

            // La barre du diaporama, au même trait : elle se remplit et disparaît à la
            // fin. Elle mesure des caractères et non des blocs — un titre et un
            // paragraphe de trente lignes ne pèsent pas pareil, et une barre qui avance
            // par à-coups ne dit rien du temps restant.
            if let p = progression {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(orange)
                        .frame(width: proxy.size.width * max(0, min(1, p)))
                        .animation(.linear(duration: 0.25), value: p)
                }
                .frame(height: 2)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    /// Le nom de la langue d'origine, dit dans la langue du lecteur.
    private var nomLangueSource: String {
        guard let code = translator.demandeSource else { return "" }
        let locale = Locale(identifier: Localization.shared.code)
        let nom = locale.localizedString(forLanguageCode: code) ?? code
        // « français » en début de segment se capitalise, comme le fait le système.
        return nom.prefix(1).uppercased() + nom.dropFirst()
    }


    /// Décide s'il y a lieu de traduire, et lance la vague. Trois refus possibles, et
    /// chacun est un refus rapide : l'option est éteinte, le document est déjà dans la
    /// langue du lecteur, ou l'appareil ne sait pas faire cette paire.
    /// L'option, telle qu'elle vaut vraiment. Le harnais existe parce qu'une app
    /// sandboxée ne voit pas les préférences écrites de l'extérieur : un lancement
    /// scripté n'a que l'environnement pour cocher la case. Il ouvre la porte, il
    /// n'invente pas de traduction — le texte affiché reste celui du vrai modèle.
    /// Le nom ne doit ressembler à aucun objet livré : `window.OKIA.translation` est
    /// une API de production, et c'est cette confusion-là qui avait bloqué toute
    /// livraison du temps de OKIA_PRESENT.
    private var traductionActive: Bool {
        #if DEBUG
        if let forcee = ProcessInfo.processInfo.environment["OKIA_AUTO_TR"], !forcee.isEmpty {
            return forcee != "off"
        }
        #endif
        return autoTranslate
    }

    /// Le lecteur a accepté le téléchargement : on repart d'une collecte fraîche plutôt
    /// que de rejouer celle de tout à l'heure, qu'une recherche entre-temps aurait pu
    /// rendre caduque.
    private func accepterTraduction(cible: String) {
        guard case .attente(let source, _) = translator.state else { return }
        web.collecterTraduisible { blocs, defilement in
            guard !blocs.isEmpty else { return }
            afficheTraduction = true
            translator.demarrer(blocs: blocs, defilement: defilement,
                                source: source, cible: cible)
        }
    }

    /// La langue d'arrivée en cours, ou celle des réglages tant que rien n'a été demandé.
    private var cibleActive: String { translator.demandeCible ?? Localization.shared.code }

    /// Le nom d'une langue, dit dans celle du lecteur, première lettre en capitale.
    private func nomDeLangue(_ code: String) -> String {
        let locale = Locale(identifier: Localization.shared.code)
        let nom = locale.localizedString(forLanguageCode: code) ?? code
        return nom.prefix(1).uppercased() + nom.dropFirst()
    }

    /// Traduire vers la langue demandée depuis le bouton, que l'option automatique soit
    /// active ou non — c'est un geste explicite, il n'a pas à passer par les Réglages.
    private func traduireVers(_ cible: String) {
        web.collecterTraduisible { blocs, defilement in
            guard !blocs.isEmpty,
                  let source = langueDetectee ?? DocumentTranslator.langue(de: blocs),
                  source != cible else { return }
            Task { @MainActor in
                switch await DocumentTranslator.aptitude(de: source, vers: cible) {
                case .impossible:
                    return
                case .aTelecharger, .pret:
                    // Pas de bandeau ici : le lecteur vient de désigner une langue, son
                    // geste vaut demande. Si un dictionnaire manque, c'est l'invite du
                    // système qui le dira — la doubler serait demander deux fois.
                    // La mémoire est indexée par le texte d'origine seulement : changer de
                    // langue d'arrivée sans l'oublier reposerait de l'allemand sur un
                    // document qu'on vient de demander en espagnol.
                    if translator.demandeCible != cible { translator.oublier() }
                    afficheTraduction = true
                    translator.demarrer(blocs: blocs, defilement: defilement,
                                        source: source, cible: cible)
                }
            }
        }
    }

    /// Devine la langue du document dès le rendu — pour le bouton — puis traduit si
    /// l'option automatique le demande. Une seule collecte sert aux deux.
    private func analyserPuisTraduire() {
        let cible = Localization.shared.code
        web.collecterTraduisible { blocs, defilement in
            guard !blocs.isEmpty else { langueDetectee = nil; return }
            let source = DocumentTranslator.langue(de: blocs)
            langueDetectee = source
            guard traductionActive, let source, source != cible else { return }
            Task { @MainActor in
                switch await DocumentTranslator.aptitude(de: source, vers: cible) {
                case .impossible: return
                case .aTelecharger: translator.attendre(source: source, cible: cible)
                case .pret:
                    afficheTraduction = true
                    translator.demarrer(blocs: blocs, defilement: defilement,
                                        source: source, cible: cible)
                }
            }
        }
    }

    private func traduireSiDemandé() {
        guard traductionActive else { return }
        let cible = Localization.shared.code
        web.collecterTraduisible { blocs, defilement in
            guard !blocs.isEmpty else { return }
            guard let source = DocumentTranslator.langue(de: blocs) else { return }
            // Un document déjà dans la langue du lecteur n'a rien à gagner à un
            // aller-retour par le modèle, qui le réécrirait sans le traduire.
            guard source != cible else { return }
            Task { @MainActor in
                // `status(from:to:)` fait foi et répond en quelques dizaines de
                // millisecondes ; il évite d'ouvrir une session qui ne mènerait à rien.
                afficheTraduction = true
                switch await DocumentTranslator.aptitude(de: source, vers: cible) {
                case .impossible:
                    return
                case .pret:
                    translator.demarrer(blocs: blocs, defilement: defilement,
                                        source: source, cible: cible)
                case .aTelecharger:
                    // Le dictionnaire manque. Le télécharger fait tomber une invite
                    // système : elle doit répondre à un geste, pas surprendre un lecteur
                    // au milieu d'une page. On propose, on n'impose pas.
                    translator.attendre(source: source, cible: cible)
                }
            }
        }
    }

    // MARK: Title bar

    /// Plus de coin à contourner. Il réservait, en haut de la page, la place de la caméra et de
    /// l'heure du Duo quand notre barre flottait sur la page ; la barre du système range
    /// désormais ses commandes dans la colonne réservée, et la page garde les marges que le
    /// système lui donne. Le coin, lui, rognait le titre et les images : de la place perdue.
    private func poserCoinLibre() {
        web.setCoinLibre(largeur: 0, hauteur: 0)
        // Sur le Duo, barre visible, la page passe sous la colonne du système et n'en garde que
        // la place des boutons de verre (44 points et leur respiration) ; le livre gère la sienne.
        web.setMargeOutils(appareilPliable && !modeLivre ? 52 : 0)
    }

    /// L'écran a-t-il la place de deux parties ? Le Duo déplié, de part et d'autre de sa pliure ;
    /// ailleurs, un grand écran en paysage — iPhone Pro Max, iPad : au moins 800 points de large,
    /// plus large que haut. Un iPhone en portrait, ou le Duo plié, n'en a pas la place.
    private var deuxPartiesPossibles: Bool {
        #if targetEnvironment(macCatalyst)
        // Le Mac, dès que sa fenêtre est assez large : la conversion, le résumé et la discussion
        // s'ouvrent à côté du document. Une fenêtre étroite garde ses feuilles.
        return tailleEcran.width >= 900
        #else
        if appareilPliable { return charniereOuverte }
        return tailleEcran.width > tailleEcran.height && tailleEcran.width >= 800
        #endif
    }

    /// Ce que la marge native de la vue web ne couvre pas de la barre, sur le Duo.
    private var margeHauteDuo: CGFloat {
        max(0, barHeight - (web.webView?.scrollView.safeAreaInsets.top ?? 0))
    }

    /// Le mode livre : le Duo partiellement replié, ou un iPad ou un grand iPhone en paysage, sans
    /// panneau ouvert. La partie droite montre la suite du document, et l'on tourne les doubles
    /// pages d'un balayage.
    private var modeLivre: Bool {
        guard panneauDuo == nil else { return false }
        if appareilPliable { return charnierePartielle }
        // iPad et grand iPhone tenus en paysage : deux pages côte à côte, comme un livre ouvert.
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return deuxPartiesPossibles
        #endif
    }

    /// Ouvre le livre : la page de gauche envoie sa copie à celle de droite, les deux prennent la
    /// même largeur de texte — la plus petite des deux —, puis leur défilement se lie.
    private func demarrerLivre() {
        guard modeLivre else { return }
        let livre = self.livre, web = self.web, pagination = paginationLivre
        web.onMiroir = { livre.poser($0); pagination.recalculerPlusTard() }
        web.onRecouper = { pagination.recalculerPlusTard() }
        web.onTapPage = { withAnimation(.easeInOut(duration: 0.2)) { barreLivreVisible.toggle() } }
        web.onCarte = { tappedCarte = $0 }
        web.suivreMiroir(true)
        web.largeurNaturelle { a in
            livre.largeurNaturelle { b in
                let largeur = min(a, b)
                if largeur > 0 {
                    web.setLargeurLivre(largeur)
                    livre.setLargeurLivre(largeur)
                }
                // Le temps que la copie se pose et se mette en page.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    pagination.relier(gauche: web.webView, droite: livre.webView)
                }
            }
        }
    }

    private func arreterLivre() {
        paginationLivre.delier()
        web.onTapPage = nil
        barreLivreVisible = false
        web.suivreMiroir(false)
        web.onMiroir = nil
        web.onRecouper = nil
        web.setLargeurLivre(0)
    }

    /// Deux parties : quand l'écran en a la place et qu'une seconde partie est demandée.
    private var deuxParties: Bool { deuxPartiesPossibles && panneauDuo != nil }

    /// Ouvre le sommaire, le résumé ou la discussion : dans la seconde partie quand l'écran en a la
    /// place — à côté du document, qu'on continue de lire — sinon dans une feuille, comme avant.
    private func ouvrir(_ panneau: PanneauDuo) {
        if deuxPartiesPossibles {
            panneauDuo = panneau
            return
        }
        switch panneau {
        case .sommaire:   showTOC = true
        case .resume:     showSummary = true
        case .discussion: showChat = true
        case .conversion: showConverter = true
        }
    }

    /// La seconde partie du Duo.
    @ViewBuilder private func secondePartie(_ panneau: PanneauDuo) -> some View {
        Group {
            switch panneau {
            case .sommaire:
                TableOfContentsView(items: web.toc) { item in web.scrollToHeading(item.id) }
            case .resume:
                DocumentSummaryView(sourceTitle: title.isEmpty ? document.filename : title,
                                    sourceMarkdown: document.text)
            case .discussion:
                DocumentChatView(sourceTitle: title.isEmpty ? document.filename : title,
                                 sourceMarkdown: document.text)
            case .conversion:
                // La présentation se construit à côté du rapport, qu'on continue de lire.
                PresentationConverterView(document: document,
                                          titreAffiche: title.isEmpty ? document.filename : title,
                                          onPresenter: { d in presentationConvertie = d },
                                          conversion: conversion)
            }
        }
        .environment(\.fermerPanneau, { panneauDuo = nil })
    }

    private var boutonAccueil: some View {
        Button(action: onHome) { Image(systemName: "house") }
            .accessibilityLabel(tr("Écran d’accueil"))
    }

    /// La barre d'outils du système. Les commandes y vont par groupes — chacun sa capsule de
    /// Liquid Glass —, en icônes monochromes, comme dans fornews. Sur un iPhone tenu droit, trois
    /// icônes, et le reste dans un menu « … » : iOS laisse tomber sans rien dire ce qui ne tient
    /// pas dans la barre.
    @ToolbarContentBuilder private var barreOutils: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { boutonAccueil.teinteBarre() }
        if isSearching {
            // Pendant une recherche : le compte et les flèches, rien d'autre.
            ToolbarItemGroup(placement: .primaryAction) {
                Text(web.searchResult.count > 0 ? "\(web.searchResult.index)/\(web.searchResult.count)"
                                                : (searchText.isEmpty ? "" : "0"))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { web.searchPrev() } label: { Image(systemName: "chevron.up") }
                    .disabled(web.searchResult.count == 0)
                    .accessibilityLabel(tr("Précédent"))
                Button { web.searchNext() } label: { Image(systemName: "chevron.down") }
                    .disabled(web.searchResult.count == 0)
                    .accessibilityLabel(tr("Suivant"))
            }
        } else if tailleHorizontale == .compact {
            ToolbarItemGroup(placement: .primaryAction) {
                boutonIntelligence
                boutonApparence
                menuPlus
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                if hasSlides { boutonDiaporama }
                boutonIntelligence
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                boutonApparence
                boutonSommaire
                if langueDetectee != nil { menuTraduction }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                boutonPartage
                boutonOuvrir
            }
        }
    }

    // MARK: Les commandes

    private var boutonDiaporama: some View {
        // Diaporama — present the document as full-screen slides (split on "---").
        Button { presenting = true } label: { Image(systemName: "play.rectangle") }
            .teinteBarre()
            .accessibilityLabel(tr("Diaporama"))
    }

    /// Apple Intelligence — résumé, discussion et conversion sous un seul glyphe. Le menu entier
    /// disparaît quand le modèle de l'appareil n'est pas disponible : ni entrée grisée, ni
    /// feuille qui ne ferait qu'échouer.
    @ViewBuilder private var boutonIntelligence: some View {
        if DocumentSummarizer.isAvailable {
            Menu {
                Button { ouvrir(.resume) } label: {
                    Label(tr("Résumé du document"), systemImage: "doc.text")
                }
                Button { ouvrir(.discussion) } label: {
                    Label(tr("Discuter avec le document"), systemImage: "text.bubble")
                }
                Button { ouvrir(.conversion) } label: {
                    Label(tr("Convertir en présentation"), systemImage: "rectangle.on.rectangle.angled")
                }
            } label: {
                Image(systemName: "apple.intelligence")
            }
            .teinteBarre()
            .accessibilityLabel("Apple Intelligence")
        }
    }

    private var boutonApparence: some View {
        Button { showTextSize = true } label: { Image(systemName: "textformat.size") }
            .teinteBarre()
            .accessibilityLabel(tr("Apparence"))
            .popover(isPresented: $showTextSize) {
                appearanceControls
                    .presentationCompactAdaptation(.popover)
            }
    }

    private var boutonSommaire: some View {
        Button { ouvrir(.sommaire) } label: { Image(systemName: "list.bullet") }
            .teinteBarre()
            .disabled(web.toc.isEmpty)
            .accessibilityLabel(tr("Sommaire (accessibilité)"))
    }

    private var boutonPartage: some View {
        Button { showShareOptions = true } label: { Image(systemName: "square.and.arrow.up") }
            .teinteBarre()
            .accessibilityLabel(tr("Partager"))
    }

    private var boutonOuvrir: some View {
        Button(action: onOpen) { Image(systemName: "folder") }
            .teinteBarre()
            .accessibilityLabel(tr("Ouvrir un fichier"))
    }

    /// Traduire — le geste ponctuel, à côté du réglage qui, lui, traduit tout seul. Il n'apparaît
    /// que si l'appareil sait traduire ET que la langue du document est connue.
    @ViewBuilder private var menuTraduction: some View {
        if let source = langueDetectee {
            Menu {
                elementsTraduction(source)
            } label: {
                Image(systemName: "character.book.closed")
            }
            .teinteBarre()
            .accessibilityLabel(tr("Traduire"))
        }
    }

    @ViewBuilder private func elementsTraduction(_ source: String) -> some View {
        Section(tr("Traduire depuis %@", nomDeLangue(source))) {
            ForEach(AppLanguage.allCases.filter { $0 != .system }) { langue in
                Button {
                    traduireVers(langue.rawValue)
                } label: {
                    Label {
                        Text("\(langue.drapeau)  \(langue.nativeName)")
                    } icon: {
                        if cibleActive == langue.rawValue { Image(systemName: "checkmark") }
                    }
                }
                .disabled(langue.rawValue == source)
            }
        }
        if translator.demandeCible != nil {
            Divider()
            Button {
                afficheTraduction.toggle()
                web.afficherTraduction(afficheTraduction)
                if afficheTraduction { web.reappliquerExtras() } else { web.restaurerExtras() }
                web.titreCourant { t in if !t.isEmpty { title = t } }
            } label: {
                Label(afficheTraduction ? tr("Voir l’original") : tr("Voir la traduction"),
                      systemImage: afficheTraduction ? "arrow.uturn.backward" : "character.book.closed")
            }
        }
    }

    /// iPhone tenu droit : ce qui ne tient pas dans la barre.
    private var menuPlus: some View {
        Menu {
            if hasSlides {
                Button { presenting = true } label: { Label(tr("Diaporama"), systemImage: "play.rectangle") }
            }
            Button { ouvrir(.sommaire) } label: { Label(tr("Sommaire"), systemImage: "list.bullet") }
                .disabled(web.toc.isEmpty)
            if let source = langueDetectee {
                Menu {
                    elementsTraduction(source)
                } label: {
                    Label(tr("Traduire"), systemImage: "character.book.closed")
                }
            }
            Divider()
            Button { showShareOptions = true } label: { Label(tr("Partager"), systemImage: "square.and.arrow.up") }
            Button(action: onOpen) { Label(tr("Ouvrir un fichier"), systemImage: "folder") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .teinteBarre()
        .accessibilityLabel(tr("Plus"))
    }

    // MARK: Text size

    /// Le menu « Aa » : le thème de lecture puis la taille du texte. Les réunir évite un
    /// neuvième bouton dans une barre qui en compte déjà huit — et l'on règle d'un même geste
    /// tout ce qui touche à l'aspect de la page.
    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Thème"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                ForEach(ReaderTheme.allCases) { theme in themeRow(theme) }
            }
            Divider()
            Text(tr("Taille du texte"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            textSizeControls
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 290)
    }

    /// Une ligne du choix de thème : une vignette aux couleurs du thème — dans le mode clair ou
    /// sombre en cours —, son nom, et une coche sur celui qui est actif.
    private func themeRow(_ theme: ReaderTheme) -> some View {
        let v = theme.vignette(colorScheme)
        let actif = readerTheme == theme.rawValue
        return Button { readerTheme = theme.rawValue } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(v.fond)
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3))
                    Text("Aa")
                        .font(.system(size: 15, weight: .bold, design: theme.dessinTitre))
                        .foregroundStyle(v.titre)
                        .padding(.leading, 6).padding(.bottom, 5)
                    Capsule().fill(v.accent)
                        .frame(width: 10, height: 3)
                        .offset(x: 30, y: -9)
                }
                .frame(width: 48, height: 32)
                Text(theme.nom)
                    .foregroundStyle(.primary)
                Spacer()
                if actif {
                    Image(systemName: "checkmark").foregroundStyle(orange)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? .isSelected : [])
    }

    private var textSizeControls: some View {
        HStack(spacing: 16) {
            Button { setScale(fontScale - scaleStep) } label: {
                Image(systemName: "minus").font(.headline).frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(fontScale <= minScale + 0.001)

            VStack(spacing: 2) {
                Text("\(Int((fontScale * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
                Button(tr("Réinitialiser")) { setScale(1.0) }
                    .font(.caption)
                    .disabled(abs(fontScale - 1.0) < 0.001)
            }
            .frame(minWidth: 72)

            Button { setScale(fontScale + scaleStep) } label: {
                Image(systemName: "plus").font(.headline).frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(fontScale >= maxScale - 0.001)
        }
        .tint(orange)
    }

    private func setScale(_ value: Double) {
        fontScale = (min(maxScale, max(minScale, value)) * 100).rounded() / 100
    }

    // MARK: External links

    private func handleExternalLink(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        #if targetEnvironment(macCatalyst)
        UIApplication.shared.open(url)                      // open in the default macOS browser
        #else
        if scheme == "http" || scheme == "https" {
            externalLink = ExternalLink(url: url)          // in-app Safari with "Done"
        } else {
            UIApplication.shared.open(url)                 // mailto:, tel: → system handler
        }
        #endif
    }

    // MARK: Share actions

    /// Un export porte ce que le lecteur voit — c'est la règle la moins surprenante, et
    /// la bascule « Voir l'original » la rend explicite : ce qui est à l'écran est ce qui
    /// sortira. Mais un document exporté circule sans le bandeau qui l'annonce, alors la
    /// mention voyage avec lui, et le nom du fichier porte la langue.
    private var mentionExport: String? {
        guard afficheTraduction, case .finished = translator.state,
              let source = translator.demandeSource else { return nil }
        let locale = Locale(identifier: Localization.shared.code)
        let nom = locale.localizedString(forLanguageCode: source) ?? source
        return tr("Traduit automatiquement sur l’appareil · %@", nom.prefix(1).uppercased() + nom.dropFirst())
    }

    /// Le suffixe de langue du fichier exporté, pour que deux versions du même rapport ne
    /// se recouvrent pas dans un dossier de téléchargements.
    private var suffixeLangue: String {
        mentionExport == nil ? "" : " (\(Localization.shared.code))"
    }

    private func exportPDF() {
        web.avecMentionExport(mentionExport) { fini in
            web.exportPDF { url in
                fini()
                if let url { sharePayload = SharePayload(url: url) }
            }
        }
    }

    private func exportWord() {
        let base = title.isEmpty ? document.filename.replacingOccurrences(of: ".md", with: "") : title
        let name = base + suffixeLangue
        web.avecMentionExport(mentionExport) { fini in
            web.buildExportModel { model in
                fini()
                guard let model else { return }
                OOXMLExportBridge.buildDocx(title: base, model: model) { data in
                    guard let data else { return }
                    let safe = name.replacingOccurrences(of: "/", with: "-")
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).docx")
                    do { try data.write(to: url); sharePayload = SharePayload(url: url) } catch { /* ignore */ }
                }
            }
        }
    }

    /// Le Markdown partagé reste la source, toujours : c'est le fichier lui-même, et il
    /// n'a pas changé de langue. Exporter une traduction en .md ferait croire à un
    /// original.
    private func shareMarkdown() {
        let name = document.filename.hasSuffix(".md") ? document.filename : document.filename + ".md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try document.text.data(using: .utf8)?.write(to: url)
            sharePayload = SharePayload(url: url)
        } catch { /* ignore */ }
    }
}

// MARK: - Apple Intelligence — Résumé du document

/// A small "Apple Intelligence"-style mark: a sparkle with the signature
/// multicolour gradient. An adapted glyph, not Apple's trademark.
struct AppleIntelligenceGlyph: View {
    var size: CGFloat = 17
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.30, blue: 0.55),
                             Color(red: 0.60, green: 0.34, blue: 0.96),
                             Color(red: 0.27, green: 0.60, blue: 0.99),
                             Color(red: 0.99, green: 0.65, blue: 0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            .accessibilityHidden(true)
    }
}

/// Generates a **formatted Markdown** summary (chapters, themes, bold, sizes) of a
/// document using Apple Intelligence's on-device model (Foundation Models).
/// Available only when Apple Intelligence is enabled (iOS 26 / macOS 26+).
@MainActor
final class DocumentSummarizer: ObservableObject {
    enum State: Equatable {
        case idle, loading
        case done(String)        // Markdown
        case failed(String)
    }
    @Published var state: State = .idle

    /// True when on-device summarisation can run right now.
    static var isAvailable: Bool {
        #if DEBUG
        // UI/screenshot harness (Debug only, like OKIA_RENDER_CONTENT): Foundation Models
        // needs a real Apple-Intelligence device, so the simulator can never exercise these
        // screens. This flag shows them with canned content. Absent from release builds.
        // "off" forces the unavailable state — the simulator reports Apple Intelligence as
        // available (it borrows the host Mac's model) yet generation fails there, so this is
        // the only way to exercise the hidden-options path. Ce drapeau ne fait que doubler le
        // modèle : c'est OKIA_AI qui ouvre l'écran.
        if let flag = ProcessInfo.processInfo.environment["OKIA_FAKE_AI"], !flag.isEmpty {
            return flag != "off"
        }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// True when the document was too long to be read whole, so the summary covers its
    /// opening only. Surfaced to the reader rather than left implicit.
    @Published private(set) var partialDocument = false

    func summarize(_ markdown: String) {
        #if DEBUG
        // Harnais : le simulateur échoue à générer. OKIA_FAKE_AI pose un résumé factice, assez
        // long pour éprouver le défilement de la seconde partie.
        if let flag = ProcessInfo.processInfo.environment["OKIA_FAKE_AI"], !flag.isEmpty, flag != "off" {
            partialDocument = true
            let chapitre = (1...8).map { "Paragraphe \($0) du chapitre, assez long pour remplir l’écran et obliger à défiler jusqu’en bas de la seconde partie." }
                .joined(separator: "\n\n")
            state = .done("# Résumé factice\n\n" + (1...4).map { "## Chapitre \($0)\n\n" + chapitre }.joined(separator: "\n\n"))
            return
        }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            state = .loading
            let condensed = Self.condensed(from: markdown, limit: 8000)
            partialDocument = condensed.truncated
            Task { await run(condensed.text) }
            return
        }
        #endif
        state = .failed(tr("Apple Intelligence n’est pas disponible sur cet appareil."))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func run(_ text: String) async {
        do {
            let session = LanguageModelSession(instructions: Self.instructions(partial: partialDocument))
            let prompt = tr("Voici le document à résumer :")
            // La règle de langue est répétée *après* le document, comme dans la discussion :
            // les instructions la posent une fois, mais un document rédigé dans une autre
            // langue tire fortement le modèle vers elle — un résumé demandé en français sur
            // un rapport anglais revenait moitié-moitié, « Introduction » puis « Field
            // Overview ». La dernière ligne lue est celle qui pèse le plus.
            let response = try await session.respond(
                to: "\(prompt)\n\n\(text)\n\n(\(DocumentChat.languageRule))")
            // Same stutter guard as the chat: asked for 3 to 5 chapters, the on-device model
            // can emit one of them several times over.
            state = .done(DocumentChat.dropRepeatedSections(Self.cleanMarkdown(response.content)))
        } catch {
            state = .failed(tr("Le résumé n’a pas pu être généré (%@).", error.localizedDescription))
        }
    }

    /// Summarising instructions, one per shipped language. These are model prompts, not UI
    /// strings: each is written natively (not translated word-for-word) and names its own
    /// language explicitly, so the model answers in the language the reader chose.
    private static func instructions(partial: Bool) -> String {
        let note = partial ? "\n\n" + excerptNote : ""
        switch Localization.shared.code {
        case "en": return """
    You are an assistant that summarises documents in English. CONDENSE aggressively:
    do not copy the text, rephrase the essentials.
    Produce a STRUCTURED summary in Markdown, ready to display:
    - start with a bold hook sentence (**…**);
    - organise into 3 to 5 chapters with level-2 headings, written exactly as "## Title"
      (a single "##", never "## ##");
    - under each chapter, 2 to 4 concise bullets, with key terms, proper nouns and
      figures in **bold**;
    - end with a "## In brief" chapter of 2 to 3 points.
    Stay faithful to the document, invent nothing. Reply ONLY with the summary's Markdown.
    """ + note
        case "de": return """
    Du bist ein Assistent, der Dokumente auf Deutsch zusammenfasst. VERDICHTE stark:
    schreibe den Text nicht ab, formuliere das Wesentliche neu.
    Erstelle eine STRUKTURIERTE Zusammenfassung in Markdown, direkt anzeigefertig:
    - beginne mit einem fett gesetzten Aufhänger-Satz (**…**);
    - gliedere in 3 bis 5 Kapitel mit Überschriften der Ebene 2, exakt als „## Titel“
      geschrieben (nur ein „##“, niemals „## ##“);
    - unter jedem Kapitel 2 bis 4 knappe Stichpunkte, Schlüsselbegriffe, Eigennamen und
      Zahlen **fett** hervorgehoben;
    - schließe mit einem Kapitel „## Kurz gefasst“ aus 2 bis 3 Punkten.
    Bleibe dem Dokument treu, erfinde nichts. Antworte NUR mit dem Markdown der Zusammenfassung.
    """ + note
        case "es": return """
    Eres un asistente que resume documentos en español. CONDENSA con fuerza:
    no copies el texto, reformula lo esencial.
    Produce un resumen ESTRUCTURADO en formato Markdown, listo para mostrarse:
    - empieza con una frase gancho en negrita (**…**);
    - organiza en 3 a 5 capítulos con títulos de nivel 2, escritos exactamente «## Título»
      (una sola «##», nunca «## ##»);
    - bajo cada capítulo, de 2 a 4 viñetas concisas, con los términos, nombres propios
      y cifras clave en **negrita**;
    - termina con un capítulo «## En resumen» de 2 a 3 puntos.
    Cíñete al documento, no inventes nada. Responde ÚNICAMENTE con el Markdown del resumen.
    """ + note
        case "it": return """
    Sei un assistente che riassume documenti in italiano. CONDENSA con decisione:
    non ricopiare il testo, riformula l'essenziale.
    Produci un riassunto STRUTTURATO in formato Markdown, pronto da visualizzare:
    - inizia con una frase d'aggancio in grassetto (**…**);
    - organizza in 3-5 capitoli con titoli di livello 2, scritti esattamente «## Titolo»
      (un solo «##», mai «## ##»);
    - sotto ogni capitolo, da 2 a 4 punti elenco concisi, con termini, nomi propri
      e cifre chiave in **grassetto**;
    - concludi con un capitolo «## In breve» di 2 o 3 punti.
    Resta fedele al documento, non inventare nulla. Rispondi SOLO con il Markdown del riassunto.
    """ + note
        default: return """
    Tu es un assistant qui résume des documents en français. CONDENSE fortement :
    ne recopie pas le texte, reformule l’essentiel.
    Produis un résumé STRUCTURÉ au format Markdown, prêt à être affiché :
    - commence par une phrase d’accroche en gras (**…**) ;
    - organise en 3 à 5 chapitres avec des titres de niveau 2, écris exactement « ## Titre »
      (un seul « ## », jamais « ## ## ») ;
    - sous chaque chapitre, 2 à 4 puces concises, en mettant en **gras** les termes,
      noms propres et chiffres clés ;
    - termine par un chapitre « ## En bref » de 2 à 3 points.
    Reste fidèle au document, n’invente rien. Réponds UNIQUEMENT avec le Markdown du résumé.
    """ + note
        }
    }

    /// Tidy the model's Markdown: drop wrapping ```-fences and collapse any doubled
    /// heading markers (`## ## Titre` → `## Titre`).
    static func cleanMarkdown(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") {
            out = out.replacingOccurrences(of: #"^```[a-zA-Z]*\n"#, with: "", options: .regularExpression)
            if out.hasSuffix("```") { out = String(out.dropLast(3)) }
        }
        out = out.replacingOccurrences(of: #"(?m)^(#{1,6})[ \t]+#{1,6}[ \t]+"#, with: "$1 ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    /// Reduce a Markdown document to **plain prose** (no Markdown markers) and cap its length
    /// for the model's context window. Stripping the `#`/`>`/`*` markers is important: if the
    /// source headings keep their `##`, the model wraps them in its own `##` → "## ## Titre".
    static func plainText(from markdown: String, limit: Int = 8000) -> String {
        condensed(from: markdown, limit: limit).text
    }

    /// Reduce the document to what fits, and report whether the cap actually bit.
    ///
    /// When it does, a blind prefix is the worst possible sample: on a 858-article briefing it
    /// is the first four articles, and the model then answers "what are the main themes" from
    /// 0.4 % of the text. The headings map the *whole* document for one line each, so the
    /// excerpt keeps the opening for substance and adds an outline for coverage. Even the
    /// outline can overflow — 859 headings are 54 KB against a 6 000-character budget — so it
    /// is sampled at a regular stride, which keeps the sample spread over the entire document
    /// instead of stopping partway.
    static func condensed(from markdown: String, limit: Int) -> (text: String, truncated: Bool) {
        let prose = plainProse(from: markdown)
        if prose.count <= limit { return (prose, false) }

        let outline = headings(in: markdown)
        guard !outline.isEmpty else { return (String(prose.prefix(limit)), true) }

        let averageLine = max(1, outline.reduce(0) { $0 + $1.count + 1 } / outline.count)
        let capacity = max(1, (limit * 3 / 5) / averageLine)
        let stride = max(1, Int((Double(outline.count) / Double(capacity)).rounded(.up)))

        var kept: [String] = []
        var index = 0
        while index < outline.count && kept.count < capacity {
            kept.append(outline[index])
            index += stride
        }

        // The marker is deliberately terse and in English: it is read by the model, and the
        // per-language instructions are what explain the excerpt to it.
        let outlineText = "\n\n----- OUTLINE (\(kept.count)/\(outline.count) headings) -----\n"
            + kept.map { "- " + $0 }.joined(separator: "\n")
        let proseBudget = max(0, limit - outlineText.count)
        return (String(prose.prefix(proseBudget)) + outlineText, true)
    }

    /// Handed to the model whenever `condensed` had to cut. Without it the model treats an
    /// opening as the whole document and answers "the main themes" from the first few
    /// sections. Shared by the summary and the chat so the wording cannot drift apart.
    static var excerptNote: String {
        switch Localization.shared.code {
        case "en": return """
    The document is too long to be sent whole. You are given its OPENING, then an OUTLINE — \
    headings taken from across the entire document — under "----- OUTLINE -----". The outline \
    tells you what the document covers as a whole; the opening is the only text you have \
    actually read. If a question bears on a part you do not have, say so instead of guessing.
    """
        case "de": return """
    Das Dokument ist zu lang, um vollständig übergeben zu werden. Du erhältst seinen ANFANG \
    und danach eine GLIEDERUNG — Überschriften aus dem gesamten Dokument — unter \
    "----- OUTLINE -----". Die Gliederung sagt dir, worum es insgesamt geht; der Anfang ist \
    der einzige Text, den du wirklich gelesen hast. Betrifft eine Frage einen Teil, den du \
    nicht hast, sage das, statt zu raten.
    """
        case "es": return """
    El documento es demasiado largo para enviarse entero. Recibes su INICIO y después un \
    ÍNDICE — títulos tomados de todo el documento — bajo "----- OUTLINE -----". El índice te \
    dice de qué trata el conjunto; el inicio es el único texto que has leído de verdad. Si una \
    pregunta se refiere a una parte que no tienes, dilo en lugar de suponer.
    """
        case "it": return """
    Il documento è troppo lungo per essere trasmesso per intero. Ricevi il suo INIZIO e poi un \
    INDICE — titoli presi da tutto il documento — sotto "----- OUTLINE -----". L'indice ti dice \
    di che cosa tratta l'insieme; l'inizio è l'unico testo che hai davvero letto. Se una domanda \
    riguarda una parte che non hai, dillo invece di supporre.
    """
        default: return """
    Le document est trop long pour être transmis en entier. Tu reçois son DÉBUT, puis un PLAN — \
    des titres prélevés sur tout le document — sous « ----- OUTLINE ----- ». Le plan te dit ce \
    que couvre l'ensemble ; le début est le seul texte que tu aies réellement lu. Si une question \
    porte sur une partie que tu n'as pas, dis-le au lieu de supposer.
    """
        }
    }

    /// Every heading in document order, markers stripped — `##` left in place would come back
    /// as "## ## Titre" in the model's own output.
    private static func headings(in markdown: String) -> [String] {
        var out: [String] = []
        var inFence = false
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            guard let marker = line.range(of: #"^#{1,3}[ \t]+"#, options: .regularExpression) else { continue }
            let title = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { out.append(title) }
        }
        return out
    }

    /// Markdown reduced to plain prose, uncapped.
    private static func plainProse(from markdown: String) -> String {
        var s = markdown
        s = s.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)        // code/mermaid/leaflet
        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: " ", options: .regularExpression)   // images
        s = s.replacingOccurrences(of: #"\[\[([^\]|]+)(\|[^\]]+)?\]\]"#, with: "$1", options: .regularExpression) // wiki-links
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)        // md links → text
        s = s.replacingOccurrences(of: #"(?m)^[ \t]*#{1,6}[ \t]+"#, with: "", options: .regularExpression)        // headings
        s = s.replacingOccurrences(of: #"(?m)^[ \t]*>[ \t]?"#, with: "", options: .regularExpression)             // quotes/callouts
        s = s.replacingOccurrences(of: #"[*_`~]"#, with: "", options: .regularExpression)                          // inline emphasis/code
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }
}

/// Sheet showing the Apple-Intelligence summary, rendered with the app's own Markdown
/// engine so it keeps the OK-ia typography (chapter headings, bold, sizes).
struct DocumentSummaryView: View {
    let sourceTitle: String
    let sourceMarkdown: String

    @StateObject private var summarizer = DocumentSummarizer()
    @StateObject private var web = ReaderWebController()
    @State private var ignoredTap: TappedDiagram?
    @State private var ignoredImage: TappedImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fermerPanneau) private var fermerPanneau

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(tr("Résumé du document"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { boutonOK }
                    ToolbarItem(placement: .cancellationAction) { boutonRegenerer }
                }
        }
        .task { if case .idle = summarizer.state { summarizer.summarize(sourceMarkdown) } }
    }

    private var boutonOK: some View {
        Button("OK") { (fermerPanneau ?? { dismiss() })() }
    }

    private var boutonRegenerer: some View {
        Button { summarizer.summarize(sourceMarkdown) } label: { Image(systemName: "arrow.clockwise") }
            .disabled(isWorking)
            .accessibilityLabel(tr("Régénérer le résumé"))
    }

    private var isWorking: Bool {
        if case .loading = summarizer.state { return true }
        return false
    }

    @ViewBuilder private var content: some View {
        switch summarizer.state {
        case .idle, .loading:
            VStack(spacing: 14) {
                AppleIntelligenceGlyph(size: 34)
                ProgressView()
                Text(tr("Apple Intelligence rédige le résumé…"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle).foregroundStyle(.secondary)
                Text(message)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .done(let summary):
            VStack(spacing: 0) {
                MarkdownWebView(document: MarkdownDocument(filename: tr("Résumé — %@", sourceTitle), text: summary),
                                tapped: $ignoredTap, tappedImage: $ignoredImage, onTitle: { _ in },
                                webController: web, onExternalLink: { _ in })
                summaryDisclaimer
            }
        }
    }

    private var summaryDisclaimer: some View {
        HStack(spacing: 6) {
            AppleIntelligenceGlyph(size: 12)
            Text(summarizer.partialDocument
                 ? tr("Résumé généré sur l’appareil par Apple Intelligence. Peut contenir des erreurs.")
                   + " " + tr("Document trop long pour être lu en entier : seul son début a été analysé.")
                 : tr("Résumé généré sur l’appareil par Apple Intelligence. Peut contenir des erreurs."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Diaporama (slideshow)

/// Full-screen slideshow of the document. Hosts a dedicated web view running the
/// OK-ia slideshow engine (slides split on "---"). The end button or the Esc key
/// dismisses back to the normal Markdown reader. Tapping an image or diagram opens
/// the existing full-screen zoom viewers on top of the slideshow.
struct PresentationView: View {
    let document: MarkdownDocument
    /// La mémoire du lecteur, reprise telle quelle : ce qu'il a déjà traduit ne se
    /// repaiera pas ici, à 171 caractères par seconde.
    var memoireHeritee: [String: String]
    var langueSource: String?
    var traduire: Bool
    @Environment(\.dismiss) private var dismiss

    /// Le diaporama a son propre traducteur. Le partager avec le lecteur enverrait les
    /// blocs traduits ici vers le DOM de l'autre WebView — une autre page, d'autres
    /// nœuds — et il faut de toute façon une vue hôte vivante dans cette hiérarchie-ci
    /// pour que le framework rende une session.
    @StateObject private var trad = DocumentTranslator()
    @State private var tappedDiagram: TappedDiagram?
    @State private var tappedImage: TappedImage?
    @State private var sharePayload: SharePayload?

    var body: some View {
        PresentationWebView(document: document,
                            translator: trad,
                            langueSource: langueSource,
                            traduire: traduire,
                            onExit: { dismiss() },
                            onDiagram: { tappedDiagram = $0 },
                            onImage: { tappedImage = $0 },
                            onExportReady: { sharePayload = SharePayload(url: $0) })
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .fullScreenCover(item: $tappedDiagram) { DiagramZoomView(diagram: $0) }
            .fullScreenCover(item: $tappedImage) { ImageZoomView(image: $0) }
            .sheet(item: $sharePayload) { payload in ShareSheet(items: [payload.url]) }
            .onAppear {
                requestLandscapeIfPhone()
                trad.absorber(memoireHeritee)
                barreDeFenetre(visible: false)
            }
            .onDisappear { barreDeFenetre(visible: true) }
            .overlay { TranslationHostView(translator: trad) }
    }

    /// Sur Mac, la barre de la fenêtre reste au-dessus d'une présentation plein écran et en cache
    /// le haut : le diaporama la retire le temps de la séance.
    private func barreDeFenetre(visible: Bool) {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes {
            guard let titlebar = (scene as? UIWindowScene)?.titlebar else { continue }
            titlebar.toolbar?.isVisible = visible
            titlebar.titleVisibility = visible ? .visible : .hidden
        }
        #endif
    }

    /// On iPhone, the deck reads best in landscape ("en largeur"); nudge the scene.
    private func requestLandscapeIfPhone() {
        #if !targetEnvironment(macCatalyst)
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        for scene in UIApplication.shared.connectedScenes {
            if let ws = scene as? UIWindowScene {
                ws.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
        }
        #endif
    }
}

/// A WKWebView that captures hardware-keyboard navigation (←/→, space, page up/down,
/// Esc) for the slideshow, reliably on Mac Catalyst and iPad with a keyboard.
final class KeyCapturingWebView: WKWebView {
    var onKey: ((String) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let inputs = [UIKeyCommand.inputRightArrow, UIKeyCommand.inputLeftArrow,
                      UIKeyCommand.inputEscape, " ",
                      UIKeyCommand.inputPageUp, UIKeyCommand.inputPageDown]
        return inputs.map { input in
            let cmd = UIKeyCommand(input: input, modifierFlags: [], action: #selector(handleKey(_:)))
            cmd.wantsPriorityOverSystemBehavior = true
            return cmd
        }
    }

    @objc private func handleKey(_ command: UIKeyCommand) {
        onKey?(command.input ?? "")
    }
}

struct PresentationWebView: UIViewRepresentable {
    let document: MarkdownDocument
    var translator: DocumentTranslator
    var langueSource: String?
    /// Vrai quand l'option est active. Le diaporama n'a pas de bandeau — il est en plein
    /// écran, sans chrome — donc pas de bascule vers l'original : on sort du diaporama
    /// pour retrouver le document.
    var traduire: Bool
    var onExit: () -> Void
    var onDiagram: (TappedDiagram) -> Void
    var onImage: (TappedImage) -> Void
    var onExportReady: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        for name in ["presentReady", "presentStarted", "presentExit", "diagramTapped", "imageTapped", "exportPptx", "slideRendered"] {
            controller.add(context.coordinator, name: name)
        }
        // Hand the app language to the slideshow engine (menu labels, aria labels).
        controller.addUserScript(WKUserScript(
            source: "window.OKIA_LANG = '\(Localization.shared.code)';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = KeyCapturingWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.onKey = { [weak coordinator = context.coordinator] key in
            coordinator?.handleNativeKey(key)
        }

        context.coordinator.webView = webView
        loadRenderer(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    private func loadRenderer(into webView: WKWebView) {
        guard let webDir = Bundle.main.url(forResource: "presentation", withExtension: "html", subdirectory: "Web")
                ?? Bundle.main.url(forResource: "presentation", withExtension: "html") else { return }
        webView.loadFileURL(webDir, allowingReadAccessTo: webDir.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: PresentationWebView
        weak var webView: WKWebView?

        init(_ parent: PresentationWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Chaque bloc traduit alimente la table que le diaporama repose sur ses
            // diapositives — et que l'export PowerPoint relira.
            parent.translator.onBloc = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.envoyerTraduction(self.parent.translator.memoire, actif: true)
                }
            }
            // Les libellés qui ne sont pas du texte : nœuds Mermaid, bulles de marqueurs.
            // Ils vivent dans le SVG, la collecte de texte les ignore, et sans ce
            // branchement le diaporama gardait ses diagrammes dans la langue d'origine
            // pendant que tout le reste passait — vu sur iPhone, pas au développement.
            parent.translator.extras = { [weak self] in
                guard let self else { return [] }
                return await self.collecterExtrasDiapositives()
            }
            parent.translator.onExtras = { [weak self] table in
                guard let self else { return }
                self.parent.translator.absorber(table)
                self.envoyerTraduction(self.parent.translator.memoire, actif: true)
            }
            startPresentation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak webView] in
                webView?.becomeFirstResponder()
            }
        }

        /// Traduit une diapositive qui vient d'apparaître. Le rendu du diaporama est
        /// paresseux ; la traduction l'est donc aussi — on ne traduit pas six diapositives
        /// que personne ne regarde encore.
        ///
        /// Le résultat repart en table « texte d'origine → traduction » plutôt qu'en blocs
        /// numérotés : une diapositive qu'on rouvre, et l'export qui les rend toutes une
        /// seconde fois hors écran, se resservent alors sans repasser par le modèle. Le
        /// prix est qu'un morceau déplacé par la syntaxe d'arrivée reste à sa place —
        /// une diapositive est courte, la gêne est moindre que d'attendre.
        func traduireDiapositive(_ index: Int) {
            guard parent.traduire, let webView else { return }
            let cible = Localization.shared.code
            let js = "return JSON.stringify(window.OKIA_PRESENT.collectSlide(\(index)));"
            webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self, case .success(let value) = result, let json = value as? String,
                      let data = json.data(using: .utf8),
                      let blocs = try? JSONDecoder().decode([TranslationBlock].self, from: data),
                      !blocs.isEmpty else { return }
                Task { @MainActor in
                    let translator = self.parent.translator
                    // La langue du lecteur si elle est connue, sinon devinée sur cette
                    // diapositive : le diaporama peut s'ouvrir avant que la lecture ait
                    // fini de deviner la sienne, et il ne doit pas en dépendre.
                    guard let source = self.parent.langueSource
                            ?? DocumentTranslator.langue(de: blocs),
                          source != cible else { return }

                    // Ce que la lecture a déjà traduit se repose sans rien demander.
                    self.envoyerTraduction(translator.memoire, actif: true)
                    let manquants = blocs.filter { bloc in
                        bloc.parts.contains { !$0.protege && translator.memoire[$0.texte] == nil }
                    }
                    guard !manquants.isEmpty,
                          case .pret = await DocumentTranslator.aptitude(de: source, vers: cible)
                    else { return }
                    DocumentTranslator.journal.debug(
                        "diapositive \(index) : \(manquants.count) blocs à traduire")
                    translator.demarrer(blocs: manquants, defilement: 0,
                                        source: source, cible: cible)
                }
            }
        }

        /// Les libellés hors texte de toutes les diapositives déjà rendues. On ne se limite
        /// pas à la diapositive courante : le lecteur avance, et un aller-retour par
        /// diapositive coûterait cher pour un gain nul — la mémoire écarte de toute façon
        /// ce qui a déjà été traduit.
        func collecterExtrasDiapositives() async -> [String] {
            guard let webView else { return [] }
            // Toutes les diapositives, pas seulement celles déjà affichées : le rendu du
            // diaporama est paresseux, et un diagramme jamais dessiné n'a pas de libellé à
            // collecter — il serait resté en langue d'origine jusque dans le PowerPoint.
            let js = "return JSON.stringify(await window.OKIA_PRESENT.collectAllSlidesExtras());"
            return await withCheckedContinuation { suite in
                webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                    guard case .success(let v) = result, let json = v as? String,
                          let d = json.data(using: .utf8),
                          let liste = try? JSONDecoder().decode([String].self, from: d) else {
                        suite.resume(returning: [])
                        return
                    }
                    suite.resume(returning: liste)
                }
            }
        }

        func envoyerTraduction(_ table: [String: String], actif: Bool) {
            guard let webView,
                  let data = try? JSONSerialization.data(withJSONObject: table),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.OKIA_PRESENT && window.OKIA_PRESENT.setTranslation(\(actif), \(json));")
        }

        func startPresentation() {
            guard let webView,
                  let data = try? JSONEncoder().encode(parent.document.text),
                  let mdJSON = String(data: data, encoding: .utf8) else { return }
            // AVANT le démarrage, sans quoi rien ne part : le moteur n'annonce une
            // diapositive rendue que si la traduction est active, et la première est
            // rendue par `start` lui-même. L'annoncer après, c'est ne jamais traduire la
            // première diapositive — et comme c'est elle qui déclenche tout, aucune.
            // On active sur la seule option : la langue d'origine, elle, peut n'être pas
            // encore connue — le diaporama s'ouvre parfois avant que le lecteur ait fini
            // de deviner la sienne. Le tri se fait plus bas, diapositive par diapositive.
            envoyerTraduction(parent.translator.memoire, actif: parent.traduire)
            webView.evaluateJavaScript("window.OKIA_PRESENT && window.OKIA_PRESENT.start(\(mdJSON));",
                                       completionHandler: nil)
        }

        func handleNativeKey(_ key: String) {
            switch key {
            case UIKeyCommand.inputRightArrow, " ", UIKeyCommand.inputPageDown:
                webView?.evaluateJavaScript("window.OKIA_PRESENT && window.OKIA_PRESENT.next();")
            case UIKeyCommand.inputLeftArrow, UIKeyCommand.inputPageUp:
                webView?.evaluateJavaScript("window.OKIA_PRESENT && window.OKIA_PRESENT.prev();")
            case UIKeyCommand.inputEscape:
                // Let the slideshow handle Esc: it closes the overview/menu first,
                // and posts presentExit (→ onExit) only when nothing is open.
                webView?.evaluateJavaScript("window.OKIA_PRESENT && window.OKIA_PRESENT.escape();")
            default: break
            }
        }

        // Open external links (e.g. an article URL on a slide) in the system browser.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "mailto", "tel"].contains(scheme) {
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "presentExit":
                parent.onExit()
            case "diagramTapped":
                if let dict = message.body as? [String: Any], let svg = dict["svg"] as? String {
                    parent.onDiagram(TappedDiagram(svg: svg, title: (dict["title"] as? String) ?? ""))
                }
            case "imageTapped":
                if let dict = message.body as? [String: Any], let src = dict["src"] as? String {
                    parent.onImage(TappedImage(src: src))
                }
            case "slideRendered":
                if let dict = message.body as? [String: Any] {
                    let index = (dict["index"] as? Int) ?? Int((dict["index"] as? Double) ?? 0)
                    traduireDiapositive(index)
                }
            case "exportPptx":
                exportPptx()
            default:
                break
            }
        }

        /// Avant d'exporter, s'assurer que TOUTES les diapositives sont traduites — pas
        /// seulement celles que le lecteur a ouvertes. Sans cette passe, le fichier
        /// sortirait à moitié traduit, ce qui est pire que pas traduit du tout : rien ne
        /// dirait au destinataire où s'arrête la traduction.
        private func exportPptx() {
            guard parent.traduire else { exportPptxMaintenant(); return }
            guard let webView else { return }
            let cible = Localization.shared.code
            let js = "return JSON.stringify(await window.OKIA_PRESENT.collectAllSlides());"
            webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self else { return }
                guard case .success(let value) = result, let json = value as? String,
                      let data = json.data(using: .utf8),
                      let blocs = try? JSONDecoder().decode([TranslationBlock].self, from: data),
                      !blocs.isEmpty else {
                    self.exportPptxMaintenant()
                    return
                }
                Task { @MainActor in
                    let translator = self.parent.translator
                    guard let source = self.parent.langueSource
                            ?? DocumentTranslator.langue(de: blocs),
                          source != cible,
                          case .pret = await DocumentTranslator.aptitude(de: source, vers: cible)
                    else {
                        self.exportPptxMaintenant()
                        return
                    }
                    let manquants = blocs.filter { bloc in
                        bloc.parts.contains { !$0.protege && translator.memoire[$0.texte] == nil }
                    }
                    if !manquants.isEmpty {
                        DocumentTranslator.journal.debug(
                            "export : \(manquants.count) blocs encore à traduire")
                        translator.demarrer(blocs: manquants, defilement: 0,
                                            source: source, cible: cible)
                        await translator.attendreFin()
                        self.envoyerTraduction(translator.memoire, actif: true)
                    }
                    self.exportPptxMaintenant()
                }
            }
        }

        private func exportPptxMaintenant() {
            guard let webView else { return }
            let name = (parent.document.filename as NSString).deletingPathExtension
            webView.callAsyncJavaScript("return await window.OKIA_PRESENT.exportModel();",
                                        arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self, case .success(let value) = result,
                      let model = value as? [String: Any] else { return }
                OOXMLExportBridge.buildPptx(model: model) { data in
                    guard let data else { return }
                    let safe = name.isEmpty ? tr("Présentation")
                                            : name.replacingOccurrences(of: "/", with: "-")
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pptx")
                    do { try data.write(to: url); self.parent.onExportReady(url) } catch { /* ignore */ }
                }
            }
        }
    }
}

#if DUO_SDK && !targetEnvironment(macCatalyst)
/// Dit si l'appareil a une charnière (Duo). `UIHingeInteraction` reçoit l'état de la charnière
/// dès qu'elle entre dans la hiérarchie, puis à chaque changement ; sans charnière, `hinge` est
/// nil. Plus sûr que de deviner l'appareil à ses marges : un iPhone en paysage en a aussi.
@available(iOS 27.1, *)
private struct DetecteurCharniere: UIViewRepresentable {
    /// (appareil pliable, charnière ouverte, partiellement repliée)
    var surChangement: (Bool, Bool, Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let vue = UIView()
        vue.isUserInteractionEnabled = false
        let suivi = surChangement
        vue.addInteraction(UIHingeInteraction { _, maj in
            suivi(maj.hinge != nil, maj.hinge.map { $0.status != .closed } ?? false,
                  maj.hinge.map { $0.status == .partiallyOpen } ?? false)
        })
        return vue
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif

/// Ce que la seconde partie du Duo peut montrer à côté du document.
enum PanneauDuo: Hashable {
    case sommaire, resume, discussion, conversion
}

extension View {
    /// Les icônes de la barre en monochrome sur iPhone et iPad — sans quoi elles prendraient
    /// l'orange de l'app. Sur Mac, la barre de la fenêtre les dessine elle-même ; une teinte
    /// imposée les posait sur des pastilles noires.
    @ViewBuilder func teinteBarre() -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        tint(.primary)
        #endif
    }
}
