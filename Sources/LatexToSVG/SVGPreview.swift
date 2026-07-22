import AppKit
import SwiftUI
import WebKit

/// Shows the finalized SVG exactly as it will be exported -- at its true pixel
/// size, so the scaling controls are WYSIWYG.
///
/// A web view is used rather than converting to an image because the SVG is
/// already the artefact being produced -- displaying it directly means the
/// preview cannot drift from the output.
struct SVGPreview: NSViewRepresentable {
    let svg: String?

    final class Coordinator {
        var lastLoadedKey: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.setValue(false, forKey: "drawsBackground")
        // The preview is not a browser; it should never scroll or bounce.
        view.enclosingScrollView?.hasVerticalScroller = false
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        // Reloading on every keystroke would flicker; the key changes only when
        // something visible actually changed.
        let key = svg ?? ""
        guard key != context.coordinator.lastLoadedKey else { return }
        context.coordinator.lastLoadedKey = key

        guard let svg else {
            view.loadHTMLString("<html><body style=\"background:transparent\"></body></html>",
                                baseURL: nil)
            return
        }

        // The equation is shown at its exact export size. `margin: auto` inside
        // a flex container centres it while it fits, and switches to scrollable
        // top-left alignment once it is larger than the pane -- unlike plain
        // centring, which would clip the edges of an oversized equation.
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
          html, body {
            margin: 0; width: 100%; height: 100%; background: transparent;
            display: flex; overflow: auto;
          }
          svg { margin: auto; flex-shrink: 0; }
        </style></head><body>\(svg)</body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
}
