import SwiftUI
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
    @State private var title: String = ""

    @State private var showTOC = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var showShareOptions = false
    @State private var sharePayload: SharePayload?
    @State private var externalLink: ExternalLink?
    @State private var showTextSize = false
    @State private var showSummary = false
    @State private var barHeight: CGFloat = 0
    @AppStorage("okia.fontScale") private var fontScale: Double = 1.0
    @FocusState private var searchFocused: Bool

    private let minScale = 0.7, maxScale = 2.0, scaleStep = 0.1

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        ZStack(alignment: .top) {
            MarkdownWebView(document: document, tapped: $tapped, onTitle: { title = $0 },
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
#if !targetEnvironment(macCatalyst)
        .sheet(item: $externalLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
#endif
        .confirmationDialog("Partager", isPresented: $showShareOptions, titleVisibility: .visible) {
            Button("Exporter en PDF") { exportPDF() }
            Button("Partager le Markdown (.md)") { shareMarkdown() }
            Button("Annuler", role: .cancel) {}
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
                .accessibilityLabel("Écran d’accueil")

            Text(title.isEmpty ? document.filename : title)
                .font(.system(size: 16, weight: .heavy))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Apple Intelligence summary — only when the on-device model is available.
            if DocumentSummarizer.isAvailable {
                Button { showSummary = true } label: { AppleIntelligenceGlyph(size: 18) }
                    .accessibilityLabel("Résumé du document par Apple Intelligence")
            }

            Button { showTextSize = true } label: { Image(systemName: "textformat.size") }
                .accessibilityLabel("Taille du texte")
                .popover(isPresented: $showTextSize) {
                    textSizeControls
                        .presentationCompactAdaptation(.popover)
                }

            Button { showTOC = true } label: { Image(systemName: "list.bullet") }
                .disabled(web.toc.isEmpty)
                .accessibilityLabel("Sommaire")

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isSearching.toggle() }
                if isSearching { searchFocused = true } else { searchText = ""; web.clearSearch() }
            } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("Rechercher")

            Button { showShareOptions = true } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Partager")

            Button(action: onOpen) { Image(systemName: "folder") }
                .accessibilityLabel("Ouvrir un fichier")
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
            TextField("Rechercher dans le document", text: $searchText)
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
                Button("Réinitialiser") { setScale(1.0) }
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
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    func summarize(_ markdown: String) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            state = .loading
            let text = Self.plainText(from: markdown)
            Task { await run(text) }
            return
        }
        #endif
        state = .failed("Apple Intelligence n’est pas disponible sur cet appareil.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func run(_ text: String) async {
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: "Voici le document à résumer :\n\n\(text)")
            state = .done(Self.cleanMarkdown(response.content))
        } catch {
            state = .failed("Le résumé n’a pas pu être généré (\(error.localizedDescription)).")
        }
    }

    private static let instructions = """
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
    """

    /// Tidy the model's Markdown: drop wrapping ```-fences and collapse any doubled
    /// heading markers (`## ## Titre` → `## Titre`).
    private static func cleanMarkdown(_ s: String) -> String {
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
        return s.count > limit ? String(s.prefix(limit)) : s
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Résumé du document")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                    ToolbarItem(placement: .cancellationAction) {
                        Button { summarizer.summarize(sourceMarkdown) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isWorking)
                        .accessibilityLabel("Régénérer le résumé")
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
                Text("Apple Intelligence rédige le résumé…")
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
                MarkdownWebView(document: MarkdownDocument(filename: "Résumé — \(sourceTitle)", text: summary),
                                tapped: $ignoredTap, onTitle: { _ in },
                                webController: web, onExternalLink: { _ in })
                summaryDisclaimer
            }
        }
    }

    private var summaryDisclaimer: some View {
        HStack(spacing: 6) {
            AppleIntelligenceGlyph(size: 12)
            Text("Résumé généré sur l’appareil par Apple Intelligence. Peut contenir des erreurs.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}
