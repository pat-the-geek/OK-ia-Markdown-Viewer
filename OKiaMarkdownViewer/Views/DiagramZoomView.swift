import SwiftUI
import WebKit

/// Controls the zoom web view (fit-to-screen, double-tap toggle).
final class ZoomController: ObservableObject {
    weak var scrollView: UIScrollView?

    func fitToScreen(animated: Bool = true) {
        guard let sv = scrollView else { return }
        sv.setZoomScale(sv.minimumZoomScale, animated: animated)
    }

    func zoomIn()  { zoomBy(1.4) }
    func zoomOut() { zoomBy(1 / 1.4) }

    private func zoomBy(_ factor: CGFloat) {
        guard let sv = scrollView else { return }
        let target = min(sv.maximumZoomScale, max(sv.minimumZoomScale, sv.zoomScale * factor))
        sv.setZoomScale(target, animated: true)
    }

    func toggleZoom(at point: CGPoint) {
        guard let sv = scrollView else { return }
        if sv.zoomScale > sv.minimumZoomScale * 1.05 {
            sv.setZoomScale(sv.minimumZoomScale, animated: true)
        } else {
            let target = min(sv.maximumZoomScale, sv.minimumZoomScale * 3)
            let size = sv.bounds.size
            let w = size.width / target, h = size.height / target
            let rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
            sv.zoom(to: rect, animated: true)
        }
    }
}

/// Full-screen, vector-crisp diagram viewer. The SVG is rendered inside a WKWebView whose
/// scroll view provides native pinch-to-zoom and pan; double-tap toggles fit ↔ zoom.
struct DiagramZoomView: View {
    let diagram: TappedDiagram
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = ZoomController()
    @State private var dragOffset: CGFloat = 0

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(1 - min(Double(dragOffset) / 400, 0.6))
                .ignoresSafeArea()

            ZoomWebView(bodyHTML: diagram.svg, controller: controller)
                .ignoresSafeArea()
                .offset(y: dragOffset)

            chrome
        }
        .overlay(alignment: .bottom) { zoomBar }
        .statusBarHidden(true)
    }

    private var zoomBar: some View {
        HStack(spacing: 0) {
            Button { controller.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 56, height: 44)
            }
            .accessibilityLabel(tr("Dézoomer"))

            Divider().frame(height: 24).overlay(Color.white.opacity(0.25))

            Button { controller.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 56, height: 44)
            }
            .accessibilityLabel(tr("Zoomer"))
        }
        .tint(orange)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .padding(.bottom, 28)
        .offset(y: dragOffset)
    }

    private var chrome: some View {
        HStack {
            Button(action: { controller.fitToScreen() }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(tr("Ajuster à l’écran"))

            Spacer()

            if !diagram.title.isEmpty {
                Text(diagram.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(tr("Fermer (accessibilité)"))
        }
        .tint(orange)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Swipe-down on the top chrome dismisses, without fighting the pan gesture below.
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 { dragOffset = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 { dismiss() }
                    else { withAnimation(.spring()) { dragOffset = 0 } }
                }
        )
    }
}

/// WKWebView hosting arbitrary centred content (an SVG diagram or an `<img>`)
/// with native scroll-view zoom/pan.
private struct ZoomWebView: UIViewRepresentable {
    let bodyHTML: String
    let controller: ZoomController

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.maximumZoomScale = 6
        webView.scrollView.minimumZoomScale = 0.5
        webView.scrollView.bouncesZoom = true
        // Le fond clair va d'un bord à l'autre : sans cela, la vue gardait les marges de sécurité
        // et le noir de dessous bordait la page en haut et en bas.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        controller.scrollView = webView.scrollView

        // Double-tap toggle (added on top of the web content).
        let dbl = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        webView.scrollView.addGestureRecognizer(dbl)

        let baseURL = Bundle.main.url(forResource: "renderer", withExtension: "html", subdirectory: "Web")?
            .deletingLastPathComponent()
        webView.loadHTMLString(Self.wrap(bodyHTML: bodyHTML), baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func wrap(bodyHTML: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=0.5, maximum-scale=6, user-scalable=yes, viewport-fit=cover">
        <link rel="stylesheet" href="style.css">
        <style>
          html,body{margin:0;height:100%;}
          /* Light framed canvas so the OK-ia mermaid palette stays true even in dark mode */
          body{background:#FAFAF8;display:flex;align-items:safe center;justify-content:safe center;}
          .wrap{min-width:100%;min-height:100%;display:flex;align-items:safe center;justify-content:safe center;
                padding:24px;box-sizing:border-box;}
          /* Un bloc plus haut que l'écran commence sous les boutons du haut et finit au-dessus
             de ceux du zoom : le fond va d'un bord à l'autre, pas le contenu. */
          .wrap{padding:calc(env(safe-area-inset-top) + 64px) max(24px, env(safe-area-inset-right))
                calc(env(safe-area-inset-bottom) + 88px) max(24px, env(safe-area-inset-left));}
          /* Une largeur toujours définie : un SVG à largeur « auto » dans ce cadre souple sortait
             réduit à rien. */
          .wrap > svg{width:100% !important;max-height:none !important;height:auto;display:block;}
          .wrap img{max-width:100%;max-height:100%;height:auto;display:block;border-radius:8px;}
          /* Un bloc de texte agrandi — chronologie, tableau : en entier, sans retour à la ligne. */
          .okia-zoom-bloc{max-width:none;margin:0;padding:0;font-size:17px;}
          .okia-zoom-bloc pre{white-space:pre;overflow:visible;margin:0;cursor:auto;}
          .okia-zoom-bloc pre::after{content:none;}
          .okia-zoom-bloc table{width:auto;margin:0;cursor:auto;}
          .okia-zoom-bloc .okia-ligne{display:block;}
          /* Écran étroit : la chronologie passe à la ligne, chaque suite alignée après la flèche. */
          .okia-zoom-bloc.okia-replie{font-size:14px;}
          .okia-zoom-bloc.okia-replie pre{white-space:pre-wrap;}
          .okia-zoom-bloc.okia-replie .okia-ligne{padding-left:var(--retrait);text-indent:calc(-1 * var(--retrait));}
          .okia-zoom-bloc.okia-replie .okia-ligne + .okia-ligne{margin-top:.5em;}
        </style></head>
        <body><div class="wrap">\(bodyHTML)</div>
        <script>
          // Un bloc plus large que l'écran (une chronologie aux longues lignes) s'ouvre en entier,
          // réduit à la largeur ; le pincement l'agrandit ensuite. Si la réduction le rendait
          // illisible (iPhone en portrait), une chronologie passe plutôt à la ligne, et un tableau
          // garde une taille lisible et défile. Mesuré au chargement et à chaque rotation : au
          // premier passage, la vue n'a pas encore sa taille.
          (function () {
            var b = document.querySelector('.okia-zoom-bloc');
            if (!b) return;
            var pre = b.querySelector('pre'), code = pre && (pre.querySelector('code') || pre);
            var lignes = false;
            if (code && code.children.length === 0) {
              var texte = code.textContent.replace(/\\n$/, '').split('\\n');
              var fleche = texte[0].indexOf('→');
              pre.style.setProperty('--retrait', (fleche > 0 ? fleche + 2 : 4) + 'ch');
              code.textContent = '';
              texte.forEach(function (l) {
                var s = document.createElement('span');
                s.className = 'okia-ligne';
                s.textContent = l || ' ';
                code.appendChild(s);
              });
              lignes = true;
            }
            function ajuster() {
              var dispo = window.innerWidth - 48;
              if (!(dispo > 0)) return;
              b.style.zoom = ''; b.style.width = ''; b.classList.remove('okia-replie');
              var l = b.scrollWidth;
              if (l <= dispo) return;
              var z = dispo / l;
              if (z >= 0.6) { b.style.zoom = z.toFixed(3); return; }
              if (lignes) { b.classList.add('okia-replie'); b.style.width = dispo + 'px'; return; }
              b.style.zoom = '0.6';
            }
            ajuster();
            window.addEventListener('load', ajuster);
            window.addEventListener('resize', ajuster);
          })();
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let controller: ZoomController
        init(_ controller: ZoomController) { self.controller = controller }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.subviews.first
        }

        @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            let point = gr.location(in: gr.view)
            controller.toggleZoom(at: point)
        }
    }
}

// MARK: - Full-screen image viewer

/// An image the user tapped, ready to be shown full-screen.
struct TappedImage: Identifiable, Equatable {
    let id = UUID()
    let src: String
}

/// Full-screen, pinch-to-zoom image viewer. Reuses the same zoom web view as the
/// diagram viewer, wrapping the source in an `<img>` on a dark canvas.
struct ImageZoomView: View {
    let image: TappedImage
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = ZoomController()
    @State private var dragOffset: CGFloat = 0

    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(1 - min(Double(dragOffset) / 400, 0.6))
                .ignoresSafeArea()

            ZoomWebView(bodyHTML: Self.imgTag(image.src), controller: controller)
                .ignoresSafeArea()
                .offset(y: dragOffset)

            chrome
        }
        .overlay(alignment: .bottom) { zoomBar }
        .statusBarHidden(true)
    }

    private static func imgTag(_ src: String) -> String {
        let escaped = src
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return "<img src=\"\(escaped)\" alt=\"\">"
    }

    private var zoomBar: some View {
        HStack(spacing: 0) {
            Button { controller.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 56, height: 44)
            }
            .accessibilityLabel(tr("Dézoomer"))

            Divider().frame(height: 24).overlay(Color.white.opacity(0.25))

            Button { controller.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 56, height: 44)
            }
            .accessibilityLabel(tr("Zoomer"))
        }
        .tint(orange)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .padding(.bottom, 28)
        .offset(y: dragOffset)
    }

    private var chrome: some View {
        HStack {
            Button(action: { controller.fitToScreen() }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(tr("Ajuster à l’écran"))

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(tr("Fermer (accessibilité)"))
        }
        .tint(orange)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 { dragOffset = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 { dismiss() }
                    else { withAnimation(.spring()) { dragOffset = 0 } }
                }
        )
    }
}

// MARK: - Carte en plein écran

/// Une carte touchée dans le livre, à ouvrir en plein écran : sa configuration, telle que la page
/// l'a reçue (base64 du JSON).
struct TappedCarte: Identifiable, Equatable {
    let id = UUID()
    let cfg: String
}

/// La carte seule, sur tout l'écran : la même pile que le lecteur (Leaflet + MapLibre), sa
/// navigation à deux doigts, et un bouton pour revenir au livre.
struct CarteZoomView: View {
    let carte: TappedCarte
    @Environment(\.dismiss) private var dismiss
    private let orange = Color(red: 0xE8/255, green: 0x97/255, blue: 0x2E/255)

    var body: some View {
        CarteWebView(cfg: carte.cfg)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .tint(orange)
                .padding(16)
                .accessibilityLabel(tr("Fermer (accessibilité)"))
            }
            .statusBarHidden(true)
    }
}

private struct CarteWebView: UIViewRepresentable {
    let cfg: String

    func makeCoordinator() -> Coordinator { Coordinator(cfg: cfg) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: "window.OKIA_LANG = '\(Localization.shared.code)';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let vue = WKWebView(frame: .zero, configuration: config)
        vue.navigationDelegate = context.coordinator
        vue.scrollView.isScrollEnabled = false
        vue.scrollView.contentInsetAdjustmentBehavior = .never
        if let page = Bundle.main.url(forResource: "renderer", withExtension: "html", subdirectory: "Web")
            ?? Bundle.main.url(forResource: "renderer", withExtension: "html") {
            vue.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return vue
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let cfg: String
        init(cfg: String) { self.cfg = cfg }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let sur = cfg.filter { $0.isLetter || $0.isNumber || "+/=".contains($0) }
            webView.evaluateJavaScript("window.OKIA && window.OKIA.carteSeule('\(sur)')")
        }
    }
}
