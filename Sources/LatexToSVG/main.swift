import AppKit
import LatexRender

// TEMPORARY SPIKE -- replaced by the real app once the render chain is proven.
@MainActor
final class SpikeDelegate: NSObject, NSApplicationDelegate {
    let engine = RenderEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let result = try await engine.render(
                    latex: #"x = \sin \left( \frac{\pi}{2} \right)"#,
                    preamble: "",
                    displayMode: true
                )
                print("OK  widthEx=\(result.widthEx)  heightEx=\(result.heightEx)")
                print("SVG bytes: \(result.svg.utf8.count)")
                print(String(result.svg.prefix(300)))

                // A deliberately broken source, to confirm errors are recoverable
                // rather than fatal.
                do {
                    _ = try await engine.render(latex: #"\frac{"#, preamble: "", displayMode: true)
                    print("UNEXPECTED: bad TeX did not raise")
                } catch let RenderError.invalidTeX(message) {
                    print("bad TeX reported cleanly: \(message)")
                }
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
