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
    @State private var barHeight: CGFloat = 0
    @AppStorage("okia.fontScale") private var fontScale: Double = 1.0
    @FocusState private var searchFocused: Bool
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
        ZStack(alignment: .top) {
            MarkdownWebView(document: document, tapped: $tapped, tappedImage: $tappedImage,
                            onTitle: { title = $0 },
                            webController: web, onExternalLink: handleExternalLink,
                            topInset: barHeight)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                titleBar
                if isSearching { searchBar }
            }
            // Measure the floating bar so the web content can inset below it.
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { barHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, h in barHeight = h }
                }
            )
        }
        .fullScreenCover(item: $tapped) { diagram in
            DiagramZoomView(diagram: diagram)
        }
        .fullScreenCover(item: $tappedImage) { image in
            ImageZoomView(image: image)
        }
        .fullScreenCover(isPresented: $presenting) {
            PresentationView(document: document)
        }
        #if DEBUG
        // Harnais de capture (Debug uniquement, absent du binaire livré) : OKIA_PRESENT
        // ouvre le diaporama dès l'affichage, ce qu'aucune variable ne savait faire — la
        // présentation n'était atteignable que par un bouton, donc impossible à capturer
        // sans piloter l'interface.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if env["OKIA_PRESENT"] != nil && hasSlides {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { presenting = true }
            }
            // OKIA_AI ouvre le résumé ou la discussion au lancement. Le contenu affiché
            // reste celui du vrai modèle : le harnais ouvre la porte, il n'écrit pas la
            // réponse — contrairement à OKIA_FAKE_AI, dont le texte est fabriqué et n'a
            // donc rien à faire sur une capture publiée.
            switch env["OKIA_AI"] {
            case "summary": DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showSummary = true }
            case "chat":    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showChat = true }
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
        }
        .onChange(of: fontScale) { _, v in web.setFontScale(v) }
        .task { web.setFontScale(fontScale) }
        // An App Intent (Siri/Shortcuts) asked to summarise the opened report.
        .onAppear {
            if store.summaryRequested { showSummary = true; store.summaryRequested = false }
        }
        .onChange(of: store.summaryRequested) { _, requested in
            if requested { showSummary = true; store.summaryRequested = false }
        }
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 14) {
            Button(action: onHome) { Image(systemName: "house") }
                .accessibilityLabel(tr("Écran d’accueil"))

            Text(title.isEmpty ? document.filename : title)
                .font(.system(size: 16, weight: .heavy))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Diaporama — present the document as full-screen slides (split on "---").
            if hasSlides {
                Button { presenting = true } label: { Image(systemName: "play.rectangle") }
                    .accessibilityLabel(tr("Diaporama"))
            }

            // Apple Intelligence — summary and document chat, grouped under one glyph so the
            // title bar keeps its eight controls. The whole menu disappears when the on-device
            // model is unavailable: no greyed-out entries, no sheet that would only fail.
            if DocumentSummarizer.isAvailable {
                Menu {
                    Button { showSummary = true } label: {
                        Label(tr("Résumé du document"), systemImage: "doc.text")
                    }
                    Button { showChat = true } label: {
                        Label(tr("Discuter avec le document"), systemImage: "text.bubble")
                    }
                } label: {
                    AppleIntelligenceGlyph(size: 18)
                }
                .accessibilityLabel("Apple Intelligence")
            }

            Button { showTextSize = true } label: { Image(systemName: "textformat.size") }
                .accessibilityLabel(tr("Taille du texte"))
                .popover(isPresented: $showTextSize) {
                    textSizeControls
                        .presentationCompactAdaptation(.popover)
                }

            Button { showTOC = true } label: { Image(systemName: "list.bullet") }
                .disabled(web.toc.isEmpty)
                .accessibilityLabel(tr("Sommaire (accessibilité)"))

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isSearching.toggle() }
                if isSearching { searchFocused = true } else { searchText = ""; web.clearSearch() }
            } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel(tr("Rechercher"))

            Button { showShareOptions = true } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel(tr("Partager"))

            Button(action: onOpen) { Image(systemName: "folder") }
                .accessibilityLabel(tr("Ouvrir un fichier"))
        }
        .font(.system(size: 17, weight: .semibold))
        .tint(orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(tr("Rechercher dans le document"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onChange(of: searchText) { _, q in web.search(q) }
                .onSubmit { web.searchNext() }

            if web.searchResult.count > 0 {
                Text("\(web.searchResult.index)/\(web.searchResult.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if !searchText.isEmpty {
                Text("0").font(.footnote).foregroundStyle(.secondary)
            }

            Button { web.searchPrev() } label: { Image(systemName: "chevron.up") }
                .disabled(web.searchResult.count == 0)
            Button { web.searchNext() } label: { Image(systemName: "chevron.down") }
                .disabled(web.searchResult.count == 0)

            Button("OK") {
                withAnimation(.easeInOut(duration: 0.15)) { isSearching = false }
                searchText = ""; web.clearSearch(); searchFocused = false
            }
        }
        .tint(orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    // MARK: Text size

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
        .padding(16)
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

    private func exportPDF() {
        web.exportPDF { url in
            if let url { sharePayload = SharePayload(url: url) }
        }
    }

    private func exportWord() {
        let name = title.isEmpty ? document.filename.replacingOccurrences(of: ".md", with: "") : title
        web.buildExportModel { model in
            guard let model else { return }
            OOXMLExportBridge.buildDocx(title: name, model: model) { data in
                guard let data else { return }
                let safe = name.replacingOccurrences(of: "/", with: "-")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).docx")
                do { try data.write(to: url); sharePayload = SharePayload(url: url) } catch { /* ignore */ }
            }
        }
    }

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

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(tr("Résumé du document"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                    ToolbarItem(placement: .cancellationAction) {
                        Button { summarizer.summarize(sourceMarkdown) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isWorking)
                        .accessibilityLabel(tr("Régénérer le résumé"))
                    }
                }
        }
        .task { if case .idle = summarizer.state { summarizer.summarize(sourceMarkdown) } }
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
    @Environment(\.dismiss) private var dismiss
    @State private var tappedDiagram: TappedDiagram?
    @State private var tappedImage: TappedImage?
    @State private var sharePayload: SharePayload?

    var body: some View {
        PresentationWebView(document: document,
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
            .onAppear(perform: requestLandscapeIfPhone)
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
    var onExit: () -> Void
    var onDiagram: (TappedDiagram) -> Void
    var onImage: (TappedImage) -> Void
    var onExportReady: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        for name in ["presentReady", "presentStarted", "presentExit", "diagramTapped", "imageTapped", "exportPptx"] {
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
            startPresentation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak webView] in
                webView?.becomeFirstResponder()
            }
        }

        func startPresentation() {
            guard let webView,
                  let data = try? JSONEncoder().encode(parent.document.text),
                  let mdJSON = String(data: data, encoding: .utf8) else { return }
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
            case "exportPptx":
                exportPptx()
            default:
                break
            }
        }

        private func exportPptx() {
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
