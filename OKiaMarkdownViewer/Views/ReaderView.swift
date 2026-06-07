import SwiftUI

/// Displays a rendered Markdown document with a title bar (TOC, search, share, open),
/// an in-document search bar, and the full-screen diagram zoom overlay.
struct ReaderView: View {
    let document: MarkdownDocument
    var onOpen: () -> Void
    var onHome: () -> Void

    @StateObject private var web = ReaderWebController()
    @State private var tapped: TappedDiagram?
    @State private var title: String = ""

    @State private var showTOC = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var showShareOptions = false
    @State private var sharePayload: SharePayload?
    @State private var externalLink: ExternalLink?
    @FocusState private var searchFocused: Bool

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        ZStack(alignment: .top) {
            MarkdownWebView(document: document, tapped: $tapped, onTitle: { title = $0 },
                            webController: web, onExternalLink: handleExternalLink)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                titleBar
                if isSearching { searchBar }
            }
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
        .sheet(item: $externalLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .confirmationDialog("Partager", isPresented: $showShareOptions, titleVisibility: .visible) {
            Button("Exporter en PDF") { exportPDF() }
            Button("Partager le Markdown (.md)") { shareMarkdown() }
            Button("Annuler", role: .cancel) {}
        }
        // Reset transient UI when the document changes.
        .onChange(of: document.id) { _, _ in
            isSearching = false; searchText = ""; web.clearSearch(); showTOC = false
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

    // MARK: External links

    private func handleExternalLink(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            externalLink = ExternalLink(url: url)          // in-app Safari with "Done"
        } else {
            UIApplication.shared.open(url)                 // mailto:, tel: → system handler
        }
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
