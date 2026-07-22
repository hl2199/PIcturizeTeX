import AppKit
import LatexCore
import LatexRender

// TEMPORARY SPIKE -- proves the export chain before the UI is built on it.
@MainActor
final class SpikeDelegate: NSObject, NSApplicationDelegate {
    let engine = RenderEngine()
    let exporter = Exporter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let out = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("latex-spike")
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

                let result = try await engine.render(
                    latex: #"x = \sin \left( \frac{\pi}{2} \right)"#,
                    preamble: "",
                    displayMode: true
                )

                let svg = SVGDocument.finalize(rawSVG: result.svg,
                                               widthEx: result.widthEx,
                                               heightEx: result.heightEx,
                                               pixelsPerEx: 15,
                                               color: .custom("#0066cc"))
                let size = SVGDocument.pixelSize(widthEx: result.widthEx,
                                                 heightEx: result.heightEx,
                                                 pixelsPerEx: 15)
                print("size: \(size.width) x \(size.height) px")

                try SVGDocument.standaloneFile(svg: svg)
                    .write(to: out.appendingPathComponent("eq.svg"), atomically: true, encoding: .utf8)

                let pdf = try await exporter.pdfData(svg: svg, widthPx: size.width, heightPx: size.height)
                try pdf.write(to: out.appendingPathComponent("eq.pdf"))
                print("pdf bytes: \(pdf.count)")

                let png = try Exporter.pngData(pdf: pdf, dpi: 300)
                try png.write(to: out.appendingPathComponent("eq.png"))
                print("png bytes: \(png.count)")

                if let font = try await engine.pixelsPerEx(cssFont: "20px Helvetica") {
                    print("20px Helvetica -> \(font) px per ex")
                }
                if try await engine.pixelsPerEx(cssFont: "not a font") == nil {
                    print("invalid font string rejected cleanly")
                }

                print("OUT: \(out.path)")
                NSApp.terminate(nil)
            } catch {
                print("FAILED: \(error)")
                exit(1)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = SpikeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
