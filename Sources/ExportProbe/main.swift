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
                // With PKGPROBE=1, sweep package-specific syntax instead of
                // the standard checks: reports which LaTeX packages' commands
                // the bundled MathJax actually accepts.
                if ProcessInfo.processInfo.environment["PKGPROBE"] != nil {
                    let cases: [(String, String)] = [
                        ("ams align", #"\begin{align} a &= b \ c &= d \end{align}"#),
                        ("ams matrices", #"\begin{pmatrix} a & b \ c & d \end{pmatrix}"#),
                        ("physics dv", #"\dv{f}{x} + \pdv[2]{g}{t}"#),
                        ("physics abs norm", #"\abs{x} \norm{v}"#),
                        ("physics comm", #"\comm{\hat{H}}{\hat{p}}"#),
                        ("braket", #"\ket{\psi} \bra{\phi} \braket{\phi|\psi}"#),
                        ("mhchem ce", #"\ce{2H2 + O2 -> 2H2O}"#),
                        ("cancel", #"\cancel{x} + \bcancel{y}"#),
                        ("boldsymbol", #"\boldsymbol{\alpha}"#),
                        ("mathtools coloneqq", #"x \coloneqq y"#),
                        ("mathtools dcases", #"\begin{dcases} a & x>0 \ b & x<0 \end{dcases}"#),
                        ("upgreek", #"\upalpha"#),
                        // noundefined renders unknown commands as red literal text rather
                        // than erroring, so unsupported packages "succeed" visually wrong.
                        ("siunitx (unsupported, renders red)", #"\SI{3e8}{\metre\per\second}"#),
                        ("tikz (expect fail)", #"\begin{tikzpicture}\end{tikzpicture}"#),
                        ("usepackage (unsupported, renders red)", #"\usepackage{physics} x"#),
                        ("preamble newcommand", #"\R^n"#),
                    ]
                    for (name, tex) in cases {
                        let preamble = name.hasPrefix("preamble")
                            ? #"\newcommand{\R}{\mathbb{R}}"# : ""
                        do {
                            let r = try await engine.render(latex: tex, preamble: preamble,
                                                            displayMode: true)
                            print("PKG OK    \(name)  (\(r.widthEx) ex wide)")
                        } catch let RenderError.invalidTeX(msg) {
                            print("PKG FAIL  \(name): \(msg)")
                        }
                    }
                    exit(0)
                }

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
