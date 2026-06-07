import SwiftUI
import WebKit

/// Controls the zoom web view (fit-to-screen, double-tap toggle).
final class ZoomController: ObservableObject {
    weak var scrollView: UIScrollView?

    func fitToScreen(animated: Bool = true) {
        guard let sv = scrollView else { return }
        sv.setZoomScale(sv.minimumZoomScale, animated: animated)
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

            ZoomWebView(svg: diagram.svg, controller: controller)
                .ignoresSafeArea()
                .offset(y: dragOffset)

            chrome
        }
        .statusBarHidden(true)
    }

    private var chrome: some View {
        HStack {
            Button(action: { controller.fitToScreen() }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Ajuster à l’écran")

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
            .accessibilityLabel("Fermer")
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

/// WKWebView hosting the SVG with native scroll-view zoom/pan.
private struct ZoomWebView: UIViewRepresentable {
    let svg: String
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
        controller.scrollView = webView.scrollView

        // Double-tap toggle (added on top of the web content).
        let dbl = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        webView.scrollView.addGestureRecognizer(dbl)

        let baseURL = Bundle.main.url(forResource: "renderer", withExtension: "html", subdirectory: "Web")?
            .deletingLastPathComponent()
        webView.loadHTMLString(Self.wrap(svg: svg), baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func wrap(svg: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=0.5, maximum-scale=6, user-scalable=yes">
        <link rel="stylesheet" href="style.css">
        <style>
          html,body{margin:0;height:100%;}
          /* Light framed canvas so the OK-ia mermaid palette stays true even in dark mode */
          body{background:#FAFAF8;display:flex;align-items:center;justify-content:center;}
          .wrap{min-width:100%;min-height:100%;display:flex;align-items:center;justify-content:center;
                padding:24px;box-sizing:border-box;}
          .wrap svg{max-width:100%;height:auto;display:block;}
        </style></head>
        <body><div class="wrap">\(svg)</div></body></html>
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
