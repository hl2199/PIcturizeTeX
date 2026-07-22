import AppKit
import LatexCore
import LatexRender

// Generates the app icon: a Computer Modern pi, typeset by the app's own
// MathJax engine, in the app's carmine on the warm dotted paper of the desk.
// Run with the output directory as the only argument; writes AppIcon.iconset.
@MainActor
final class IconDelegate: NSObject, NSApplicationDelegate {
    let engine = RenderEngine()
    let exporter = Exporter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

                // The glyph, in the app's accent carmine.
                let r = try await engine.render(latex: #"\pi"#, preamble: "", displayMode: true)
                let svg = SVGDocument.finalize(rawSVG: r.svg, widthEx: r.widthEx, heightEx: r.heightEx,
                                               pixelsPerEx: 100, color: .custom("#9E312A"))
                let size = SVGDocument.pixelSize(widthEx: r.widthEx, heightEx: r.heightEx, pixelsPerEx: 100)
                let pdf = try await exporter.pdfData(svg: svg, widthPx: size.width, heightPx: size.height)
                // Rasterise so the glyph is ~480 px tall on the 1024 canvas.
                let glyphDPI = 96.0 * (960.0 / size.height)
                let glyphPNG = try Exporter.pngData(pdf: pdf, dpi: glyphDPI)
                guard let glyph = NSImage(data: glyphPNG) else {
                    throw RenderError.engineFailure("glyph PNG undecodable")
                }

                let master = Self.compose(glyph: glyph)

                // Emit the iconset. macOS wants each size and its @2x pair.
                let iconset = outDir.appendingPathComponent("AppIcon.iconset")
                try? FileManager.default.removeItem(at: iconset)
                try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
                for base in [16, 32, 128, 256, 512] {
                    try Self.writePNG(master, pixels: base,
                                      to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
                    try Self.writePNG(master, pixels: base * 2,
                                      to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
                }
                print("ICONSET: \(iconset.path)")
                exit(0)
            } catch {
                print("FAILED: \(error)")
                exit(1)
            }
        }
    }

    /// Draws the 1024-pt master: paper squircle, dot grid, centred glyph.
    static func compose(glyph: NSImage) -> NSImage {
        let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
        canvas.lockFocus()

        // Standard Big Sur icon grid: an 824-pt squircle centred on the canvas.
        let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = NSBezierPath(roundedRect: rect, xRadius: 186, yRadius: 186)

        // Soft drop shadow, as macOS icons carry their own.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.shadowBlurRadius = 24
        shadow.set()
        NSColor(srgbRed: 0.992, green: 0.988, blue: 0.976, alpha: 1).setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()

        // A whisper of a gradient so the paper reads as material.
        NSGradient(colors: [
            NSColor(srgbRed: 1.0, green: 0.997, blue: 0.99, alpha: 1),
            NSColor(srgbRed: 0.975, green: 0.968, blue: 0.95, alpha: 1),
        ])?.draw(in: squircle, angle: -90)

        // The desk's dot grid, clipped to the sheet.
        NSGraphicsContext.saveGraphicsState()
        squircle.setClip()
        NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 0.055).setFill()
        let step: CGFloat = 64
        var y = rect.minY + step / 2
        while y < rect.maxY {
            var x = rect.minX + step / 2
            while x < rect.maxX {
                NSBezierPath(ovalIn: NSRect(x: x - 4, y: y - 4, width: 8, height: 8)).fill()
                x += step
            }
            y += step
        }
        NSGraphicsContext.restoreGraphicsState()

        // The glyph, optically centred (a touch above geometric centre). Drawn
        // into an explicit rect: the exporter stamps the PNG with its true
        // export point size, which is far smaller than the icon needs.
        let targetHeight: CGFloat = 460
        let aspect = glyph.size.width / glyph.size.height
        let gRect = NSRect(x: rect.midX - targetHeight * aspect / 2,
                           y: rect.midY - targetHeight / 2 + 10,
                           width: targetHeight * aspect,
                           height: targetHeight)
        glyph.draw(in: gRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        canvas.unlockFocus()
        return canvas
    }

    static func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            throw RenderError.engineFailure("bitmap alloc failed")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw RenderError.engineFailure("png encode failed")
        }
        try data.write(to: url)
    }
}

let app = NSApplication.shared
let delegate = IconDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
