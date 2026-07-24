import AppKit
import Foundation
import LatexCore
import LatexRender
import Observation

/// Which colour control the user has selected. Kept separate from `ColorMode`
/// so that switching to Black and back does not discard the chosen custom
/// colour.
enum ColorChoice: String, CaseIterable, Identifiable {
    case black, white, custom
    var id: String { rawValue }
}

/// Which scaling control is active. Separate from `ScaleMode` for the same
/// reason as `ColorChoice`.
enum ScaleChoice: String, CaseIterable, Identifiable {
    case standard, matchFont, manual
    var id: String { rawValue }
}

/// All application state, and the only place that talks to the render engine.
@MainActor
@Observable
final class AppModel {

    // MARK: Input

    var latex: String = #"x = \sin \left( \frac{\pi}{2} \right)"# {
        didSet { scheduleRender() }
    }

    var preamble: String = "" {
        didSet {
            preambleStore?.text = preamble
            scheduleRender()
        }
    }

    // MARK: Settings

    var displayMode = true { didSet { scheduleRender() } }
    var colorChoice: ColorChoice = .black { didSet { scheduleRender() } }
    var customColorText = "#0066cc" { didSet { scheduleRender() } }
    var scaleChoice: ScaleChoice = .standard { didSet { scheduleRender() } }
    var fontFamily = "Helvetica" { didSet { scheduleRender() } }
    var fontSize: Double = 20 { didSet { scheduleRender() } }
    var manualPixelsPerEx: Double = 15 { didSet { scheduleRender() } }

    /// The CSS font shorthand the measurement engine expects, assembled from
    /// the two separate controls.
    var fontCSS: String { "\(SVGDocument.format(fontSize))px \"\(fontFamily)\"" }

    // MARK: Export options

    var pngDPI: Double = 300 { didSet { refreshExportCache() } }
    /// A drag produces exactly one file, so unlike the clipboard it must commit
    /// to a single format. PDF pastes as vector into the widest range of apps.
    var dragFormat: ExportFormat = .pdf

    // MARK: View state

    /// Restored from the previous session, so the sidebar comes back the way
    /// it was left. Open on a fresh install.
    var showHistory = UserDefaults.standard.object(forKey: "showHistory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHistory, forKey: "showHistory") }
    }

    // MARK: Output

    private(set) var renderedSVG: String?
    private(set) var pixelWidth: Double = 0
    private(set) var pixelHeight: Double = 0
    /// Non-nil when the current source failed to render. The previous SVG stays
    /// in `renderedSVG` so the preview does not blank out mid-keystroke.
    private(set) var errorMessage: String?
    private(set) var isRendering = false

    private(set) var history: [HistoryEntry] = []

    /// Ready-made PDF and PNG for the current render.
    ///
    /// Filled in the background after every successful render, because drag
    /// flavours are demanded synchronously mid-drag -- there is no opportunity
    /// to run the async export pipeline once the mouse is moving. Tagged with
    /// the SVG it was built from so staleness is detectable.
    struct ExportCache {
        let svg: String
        let pdf: Data
        let png: Data
        let dpi: Double
    }
    private(set) var exportCache: ExportCache?
    private var cacheTask: Task<Void, Never>?

    /// The cache, but only if it matches what is currently on screen.
    var freshExportCache: ExportCache? {
        guard let cache = exportCache, cache.svg == renderedSVG else { return nil }
        return cache
    }

    // MARK: Collaborators

    private let engine = RenderEngine()
    private let exporter = Exporter()
    private var historyStore: HistoryStore?
    private var preambleStore: PreambleStore?
    private var renderTask: Task<Void, Never>?
    /// Last successfully measured factor for the current font string, so a
    /// half-typed font name does not collapse the equation to nothing.
    private var lastMeasuredPixelsPerEx: Double?

    /// True for the menu bar companion: a second, simpler instance that always
    /// renders in display mode and does not write history, so it can never
    /// clobber the main window's history file.
    let isMenuBarLite: Bool

    init(menuBarLite: Bool = false) {
        isMenuBarLite = menuBarLite
        // Storage failures must not prevent the app from running; the user
        // simply gets a session without history rather than no app at all.
        historyStore = menuBarLite ? nil : try? HistoryStore()
        // The preamble is read either way, so equations render identically in
        // both places; only the main window edits it.
        preambleStore = try? PreambleStore()
        preamble = preambleStore?.text ?? ""
        history = historyStore?.entries ?? []
    }

    // MARK: - Settings snapshot

    var colorMode: ColorMode {
        switch colorChoice {
        case .black: return .black
        case .white: return .white
        case .custom: return .custom(customColorText)
        }
    }

    /// The colour the equation currently renders in, whichever mode produced
    /// it -- what the colour wells display.
    var effectiveColor: NSColor {
        switch colorChoice {
        case .black: return .black
        case .white: return .white
        case .custom: return NSColor(css: customColorText) ?? .black
        }
    }

    /// Whether the preview needs a dark surface behind the equation. A white or
    /// pale equation on the default light background would be invisible.
    var previewNeedsDarkBackground: Bool {
        switch colorChoice {
        case .black: return false
        case .white: return true
        case .custom:
            guard let color = NSColor(css: customColorText)?.usingColorSpace(.sRGB) else {
                return false
            }
            // Relative luminance, roughly: bright colours need the dark surface.
            let luminance = 0.2126 * color.redComponent
                          + 0.7152 * color.greenComponent
                          + 0.0722 * color.blueComponent
            return luminance > 0.7
        }
    }

    var scaleMode: ScaleMode {
        switch scaleChoice {
        case .standard: return .standard
        case .matchFont: return .matchFont(fontCSS)
        case .manual: return .manual(manualPixelsPerEx)
        }
    }

    var currentSettings: RenderSettings {
        RenderSettings(displayMode: displayMode, color: colorMode, scale: scaleMode)
    }

    // MARK: - Rendering

    /// Debounces renders so that typing does not queue one job per keystroke.
    func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await render()
        }
    }

    /// Renders immediately, skipping the debounce, for launch and history
    /// restore.
    func renderNow() {
        renderTask?.cancel()
        renderTask = Task { await render() }
    }

    private func render() async {
        isRendering = true
        defer { isRendering = false }

        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renderedSVG = nil
            errorMessage = nil
            pixelWidth = 0
            pixelHeight = 0
            return
        }

        do {
            let result = try await engine.render(latex: latex,
                                                 preamble: preamble,
                                                 displayMode: displayMode)
            let factor = await resolvedPixelsPerEx()
            let size = SVGDocument.pixelSize(widthEx: result.widthEx,
                                             heightEx: result.heightEx,
                                             pixelsPerEx: factor)
            renderedSVG = SVGDocument.finalize(rawSVG: result.svg,
                                               widthEx: result.widthEx,
                                               heightEx: result.heightEx,
                                               pixelsPerEx: factor,
                                               color: colorMode)
            pixelWidth = size.width
            pixelHeight = size.height
            errorMessage = nil
            refreshExportCache()
        } catch let RenderError.invalidTeX(message) {
            // Recoverable: keep the last good preview on screen.
            errorMessage = message
        } catch let RenderError.engineFailure(message) {
            errorMessage = "Render engine problem: \(message)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedPixelsPerEx() async -> Double {
        switch scaleChoice {
        case .standard:
            return Scaling.defaultPixelsPerEx
        case .manual:
            return manualPixelsPerEx
        case .matchFont:
            // `try?` flattens the engine's optional result, so a nil here means
            // either a measurement failure or an unusable font string.
            if let measured = try? await engine.pixelsPerEx(cssFont: fontCSS) {
                lastMeasuredPixelsPerEx = measured
                return measured
            }
            return lastMeasuredPixelsPerEx ?? Scaling.defaultPixelsPerEx
        }
    }

    // MARK: - Export

    private func refreshExportCache() {
        cacheTask?.cancel()
        guard let svg = renderedSVG, pixelWidth > 0, pixelHeight > 0 else {
            exportCache = nil
            return
        }
        let (width, height, dpi) = (pixelWidth, pixelHeight, pngDPI)
        cacheTask = Task {
            do {
                let pdf = try await exporter.pdfData(svg: svg, widthPx: width, heightPx: height)
                let png = try Exporter.pngData(pdf: pdf, dpi: dpi)
                guard !Task.isCancelled else { return }
                exportCache = ExportCache(svg: svg, pdf: pdf, png: png, dpi: dpi)
            } catch {
                // Exports fall back to generating on demand; nothing to do here.
            }
        }
    }

    /// Builds the bytes for one format from the current render, using the
    /// cache when it is fresh.
    func data(for format: ExportFormat) async throws -> Data {
        guard let svg = renderedSVG, pixelWidth > 0, pixelHeight > 0 else {
            throw RenderError.engineFailure("There is nothing to export yet.")
        }
        if format == .svg {
            return Data(SVGDocument.standaloneFile(svg: svg).utf8)
        }

        // Wait for any in-flight cache build rather than racing it for the
        // shared export web view.
        await cacheTask?.value
        if let cache = freshExportCache {
            switch format {
            case .pdf:
                return cache.pdf
            case .png where cache.dpi == pngDPI:
                return cache.png
            case .png:
                return try Exporter.pngData(pdf: cache.pdf, dpi: pngDPI)
            case .svg:
                break
            }
        }

        // The cache build failed or is stale; generate directly.
        let pdf = try await exporter.pdfData(svg: svg, widthPx: pixelWidth, heightPx: pixelHeight)
        if format == .pdf { return pdf }
        return try Exporter.pngData(pdf: pdf, dpi: pngDPI)
    }

    /// Records the current equation in history. Called on export rather than on
    /// render, so the list holds finished equations instead of fragments.
    func recordInHistory() {
        guard let store = historyStore else { return }
        store.record(latex: latex, settings: currentSettings, svg: renderedSVG)
        history = store.entries
    }

    func restore(_ entry: HistoryEntry) {
        latex = entry.latex
        displayMode = entry.settings.displayMode

        switch entry.settings.color {
        case .black: colorChoice = .black
        case .white: colorChoice = .white
        case .custom(let value):
            colorChoice = .custom
            customColorText = value
        }

        switch entry.settings.scale {
        case .standard: scaleChoice = .standard
        case .manual(let value):
            scaleChoice = .manual
            manualPixelsPerEx = value
        case .matchFont(let css):
            scaleChoice = .matchFont
            // History stores the assembled shorthand; split it back into the
            // two controls. An unparseable value keeps the current fields.
            if let match = css.firstMatch(of: /^\s*([0-9.]+)px\s+"?([^"]+?)"?\s*$/) {
                fontSize = Double(match.1) ?? fontSize
                fontFamily = String(match.2)
            }
        }
        renderNow()
    }

    func deleteHistoryEntry(id: UUID) {
        historyStore?.delete(id: id)
        history = historyStore?.entries ?? []
    }

    func clearHistory() {
        historyStore?.clear()
        history = []
    }
}
