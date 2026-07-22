import AppKit
import SwiftUI
import WebKit

/// Shows the finalized SVG exactly as it will be exported.
///
/// A web view is used rather than converting to an image because the SVG is
/// already the artefact being produced -- displaying it directly means the
/// preview cannot drift from the output.
struct SVGPreview: NSViewRepresentable {
    let svg: String?
    /// Colour the equation inherits in "container colour" mode. Passed in from
    /// SwiftUI so the preview follows light and dark appearance.
    let inheritedColor: NSColor
    /// Scales the displayed equation. Export is unaffected.
    let zoom: Double

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
        let hex = inheritedColor.usingColorSpace(.sRGB).map {
            String(format: "#%02X%02X%02X",
                   Int(round($0.redComponent * 255)),
                   Int(round($0.greenComponent * 255)),
                   Int(round($0.blueComponent * 255)))
        } ?? "#000000"

        // Reloading on every keystroke would flicker; the key changes only when
        // something visible actually changed.
        let key = "\(hex)|\(zoom)|\(svg ?? "")"
        guard key != context.coordinator.lastLoadedKey else { return }
        context.coordinator.lastLoadedKey = key

        guard let svg else {
            view.loadHTMLString("<html><body style=\"background:transparent\"></body></html>",
                                baseURL: nil)
            return
        }

        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
          html, body {
            margin: 0; height: 100%; background: transparent;
            display: flex; align-items: center; justify-content: center;
            overflow: hidden;
            /* In "container colour" mode the equation draws with currentColor,
               so this is what makes it follow the app's appearance. */
            color: \(hex);
          }
          svg { max-width: 96%; max-height: 96%; transform: scale(\(zoom)); }
        </style></head><body>\(svg)</body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
}
