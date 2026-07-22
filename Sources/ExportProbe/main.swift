import AppKit
import CoreGraphics
import LatexCore
import LatexRender

// Diagnostic harness: renders an equation and exports it through the real
// Exporter, then counts opaque pixels in the PNG to prove the PDF was not
// blank. Used to validate changes to the exporter's window hosting.
@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let engine = RenderEngine()
    let exporter = Exporter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                // Inline once truncated to the first atom (MathJax 4 inline
                // linebreaking); both modes must produce a full-width equation.
                for display in [true, false] {
                    do {
                        let t = try await engine.render(
                            latex: #"x = \sin \left( \frac{\pi}{2} \right)"#,
                            preamble: "", displayMode: display)
                        print("PROBE display=\(display): \(t.widthEx) x \(t.heightEx) ex, svg=\(t.svg.count) chars")
                    } catch {
                        print("PROBE display=\(display) FAILED: \(error)")
                    }
                }

                let r = try await engine.render(latex: #"E = mc^2"#, preamble: "", displayMode: true)
                let svg = SVGDocument.finalize(rawSVG: r.svg, widthEx: r.widthEx, heightEx: r.heightEx,
                                               pixelsPerEx: 8, color: .black)
                let size = SVGDocument.pixelSize(widthEx: r.widthEx, heightEx: r.heightEx, pixelsPerEx: 8)
                let pdf = try await exporter.pdfData(svg: svg, widthPx: size.width, heightPx: size.height)
                let png = try Exporter.pngData(pdf: pdf, dpi: 192)

                guard let rep = NSBitmapImageRep(data: png) else { print("PROBE: png undecodable"); exit(1) }
                var opaque = 0
                for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                    for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                        if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { opaque += 1 }
                    }
                }
                print("PROBE: pdf=\(pdf.count)B png=\(png.count)B opaque=\(opaque)")
                print(opaque > 20 ? "PROBE: ARTWORK PRESENT" : "PROBE: BLANK OUTPUT")
                exit(opaque > 20 ? 0 : 1)
            } catch {
                print("PROBE FAILED: \(error)")
                exit(1)
            }
        }
    }
}
let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
