import AppKit
import CoreGraphics
import Foundation
import LatexCore
import WebKit

/// Turns a finalized SVG into the formats the user can save, copy, or drag.
///
/// The formats form a chain -- SVG to PDF to PNG -- so that each step starts
/// from vector data. In particular the PNG is rasterised from the PDF rather
/// than captured from the on-screen preview, which is what keeps it sharp at
/// any resolution instead of being pinned to the display's pixel density.
@MainActor
public final class Exporter {

    /// CSS pixels are defined at 96 per inch, so this is the DPI at which one
    /// SVG pixel equals one output pixel.
    public nonisolated static let nativeDPI: Double = 96

    private var webView: WKWebView?
    /// WebKit only builds a layer tree for a view that belongs to a window, so
    /// the export view is hosted in a real window parked far offscreen. Without
    /// it `createPDF` returns a page containing only the background.
    private var hostWindow: NSWindow?

    public init() {}

    /// Renders the SVG to a vector PDF whose page is exactly the size of the
    /// equation, with no surrounding whitespace.
    public func pdfData(svg: String, widthPx: Double, heightPx: Double) async throws -> Data {
        guard widthPx > 0, heightPx > 0 else {
            throw RenderError.engineFailure("Cannot export an equation with zero size.")
        }

        // Quartz truncates the media box to whole points, so a fractional size
        // would shave the right and bottom edges off the artwork. Rounding up
        // costs at most one point of transparent margin and never clips.
        let pageWidth = widthPx.rounded(.up)
        let pageHeight = heightPx.rounded(.up)

        let view = reusableWebView(width: pageWidth, height: pageHeight)

        // The wrapper strips the default body margin; without it the equation is
        // inset by 8 points and the page size no longer matches the artwork.
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        html, body { margin: 0; padding: 0; background: transparent; }
        svg { display: block; }
        </style></head><body>\(svg)</body></html>
        """

        try await load(html, into: view)

        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        do {
            return try await view.pdf(configuration: config)
        } catch {
            throw RenderError.engineFailure("PDF export failed: \(error.localizedDescription)")
        }
    }

    /// Rasterises a PDF at the requested resolution, preserving transparency.
    ///
    /// Nonisolated because it touches only Core Graphics, so callers can move it
    /// off the main actor if a very large export ever warrants it.
    public nonisolated static func pngData(pdf: Data, dpi: Double) throws -> Data {
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            throw RenderError.engineFailure("The generated PDF could not be read back.")
        }

        let box = page.getBoxRect(.mediaBox)
        let scale = max(dpi, 1) / nativeDPI
        let width = Int((box.width * scale).rounded())
        let height = Int((box.height * scale).rounded())
        guard width > 0, height > 0 else {
            throw RenderError.engineFailure("Cannot rasterise an equation with zero size.")
        }

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RenderError.engineFailure("Could not allocate a bitmap for the PNG.")
        }

        // No background fill: the bitmap starts fully transparent, so the PNG
        // drops onto any coloured slide without a white box around it.
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.origin.x, y: -box.origin.y)
        context.drawPDFPage(page)

        guard let image = context.makeImage() else {
            throw RenderError.engineFailure("Could not rasterise the equation.")
        }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: box.width, height: box.height)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw RenderError.engineFailure("Could not encode the PNG.")
        }
        return data
    }

    // MARK: - Web view plumbing

    private func reusableWebView(width: Double, height: Double) -> WKWebView {
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        if let existing = webView {
            existing.frame = frame
            hostWindow?.setContentSize(NSSize(width: width, height: height))
            return existing
        }

        let created = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        // Keeps the exported page transparent rather than opaque white.
        created.setValue(false, forKey: "drawsBackground")

        // Parked far offscreen so it can never appear on any display, while
        // still being a genuine window as far as WebKit is concerned.
        let window = NSWindow(contentRect: CGRect(x: -30000, y: -30000,
                                                  width: width, height: height),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = created
        window.orderFrontRegardless()

        hostWindow = window
        webView = created
        return created
    }

    private func load(_ html: String, into view: WKWebView) async throws {
        view.loadHTMLString(html, baseURL: nil)

        // The SVG is self-contained with no external references, so the only
        // thing being waited on is layout and a paint cycle. Waiting on two
        // animation frames rather than readyState alone ensures WebKit has
        // actually composited the artwork before it is captured.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let done = try? await view.evaluateJavaScript("document.readyState") as? String,
               done == "complete" {
                _ = try? await view.evaluateJavaScript("""
                new Promise(function (resolve) {
                  requestAnimationFrame(function () {
                    requestAnimationFrame(function () { resolve(true); });
                  });
                })
                """)
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        throw RenderError.engineFailure("Timed out preparing the equation for export.")
    }
}
